use std::io::{Read, Seek, SeekFrom};
use std::fs::File;
use log::{info, error, debug};

#[derive(Debug)]
pub struct VideoMetadata {
    pub duration_seconds: f64,
    pub width: u32,
    pub height: u32,
    pub format: String,
    pub bitrate: u64,
}

pub async fn extract_video_duration(file_path: &str) -> Result<i32, Box<dyn std::error::Error + Send + Sync>> {
    info!("Extracting duration from video: {}", file_path);
    
    let metadata = extract_video_metadata(file_path).await?;
    let duration = metadata.duration_seconds.round() as i32;
    
    info!("Extracted duration: {} seconds", duration);
    Ok(duration)
}

pub async fn extract_video_metadata(file_path: &str) -> Result<VideoMetadata, Box<dyn std::error::Error + Send + Sync>> {
    let mut file = File::open(file_path)?;
    let mut buffer = vec![0u8; 32];
    file.read_exact(&mut buffer)?;
    
    // Detect file format by magic bytes
    if is_mp4_format(&buffer) {
        parse_mp4_metadata(&mut file).await
    } else if is_avi_format(&buffer) {
        parse_avi_metadata(&mut file).await
    } else if is_mkv_format(&buffer) {
        parse_mkv_metadata(&mut file).await
    } else if is_webm_format(&buffer) {
        parse_webm_metadata(&mut file).await
    } else {
        Err(Box::new(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "Unsupported video format"
        )))
    }
}

fn is_mp4_format(buffer: &[u8]) -> bool {
    buffer.len() >= 8 && (
        &buffer[4..8] == b"ftyp" ||
        &buffer[4..8] == b"mdat" ||
        &buffer[4..8] == b"moov" ||
        &buffer[4..8] == b"wide" ||
        &buffer[4..8] == b"free"
    )
}

fn is_avi_format(buffer: &[u8]) -> bool {
    buffer.len() >= 12 && &buffer[0..4] == b"RIFF" && &buffer[8..12] == b"AVI "
}

fn is_mkv_format(buffer: &[u8]) -> bool {
    buffer.len() >= 4 && &buffer[0..4] == b"\x1A\x45\xDF\xA3"
}

fn is_webm_format(buffer: &[u8]) -> bool {
    buffer.len() >= 4 && &buffer[0..4] == b"\x1A\x45\xDF\xA3"
}

async fn parse_mp4_metadata(file: &mut File) -> Result<VideoMetadata, Box<dyn std::error::Error + Send + Sync>> {
    debug!("Parsing MP4 metadata");
    
    file.seek(SeekFrom::Start(0))?;
    let mut duration = 0.0;
    let mut width = 0u32;
    let mut height = 0u32;
    let mut bitrate = 0u64;
    let mut _timescale = 1000u32; // Default timescale
    
    loop {
        let mut box_header = [0u8; 8];
        match file.read_exact(&mut box_header) {
            Ok(_) => {},
            Err(_) => break, // End of file
        }
        
        let box_size = u32::from_be_bytes([box_header[0], box_header[1], box_header[2], box_header[3]]) as u64;
        let box_type = &box_header[4..8];
        
        if box_size < 8 {
            break;
        }
        
        match box_type {
            b"moov" => {
                // Movie header box - contains duration and timescale
                let moov_data = read_box_data(file, box_size - 8)?;
                if let Some((dur, ts)) = parse_moov_box(&moov_data) {
                    duration = dur as f64 / ts as f64;
                    _timescale = ts;
                }
            },
            b"trak" => {
                // Track box - contains video track information
                let trak_data = read_box_data(file, box_size - 8)?;
                if let Some((w, h)) = parse_trak_box(&trak_data) {
                    if width == 0 && height == 0 { // Only set if not already set
                        width = w;
                        height = h;
                    }
                }
            },
            _ => {
                // Skip other boxes
                file.seek(SeekFrom::Current((box_size - 8) as i64))?;
            }
        }
    }
    
    // Estimate bitrate if we have duration
    if duration > 0.0 {
        let file_size = file.metadata()?.len();
        bitrate = ((file_size as f64 * 8.0) / duration) as u64;
    }
    
    Ok(VideoMetadata {
        duration_seconds: duration,
        width,
        height,
        format: "MP4".to_string(),
        bitrate,
    })
}

