use serde::{Deserialize, Serialize};
use log::{info, error, warn};
use std::time::Duration;
use tokio::time::sleep;
use sqlx::PgPool;
use aws_sdk_s3::Client as S3Client;
use crate::video_utils::extract_video_metadata_from_s3;
use crate::models::Video;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DurationExtractionJob {
    pub video_id: i32,
    pub s3_key: String,
    pub bucket: String,
}

use std::sync::Arc;

#[derive(Clone)]
pub struct JobQueue {
    redis_client: redis::Client,
    db_pool: PgPool,
    s3_client: S3Client,
}

impl JobQueue {
    pub fn new(redis_client: redis::Client, db_pool: PgPool, s3_client: S3Client) -> Arc<Self> {
        Arc::new(Self {
            redis_client,
            db_pool,
            s3_client,
        })
    }

    pub async fn enqueue_duration_extraction(&self, job: DurationExtractionJob) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut conn = self.redis_client.get_async_connection().await?;
        let job_json = serde_json::to_string(&job)?;
        
        redis::cmd("LPUSH")
            .arg("duration_extraction_jobs")
            .arg(&job_json)
            .query_async::<_, i32>(&mut conn)
            .await?;
        
        info!("Enqueued duration extraction job for video ID {}", job.video_id);
        Ok(())
    }

    pub async fn process_duration_extraction_jobs(&self) {
        info!("Starting duration extraction job processor");
        
        loop {
            match self.process_next_job().await {
                Ok(processed) => {
                    if !processed {
                        // No jobs available, wait a bit before checking again
                        sleep(Duration::from_secs(5)).await;
                    }
                }
                Err(e) => {
                    error!("Error processing job: {:?}", e);
                    sleep(Duration::from_secs(10)).await;
                }
            }
        }
    }

    async fn process_next_job(&self) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
        // Get Redis connection with retry logic
        let mut conn = match self.redis_client.get_async_connection().await {
            Ok(conn) => conn,
            Err(e) => {
                error!("Failed to get Redis connection: {:?}", e);
                // Sleep before retrying
                sleep(Duration::from_secs(5)).await;
                return Ok(false);
            }
        };
        
        // Use BRPOP to block until a job is available (with timeout)
        let result: Option<(String, String)> = match redis::cmd("BRPOP")
            .arg("duration_extraction_jobs")
            .arg(30) // 30 second timeout
            .query_async(&mut conn)
            .await
        {
            Ok(res) => res,
            Err(e) => {
                error!("Redis BRPOP command failed: {:?}", e);
                return Ok(false);
            }
        };

        if let Some((_, job_json)) = result {
            // Parse the job JSON
            let job: DurationExtractionJob = match serde_json::from_str(&job_json) {
                Ok(job) => job,
                Err(e) => {
                    error!("Failed to parse job JSON: {:?}", e);
                    return Ok(true); // Consider the job processed (but failed)
                }
            };
            
            let video_id = job.video_id; // Store video_id before moving job
            info!("Processing duration extraction job for video ID {}", video_id);
            
            match self.extract_and_update_duration(job).await {
                Ok(_) => {
                    info!("Successfully processed duration extraction job");
                }
                Err(e) => {
                    // Check if the error is due to S3 object not found (404)
                    let error_string = format!("{:?}", e);
                    if error_string.contains("NoSuchKey") || error_string.contains("404") {
                        warn!("S3 object not found for video ID {}, not re-enqueueing job", video_id);
                    } else {
                        error!("Failed to process duration extraction job: {:?}", e);
                        
                        // Implement retry logic - push the original job back to the queue
                        info!("Re-enqueueing failed job for video ID {}", video_id);
                        if let Err(push_err) = redis::cmd("LPUSH")
                            .arg("duration_extraction_jobs")
                            .arg(&job_json)
                            .query_async::<_, i32>(&mut conn)
                            .await
                        {
                            error!("Failed to re-enqueue job: {:?}", push_err);
                        }
                    }
                }
            }
            
            Ok(true) // Job was processed
        } else {
            Ok(false) // No job available (timeout)
        }
    }

    async fn extract_and_update_duration(&self, job: DurationExtractionJob) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        // Check if video still needs duration extraction
        let video_result = match sqlx::query_as::<_, Video>(
            "SELECT * FROM videos WHERE id = $1"
        )
        .bind(job.video_id)
        .fetch_optional(&self.db_pool)
        .await {
            Ok(result) => result,
            Err(e) => {
                error!("Database error when checking video {}: {:?}", job.video_id, e);
                return Err(Box::new(e) as Box<dyn std::error::Error + Send + Sync>);
            }
        };

        // Check if video exists
        let video = match video_result {
            Some(v) => v,
            None => {
                error!("Video ID {} does not exist, skipping duration extraction", job.video_id);
                return Ok(());
            }
        };

        // Check if duration is already set
        if let Some(duration) = video.duration {
            info!("Video ID {} already has duration: {} seconds, skipping", job.video_id, duration);
            return Ok(());
        }

        info!("Extracting duration for video ID {} from S3 key {}", job.video_id, job.s3_key);

        // Extract duration from video with retry logic
        let mut retry_count = 0;
        let max_retries = 3;
        let mut last_error = None;

        while retry_count < max_retries {
            match extract_video_metadata_from_s3(&self.s3_client, &job.bucket, &job.s3_key).await {
                Ok(duration) => {
                    info!("Extracted duration {} seconds for video ID {}", duration, job.video_id);
                    
                    // Update database
                    match sqlx::query(
                        "UPDATE videos SET duration = $1 WHERE id = $2"
                    )
                    .bind(duration)
                    .bind(job.video_id)
                    .execute(&self.db_pool)
                    .await {
                        Ok(update_result) => {
                            if update_result.rows_affected() > 0 {
                                info!("Successfully updated duration for video ID {}", job.video_id);
                                return Ok(());
                            } else {
                                warn!("No rows updated for video ID {}", job.video_id);
                                return Ok(());
                            }
                        },
                        Err(db_err) => {
                            error!("Database error when updating duration for video {}: {:?}", job.video_id, db_err);
                            return Err(Box::new(db_err) as Box<dyn std::error::Error + Send + Sync>);
                        }
                    }
                },
                Err(e) => {
                    retry_count += 1;
                    last_error = Some(e);
                    error!("Failed to extract duration for video ID {} (attempt {}/{}): {:?}", 
                           job.video_id, retry_count, max_retries, last_error);
                    
                    if retry_count < max_retries {
                        // Exponential backoff: 2s, 4s, 8s, etc.
                        let backoff = Duration::from_secs(2u64.pow(retry_count as u32));
                        info!("Retrying in {} seconds", backoff.as_secs());
                        sleep(backoff).await;
                    }
                }
            }
        }

        // All retries failed
        if let Some(e) = last_error {
            error!("All {} attempts to extract duration for video ID {} failed", max_retries, job.video_id);
            return Err(Box::new(std::io::Error::new(
                std::io::ErrorKind::Other,
                format!("Failed to extract duration after {} attempts: {}", max_retries, e)
            )) as Box<dyn std::error::Error + Send + Sync>);
        }

        // This should never happen, but just in case
        Err(Box::new(std::io::Error::new(
            std::io::ErrorKind::Other,
            "Unknown error in duration extraction"
        )) as Box<dyn std::error::Error + Send + Sync>)
    }

    pub async fn queue_missing_durations(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        info!("Queuing duration extraction jobs for videos without duration");
        
        let videos = sqlx::query_as::<_, Video>(
            "SELECT * FROM videos WHERE duration IS NULL ORDER BY id ASC"
        )
        .fetch_all(&self.db_pool)
        .await?;

        let bucket = std::env::var("S3_BUCKET")
            .or_else(|_| std::env::var("MINIO_BUCKET"))
            .unwrap_or_else(|_| "videos".to_string());
        
        for video in videos {
            // Check if S3 object exists before enqueueing
            match self.s3_client
                .head_object()
                .bucket(&bucket)
                .key(&video.s3_key)
                .send()
                .await
            {
                Ok(_) => {
                    // Object exists, enqueue the job
                    let job = DurationExtractionJob {
                        video_id: video.id,
                        s3_key: video.s3_key.clone(),
                        bucket: bucket.clone(),
                    };
                    
                    if let Err(e) = self.enqueue_duration_extraction(job).await {
                        error!("Failed to enqueue job for video ID {}: {:?}", video.id, e);
                    }
                },
                Err(e) => {
                    // Check if it's a 404 error (NoSuchKey) by examining the error string
                    let error_string = format!("{:?}", e);
                    if error_string.contains("NoSuchKey") || error_string.contains("404") {
                        warn!("S3 object {} does not exist for video ID {}, skipping job enqueueing", video.s3_key, video.id);
                        continue;
                    }
                    // For other errors, log and continue
                    error!("Failed to check S3 object existence for video ID {}: {:?}", video.id, e);
                }
            }
        }
        
        info!("Finished queuing duration extraction jobs");
        Ok(())
    }
}
