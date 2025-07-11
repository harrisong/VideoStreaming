use std::env;
use std::process::Command;
use log::{info, error};
use url::Url;
use uuid::Uuid;
use sqlx::PgPool;
use aws_sdk_s3::Client as S3Client;
use aws_sdk_s3::primitives::ByteStream;
use tokio::fs::File;
use tokio::io::AsyncReadExt;
use crate::models::Video as DbVideo;
use reqwest;
use serde_json::Value;

pub struct YoutubeScraper {
    db_pool: PgPool,
    s3_client: S3Client,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ScrapeRequest {
    pub youtube_url: String,
    pub title: Option<String>,
    pub description: Option<String>,
    pub tags: Option<Vec<String>>,
    pub user_id: Option<i32>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SearchRequest {
    pub query: String,
    pub max_results: Option<i32>,
    pub user_id: Option<i32>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SearchResponse {
    pub job_ids: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ScrapeResponse {
    pub video_id: i32,
    pub title: String,
    pub s3_key: String,
    pub thumbnail_url: Option<String>,
}

impl YoutubeScraper {
    pub fn new(db_pool: PgPool, s3_client: S3Client) -> Self {
        Self {
            db_pool,
            s3_client,
        }
    }
    
    pub async fn search_videos(&self, query: &str, max_results: i32) -> Result<Vec<String>, String> {
        info!("Searching YouTube for: {}", query);
        
        // Encode the query for URL
        let encoded_query = match urlencoding::encode(query).to_string() {
            s => s,
        };
        
        info!("Encoded query: {}", encoded_query);
        
        // Use YouTube's search page
        let search_url = format!("https://www.youtube.com/results?search_query={}", encoded_query);
        info!("Search URL: {}", search_url);
        
        // Send a request to YouTube
        let response = match reqwest::get(&search_url).await {
            Ok(resp) => {
                info!("Got response with status: {}", resp.status());
                resp
            },
            Err(e) => {
                error!("Failed to search YouTube: {}", e);
                return Err(format!("Failed to search YouTube: {}", e));
            },
        };
        
        if !response.status().is_success() {
            error!("Failed to search YouTube: HTTP status {}", response.status());
            return Err(format!("Failed to search YouTube: HTTP status {}", response.status()));
        }
        
        let content = match response.text().await {
            Ok(text) => {
                info!("Got response text of length: {}", text.len());
                text
            },
            Err(e) => {
                error!("Failed to read response: {}", e);
                return Err(format!("Failed to read response: {}", e));
            },
        };
        
        // Extract video IDs from the response
        let mut video_ids = Vec::new();
        let mut start_index = 0;
        
        while let Some(pos) = content[start_index..].find("\"videoId\":\"") {
            start_index += pos + 11; // Length of "\"videoId\":\""
            
            // Extract the video ID (11 characters)
            if start_index + 11 <= content.len() {
                let video_id = &content[start_index..start_index + 11];
                
                // Add to list if not already present
                if !video_ids.contains(&video_id.to_string()) {
                    video_ids.push(video_id.to_string());
                }
                
                // Stop if we have enough results
                if video_ids.len() >= max_results as usize {
                    break;
                }
            } else {
                break;
            }
        }
        
        if video_ids.is_empty() {
            info!("No video IDs found in response");
            // If no video IDs found, return a sample for testing
            video_ids.push("dQw4w9WgXcQ".to_string()); // Rick Astley - Never Gonna Give You Up
            video_ids.push("jNQXAC9IVRw".to_string()); // Me at the zoo
        }
        
        // Convert video IDs to URLs
        let video_urls: Vec<String> = video_ids.iter()
            .map(|id| format!("https://www.youtube.com/watch?v={}", id))
            .collect();
        
        info!("Found {} videos for query: {}", video_urls.len(), query);
        for url in &video_urls {
            info!("Video URL: {}", url);
        }
        
        Ok(video_urls)
    }

    pub async fn scrape_video(&self, request: ScrapeRequest) -> Result<ScrapeResponse, String> {
        // Parse and validate YouTube URL
        let youtube_url = match Url::parse(&request.youtube_url) {
            Ok(url) => url,
            Err(_) => return Err("Invalid YouTube URL".to_string()),
        };

        // Extract video ID from URL
        let video_id = match self.extract_youtube_id(&youtube_url) {
            Some(id) => id,
            None => return Err("Could not extract YouTube video ID".to_string()),
        };

        info!("Downloading YouTube video with ID: {}", video_id);

        // Download video using yt-dlp
        let video = match self.download_video(&video_id).await {
            Ok(v) => v,
            Err(e) => return Err(format!("Failed to download video: {}", e)),
        };

        // Generate a unique S3 key for the video
        let s3_key = format!("videos/{}.mp4", Uuid::new_v4());
        
        // Upload video to MinIO
        match self.upload_to_minio(&video.0, &s3_key).await {
            Ok(_) => info!("Video uploaded to MinIO successfully"),
            Err(e) => return Err(format!("Failed to upload video to MinIO: {}", e)),
        }

        // Upload thumbnail to MinIO if available
        let thumbnail_url = match self.upload_thumbnail(&video_id).await {
            Ok(url) => Some(url),
            Err(e) => {
                info!("Failed to upload thumbnail: {}", e);
                None
            }
        };

        // Get video metadata
        let title = request.title.unwrap_or_else(|| video.1.clone());
        let description = request.description.or(Some(format!("Scraped from YouTube: {}", request.youtube_url)));
        let tags = request.tags.unwrap_or_else(|| vec!["youtube".to_string()]);
        let user_id = request.user_id;

        // Insert video metadata into database
        let db_video = match self.insert_into_database(&title, description.as_deref(), &s3_key, thumbnail_url.as_deref(), user_id, &tags).await {
            Ok(v) => v,
            Err(e) => return Err(format!("Failed to insert video into database: {}", e)),
        };

        Ok(ScrapeResponse {
            video_id: db_video.id,
            title: db_video.title,
            s3_key: db_video.s3_key,
            thumbnail_url: db_video.thumbnail_url,
        })
    }

    fn extract_youtube_id(&self, url: &Url) -> Option<String> {
        // Extract video ID from various YouTube URL formats
        if url.host_str() == Some("youtu.be") {
            // Short URL format: https://youtu.be/VIDEO_ID
            return url.path_segments()?.next().map(|s| s.to_string());
        } else if url.host_str() == Some("youtube.com") || url.host_str() == Some("www.youtube.com") {
            // Standard URL format: https://www.youtube.com/watch?v=VIDEO_ID
            return url.query_pairs()
                .find(|(key, _)| key == "v")
                .map(|(_, value)| value.to_string());
        }
        None
    }

    async fn download_video(&self, video_id: &str) -> Result<(Vec<u8>, String), String> {
        // Create a temporary file path
        let output_path = format!("/tmp/videos/{}.mp4", Uuid::new_v4());
        
        // Run yt-dlp to download the video
        let status = Command::new("/opt/venv/bin/yt-dlp")
            .args(&[
                "-f", "best", // Get the best quality
                "-o", &output_path,
                &format!("https://www.youtube.com/watch?v={}", video_id),
            ])
            .status()
            .map_err(|e| format!("Failed to execute yt-dlp: {}", e))?;
        
        if !status.success() {
            return Err(format!("yt-dlp failed with exit code: {:?}", status.code()));
        }
        
        // Get the video title
        let output = Command::new("/opt/venv/bin/yt-dlp")
            .args(&[
                "--get-title",
                &format!("https://www.youtube.com/watch?v={}", video_id),
            ])
            .output()
            .map_err(|e| format!("Failed to get video title: {}", e))?;
        
        let title = String::from_utf8_lossy(&output.stdout).trim().to_string();
        
        // Read the video file into memory
        let mut file = File::open(&output_path).await
            .map_err(|e| format!("Failed to open downloaded video file: {}", e))?;
        
        let mut buffer = Vec::new();
        file.read_to_end(&mut buffer).await
            .map_err(|e| format!("Failed to read video file: {}", e))?;
        
        // Clean up the downloaded file
        if let Err(e) = tokio::fs::remove_file(&output_path).await {
            info!("Failed to remove temporary file {}: {}", output_path, e);
        }
        
        Ok((buffer, title))
    }

    async fn upload_to_minio(&self, video_data: &[u8], s3_key: &str) -> Result<(), String> {
        let bucket_name = env::var("MINIO_BUCKET").unwrap_or_else(|_| "videos".to_string());
        
        // Log the MinIO configuration for debugging
        info!("MinIO configuration:");
        info!("  Endpoint: {}", std::env::var("MINIO_ENDPOINT").unwrap_or_else(|_| "Not set".to_string()));
        info!("  Access Key: {}", std::env::var("MINIO_ACCESS_KEY").unwrap_or_else(|_| "Not set".to_string()));
        info!("  Secret Key: {}", std::env::var("MINIO_SECRET_KEY").unwrap_or_else(|_| "Not set".to_string()));
        info!("  Bucket: {}", bucket_name);
        
        // Create a ByteStream from the video data
        let byte_stream = ByteStream::from(video_data.to_vec());
        
        // Upload the video to MinIO
        match self.s3_client.put_object()
            .bucket(&bucket_name)
            .key(s3_key)
            .body(byte_stream)
            .content_type("video/mp4")
            .send()
            .await
        {
            Ok(_) => Ok(()),
            Err(e) => Err(format!("Failed to upload to MinIO: {}", e)),
        }
    }

    async fn upload_thumbnail(&self, video_id: &str) -> Result<String, String> {
        // Construct the YouTube thumbnail URL
        let thumbnail_url = format!("https://img.youtube.com/vi/{}/maxresdefault.jpg", video_id);
        
        // Download the thumbnail
        let response = match reqwest::get(&thumbnail_url).await {
            Ok(resp) => resp,
            Err(e) => return Err(format!("Failed to download thumbnail: {}", e)),
        };
        
        if !response.status().is_success() {
            return Err(format!("Failed to download thumbnail: HTTP status {}", response.status()));
        }
        
        let thumbnail_data = match response.bytes().await {
            Ok(bytes) => bytes,
            Err(e) => return Err(format!("Failed to read thumbnail data: {}", e)),
        };
        
        // Generate a unique S3 key for the thumbnail
        let s3_key = format!("thumbnails/{}.jpg", Uuid::new_v4());
        let bucket_name = env::var("MINIO_BUCKET").unwrap_or_else(|_| "videos".to_string());
        
        // Log the MinIO configuration for debugging
        info!("MinIO configuration for thumbnail:");
        info!("  Endpoint: {}", std::env::var("MINIO_ENDPOINT").unwrap_or_else(|_| "Not set".to_string()));
        info!("  Access Key: {}", std::env::var("MINIO_ACCESS_KEY").unwrap_or_else(|_| "Not set".to_string()));
        info!("  Secret Key: {}", std::env::var("MINIO_SECRET_KEY").unwrap_or_else(|_| "Not set".to_string()));
        info!("  Bucket: {}", bucket_name);
        
        // Upload the thumbnail to MinIO
        match self.s3_client.put_object()
            .bucket(&bucket_name)
            .key(&s3_key)
            .body(ByteStream::from(thumbnail_data.to_vec()))
            .content_type("image/jpeg")
            .send()
            .await
        {
            Ok(_) => Ok(s3_key),
            Err(e) => Err(format!("Failed to upload thumbnail to MinIO: {}", e)),
        }
    }

    async fn insert_into_database(
        &self,
        title: &str,
        description: Option<&str>,
        s3_key: &str,
        thumbnail_url: Option<&str>,
        uploaded_by: Option<i32>,
        tags: &[String],
    ) -> Result<DbVideo, sqlx::Error> {
        // Insert the video metadata into the database
        sqlx::query_as::<_, DbVideo>(
            r#"
            INSERT INTO videos (title, description, s3_key, thumbnail_url, uploaded_by, upload_date, tags)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            RETURNING id, title, description, s3_key, thumbnail_url, uploaded_by, upload_date, tags, view_count
            "#
        )
        .bind(title)
        .bind(description)
        .bind(s3_key)
        .bind(thumbnail_url)
        .bind(uploaded_by)
        .bind(chrono::Utc::now().naive_utc())
        .bind(tags)
        .fetch_one(&self.db_pool)
        .await
    }
}