async fn parse_avi_metadata(file: &mut File) -> Result<VideoMetadata, Box<dyn std::error::Error + Send + Sync>> {
    debug!("Parsing AVI metadata");
    
    file.seek(SeekFrom::Start(0))?;
    let mut buffer = vec![0u8; 56]; // AVI header size
    file.read_exact(&mut buffer)?;
    
    // Skip RIFF header (12 bytes) and look for avih (AVI header)
    file.seek(SeekFrom::Start(12))?;
    
    let mut avih_found = false;
    let mut duration = 0.0;
    let mut width = 0u32;
    let mut height = 0u32;
    
    // Look for avih chunk
    loop {
        let mut chunk_header = [0u8; 8];
        match file.read_exact(&mut chunk_header) {
            Ok(_) => {},
            Err(_) => break,
        }
        
        let chunk_id = &chunk_header[0..4];
        let chunk_size = u32::from_le_bytes([chunk_header[4], chunk_header[5], chunk_header[6], chunk_header[7]]);
        
        if chunk_id == b"avih" {
            let mut avih_data = vec![0u8; chunk_size as usize];
            file.read_exact(&mut avih_data)?;
            
            if avih_data.len() >= 32 {
                let microsec_per_frame = u32::from_le_bytes([avih_data[0], avih_data[1], avih_data[2], avih_data[3]]);
                let total_frames = u32::from_le_bytes([avih_data[16], avih_data[17], avih_data[18], avih_data[19]]);
                width = u32::from_le_bytes([avih_data[32], avih_data[33], avih_data[34], avih_data[35]]);
                height = u32::from_le_bytes([avih_data[36], avih_data[37], avih_data[38], avih_data[39]]);
                
                if microsec_per_frame > 0 {
                    duration = (total_frames as f64 * microsec_per_frame as f64) / 1_000_000.0;
                }
                avih_found = true;
            }
            break;
        } else {
            file.seek(SeekFrom::Current(chunk_size as i64))?;
        }
    }
    
    if !avih_found {
        return Err(Box::new(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "Could not find AVI header"
        )));
    }
    
    let file_size = file.metadata()?.len();
    let bitrate = if duration > 0.0 {
        ((file_size as f64 * 8.0) / duration) as u64
    } else {
        0
    };
    
    Ok(VideoMetadata {
        duration_seconds: duration,
        width,
        height,
        format: "AVI".to_string(),
        bitrate,
    })
}

async fn parse_mkv_metadata(file: &mut File) -> Result<VideoMetadata, Box<dyn std::error::Error + Send + Sync>> {
    debug!("Parsing MKV metadata");
    
    file.seek(SeekFrom::Start(0))?;
    let mut duration = 0.0;
    let timecode_scale = 1_000_000u64; // Default: 1ms
    
    // Simple MKV parsing - look for duration in segment info
    let mut buffer = vec![0u8; 1024];
    file.read_exact(&mut buffer)?;
    
    // Look for duration element (0x4489)
    for i in 0..buffer.len().saturating_sub(8) {
        if buffer[i] == 0x44 && buffer[i + 1] == 0x89 {
            // Found duration element
            let duration_bytes = &buffer[i + 3..i + 11];
            if duration_bytes.len() >= 8 {
                let duration_raw = f64::from_be_bytes([
                    duration_bytes[0], duration_bytes[1], duration_bytes[2], duration_bytes[3],
                    duration_bytes[4], duration_bytes[5], duration_bytes[6], duration_bytes[7]
                ]);
                duration = duration_raw * (timecode_scale as f64) / 1_000_000_000.0;
                break;
            }
        }
    }
    
    // Estimate dimensions (MKV parsing is complex, so we'll use defaults)
    let width = 1920u32; // Default assumption
    let height = 1080u32;
    
    let file_size = file.metadata()?.len();
    let bitrate = if duration > 0.0 {
        ((file_size as f64 * 8.0) / duration) as u64
    } else {
        0
    };
    
    Ok(VideoMetadata {
        duration_seconds: duration,
        width,
        height,
        format: "MKV".to_string(),
        bitrate,
    })
}

