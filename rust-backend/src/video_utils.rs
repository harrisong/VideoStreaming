use tokio::process::Command;
use serde_json::Value;
use log::{info, error};

pub async fn extract_video_duration(file_path: &str) -> Result<i32, Box<dyn std::error::Error + Send + Sync>> {
    info!("Extracting duration from video: {}", file_path);
    
    let output = Command::new("ffprobe")
        .args(&[
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            file_path
        ])
        .output()
        .await?;

    if !output.status.success() {
        let error_msg = String::from_utf8_lossy(&output.stderr);
        error!("ffprobe failed: {}", error_msg);
        return Err(Box::new(std::io::Error::new(
            std::io::ErrorKind::Other,
            format!("ffprobe failed: {}", error_msg)
        )) as Box<dyn std::error::Error + Send + Sync>);
    }

    let json_output = String::from_utf8(output.stdout)?;
    let parsed: Value = serde_json::from_str(&json_output)?;
    
    // Try to get duration from format first
    if let Some(format) = parsed.get("format") {
        if let Some(duration_str) = format.get("duration").and_then(|d| d.as_str()) {
            if let Ok(duration_f64) = duration_str.parse::<f64>() {
                info!("Extracted duration from format: {} seconds", duration_f64);
                return Ok(duration_f64.round() as i32);
            }
        }
    }
    
    // Fallback: try to get duration from video stream
    if let Some(streams) = parsed.get("streams").and_then(|s| s.as_array()) {
        for stream in streams {
            if let Some(codec_type) = stream.get("codec_type").and_then(|c| c.as_str()) {
                if codec_type == "video" {
                    if let Some(duration_str) = stream.get("duration").and_then(|d| d.as_str()) {
                        if let Ok(duration_f64) = duration_str.parse::<f64>() {
                            info!("Extracted duration from video stream: {} seconds", duration_f64);
                            return Ok(duration_f64.round() as i32);
                        }
                    }
                }
            }
        }
    }
    
    error!("Could not extract duration from video metadata");
    Err(Box::new(std::io::Error::new(
        std::io::ErrorKind::Other,
        "Could not extract duration from video metadata"
    )) as Box<dyn std::error::Error + Send + Sync>)
}

pub async fn extract_video_metadata_from_s3(
    s3_client: &aws_sdk_s3::Client,
    bucket: &str,
    s3_key: &str,
) -> Result<i32, Box<dyn std::error::Error + Send + Sync>> {
    info!("Extracting metadata from S3 object: {}/{}", bucket, s3_key);
    
    // Download the video file temporarily
    let temp_file_path = format!("/tmp/{}", uuid::Uuid::new_v4());
    
    let get_object_output = s3_client
        .get_object()
        .bucket(bucket)
        .key(s3_key)
        .send()
        .await?;
    
    let body = get_object_output.body.collect().await?.into_bytes();
    tokio::fs::write(&temp_file_path, body).await?;
    
    // Extract duration using ffprobe
    let duration_result = extract_video_duration(&temp_file_path).await;
    
    // Clean up temporary file
    if let Err(e) = tokio::fs::remove_file(&temp_file_path).await {
        error!("Failed to remove temporary file {}: {}", temp_file_path, e);
    }
    
    match duration_result {
        Ok(duration) => Ok(duration),
        Err(e) => Err(Box::new(std::io::Error::new(
            std::io::ErrorKind::Other,
            format!("Duration extraction failed: {}", e)
        )) as Box<dyn std::error::Error + Send + Sync>)
    }
}
