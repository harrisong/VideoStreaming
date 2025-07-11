use std::sync::Arc;
use uuid::Uuid;
use serde::{Serialize, Deserialize};
use log::{info, error};
use sqlx::{PgPool, FromRow};
use chrono::{Utc, DateTime};
use crate::scraper::{ScrapeRequest, ScrapeResponse, YoutubeScraper};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum JobStatus {
    Queued,
    Processing,
    Completed(ScrapeResponse),
    Failed(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Job {
    pub id: String,
    pub request: ScrapeRequest,
    pub status: JobStatus,
}

#[derive(Debug, FromRow)]
struct JobRecord {
    job_id: String,
    request: serde_json::Value,
    status: String,
    response: Option<serde_json::Value>,
    error: Option<String>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

#[derive(Debug)]
pub struct JobQueue {
    db_pool: PgPool,
}

impl JobQueue {
    pub fn new(db_pool: PgPool) -> Self {
        Self {
            db_pool,
        }
    }

    pub async fn add_job(&self, request: ScrapeRequest) -> String {
        let job_id = Uuid::new_v4().to_string();
        
        // Insert the job into the database
        let request_json = match serde_json::to_value(&request) {
            Ok(json) => json,
            Err(e) => {
                error!("Failed to serialize request: {}", e);
                return job_id;
            }
        };
        
        let result = sqlx::query("INSERT INTO jobs (job_id, request, status, created_at, updated_at) VALUES ($1, $2, $3, $4, $5)")
            .bind(&job_id)
            .bind(&request_json)
            .bind("queued")
            .bind(Utc::now())
            .bind(Utc::now())
            .execute(&self.db_pool)
            .await;
        
        if let Err(e) = result {
            error!("Failed to insert job into database: {}", e);
        }
        
        job_id
    }

    pub async fn get_job_status(&self, job_id: &str) -> Option<JobStatus> {
        let result = sqlx::query_as::<_, JobRecord>("SELECT * FROM jobs WHERE job_id = $1")
            .bind(job_id)
            .fetch_optional(&self.db_pool)
            .await;
        
        match result {
            Ok(Some(record)) => {
                match record.status.as_str() {
                    "queued" => Some(JobStatus::Queued),
                    "processing" => Some(JobStatus::Processing),
                    "completed" => {
                        if let Some(response_json) = record.response {
                            match serde_json::from_value::<ScrapeResponse>(response_json) {
                                Ok(response) => Some(JobStatus::Completed(response)),
                                Err(e) => {
                                    error!("Failed to deserialize response: {}", e);
                                    Some(JobStatus::Failed("Failed to deserialize response".to_string()))
                                }
                            }
                        } else {
                            Some(JobStatus::Failed("Response data missing".to_string()))
                        }
                    },
                    "failed" => Some(JobStatus::Failed(record.error.unwrap_or_else(|| "Unknown error".to_string()))),
                    _ => None,
                }
            },
            Ok(None) => None,
            Err(e) => {
                error!("Failed to get job status from database: {}", e);
                None
            }
        }
    }

    pub async fn update_job_status(&self, job_id: &str, status: JobStatus) {
        let (status_str, response_json, error_str) = match &status {
            JobStatus::Queued => ("queued", None, None),
            JobStatus::Processing => ("processing", None, None),
            JobStatus::Completed(response) => {
                let response_json = match serde_json::to_value(response) {
                    Ok(json) => Some(json),
                    Err(e) => {
                        error!("Failed to serialize response: {}", e);
                        None
                    }
                };
                ("completed", response_json, None)
            },
            JobStatus::Failed(error) => ("failed", None, Some(error.clone())),
        };
        
        let result = sqlx::query("UPDATE jobs SET status = $1, response = $2, error = $3, updated_at = $4 WHERE job_id = $5")
            .bind(status_str)
            .bind(response_json)
            .bind(error_str)
            .bind(Utc::now())
            .bind(job_id)
            .execute(&self.db_pool)
            .await;
        
        if let Err(e) = result {
            error!("Failed to update job status in database: {}", e);
        }
    }

    pub async fn get_next_queued_job(&self) -> Option<Job> {
        // Use a transaction to ensure we don't have race conditions
        let mut tx = match self.db_pool.begin().await {
            Ok(tx) => tx,
            Err(e) => {
                error!("Failed to begin transaction: {}", e);
                return None;
            }
        };
        
        // Get the next queued job
        let job_record = match sqlx::query_as::<_, JobRecord>(
            "SELECT * FROM jobs WHERE status = 'queued' ORDER BY created_at ASC LIMIT 1 FOR UPDATE SKIP LOCKED"
        )
        .fetch_optional(&mut tx)
        .await {
            Ok(record) => record,
            Err(e) => {
                error!("Failed to get next queued job: {}", e);
                let _ = tx.rollback().await;
                return None;
            }
        };
        
        if let Some(record) = job_record {
            // Update the job status to processing
            let result = sqlx::query("UPDATE jobs SET status = 'processing', updated_at = $1 WHERE job_id = $2")
                .bind(Utc::now())
                .bind(&record.job_id)
                .execute(&mut tx)
                .await;
            
            if let Err(e) = result {
                error!("Failed to update job status to processing: {}", e);
                let _ = tx.rollback().await;
                return None;
            }
            
            // Commit the transaction
            if let Err(e) = tx.commit().await {
                error!("Failed to commit transaction: {}", e);
                return None;
            }
            
            // Deserialize the request
            match serde_json::from_value::<ScrapeRequest>(record.request) {
                Ok(request) => {
                    return Some(Job {
                        id: record.job_id,
                        request,
                        status: JobStatus::Processing,
                    });
                },
                Err(e) => {
                    error!("Failed to deserialize request: {}", e);
                    return None;
                }
            }
        }
        
        None
    }
}

pub async fn start_worker(job_queue: Arc<JobQueue>, scraper: YoutubeScraper) {
    info!("Starting worker thread");
    
    loop {
        // Get the next job from the queue
        if let Some(job) = job_queue.get_next_queued_job().await {
            info!("Processing job {}", job.id);
            
            // Process the job
            let job_id = job.id.clone();
            let result = scraper.scrape_video(job.request).await;
            
            // Update the job status
            match result {
                Ok(response) => {
                    info!("Job {} completed successfully", job_id);
                    job_queue.update_job_status(&job_id, JobStatus::Completed(response)).await;
                }
                Err(e) => {
                    error!("Job {} failed: {}", job_id, e);
                    job_queue.update_job_status(&job_id, JobStatus::Failed(e)).await;
                }
            }
        }
        
        // Sleep for 15 seconds before checking for new jobs to avoid hammering the database
        tokio::time::sleep(tokio::time::Duration::from_secs(15)).await;
    }
}