async fn parse_webm_metadata(file: &mut File) -> Result<VideoMetadata, Box<dyn std::error::Error + Send + Sync>> {
    debug!("Parsing WebM metadata");
    
    // WebM is based on Matroska, so we can use similar parsing
    parse_mkv_metadata(file).await.map(|mut metadata| {
        metadata.format = "WebM".to_string();
        metadata
    })
}

fn read_box_data(file: &mut File, size: u64) -> Result<Vec<u8>, std::io::Error> {
    let mut data = vec![0u8; size as usize];
    file.read_exact(&mut data)?;
    Ok(data)
}

fn parse_moov_box(data: &[u8]) -> Option<(u64, u32)> {
    // Look for mvhd (movie header) box within moov
    let mut i = 0;
    while i + 8 < data.len() {
        let box_size = u32::from_be_bytes([data[i], data[i + 1], data[i + 2], data[i + 3]]) as usize;
        let box_type = &data[i + 4..i + 8];
        
        if box_type == b"mvhd" && i + 32 < data.len() {
            // Movie header found
            let version = data[i + 8];
            let offset = if version == 1 { 28 } else { 20 }; // Version 1 uses 64-bit values
            
            if i + offset + 8 < data.len() {
                let timescale = u32::from_be_bytes([
                    data[i + offset], data[i + offset + 1], 
                    data[i + offset + 2], data[i + offset + 3]
                ]);
                let duration = if version == 1 {
                    u64::from_be_bytes([
                        data[i + offset + 4], data[i + offset + 5], data[i + offset + 6], data[i + offset + 7],
                        data[i + offset + 8], data[i + offset + 9], data[i + offset + 10], data[i + offset + 11]
                    ])
                } else {
                    u32::from_be_bytes([
                        data[i + offset + 4], data[i + offset + 5], 
                        data[i + offset + 6], data[i + offset + 7]
                    ]) as u64
                };
                
                return Some((duration, timescale));
            }
        }
        
        if box_size == 0 || box_size > data.len() - i {
            break;
        }
        i += box_size;
    }
    None
}

fn parse_trak_box(data: &[u8]) -> Option<(u32, u32)> {
    // Look for tkhd (track header) box within trak
    let mut i = 0;
    while i + 8 < data.len() {
        let box_size = u32::from_be_bytes([data[i], data[i + 1], data[i + 2], data[i + 3]]) as usize;
        let box_type = &data[i + 4..i + 8];
        
        if box_type == b"tkhd" && i + 84 < data.len() {
            // Track header found
            let version = data[i + 8];
            let offset = if version == 1 { 88 } else { 80 };
            
            if i + offset + 8 < data.len() {
                let width_fixed = u32::from_be_bytes([
                    data[i + offset], data[i + offset + 1], 
                    data[i + offset + 2], data[i + offset + 3]
                ]);
                let height_fixed = u32::from_be_bytes([
                    data[i + offset + 4], data[i + offset + 5], 
                    data[i + offset + 6], data[i + offset + 7]
                ]);
                
                // Convert from fixed-point (16.16) to integer
                let width = width_fixed >> 16;
                let height = height_fixed >> 16;
                
                if width > 0 && height > 0 {
                    return Some((width, height));
                }
            }
        }
        
        if box_size == 0 || box_size > data.len() - i {
            break;
        }
        i += box_size;
    }
    None
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
    
    // Extract duration using our pure Rust metadata parser
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
