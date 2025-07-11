use std::env;
use log::{info};
use rustube::{IdBuf, VideoFetcher};
use url::Url;
use uuid::Uuid;
use sqlx::PgPool;
use aws_sdk_s3::Client as S3Client;
use aws_sdk_s3::primitives::ByteStream;
use tokio::fs::File;
use tokio::io::AsyncReadExt;
use crate::models::Video as DbVideo;

pub struct YoutubeScraper {
    db_pool: PgPool,
    s3_client: S3Client,
}

#[derive(Debug, serde::Deserialize)]
pub struct ScrapeRequest {
    pub youtube_url: String,
    pub title: Option<String>,
    pub description: Option<String>,
    pub tags: Option<Vec<String>>,
    pub user_id: Option<i32>,
}

#[derive(Debug, serde::Serialize)]
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

        // Download video using rustube
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
        // Use rustube to download the video
        let id_buf = match IdBuf::from_string(video_id.to_string()) {
            Ok(id_buf) => id_buf,
            Err(e) => return Err(format!("Failed to create IdBuf from video_id: {}", e)),
        };
        
        let fetcher = match VideoFetcher::from_id(id_buf) {
            Ok(fetcher) => fetcher,
            Err(e) => return Err(format!("Failed to create VideoFetcher from video_id: {}", e)),
        };
        
        let descrambler = match fetcher.fetch().await {
            Ok(descrambler) => descrambler,
            Err(e) => return Err(format!("Failed to fetch video: {}", e)),
        };

        let video = match descrambler.descramble() {
            Ok(video) => video,
            Err(e) => return Err(format!("Failed to descramble video: {}", e)),
        };

        // Get the best quality video stream
        let best_quality = match video.best_quality() {
            Some(quality) => quality,
            None => return Err("No video streams available".to_string()),
        };

        // Download the video
        let path = match best_quality.download_to_dir(".").await {
            Ok(path) => path,
            Err(e) => return Err(format!("Failed to download video: {}", e)),
        };

        // Read the video file into memory
        let mut file = match File::open(&path).await {
            Ok(file) => file,
            Err(e) => return Err(format!("Failed to open downloaded video file: {}", e)),
        };

        let mut buffer = Vec::new();
        if let Err(e) = file.read_to_end(&mut buffer).await {
            return Err(format!("Failed to read video file: {}", e));
        }

        // Get the video title
        let title = video.title().to_string();

        // Clean up the downloaded file
        if let Err(e) = tokio::fs::remove_file(&path).await {
            info!("Failed to remove temporary file {}: {}", path.display(), e);
        }

        Ok((buffer, title))
    }

    async fn upload_to_minio(&self, video_data: &[u8], s3_key: &str) -> Result<(), String> {
        let bucket_name = env::var("MINIO_BUCKET").unwrap_or_else(|_| "videos".to_string());
        
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
