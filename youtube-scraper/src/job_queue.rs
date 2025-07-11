use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;
use serde::{Serialize, Deserialize};
use log::{info, error};
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

#[derive(Debug)]
pub struct JobQueue {
    jobs: RwLock<HashMap<String, Job>>,
}

impl JobQueue {
    pub fn new() -> Self {
        Self {
            jobs: RwLock::new(HashMap::new()),
        }
    }

    pub async fn add_job(&self, request: ScrapeRequest) -> String {
        let job_id = Uuid::new_v4().to_string();
        let job = Job {
            id: job_id.clone(),
            request,
            status: JobStatus::Queued,
        };
        
        let mut jobs = self.jobs.write().await;
        jobs.insert(job_id.clone(), job);
        
        job_id
    }

    pub async fn get_job_status(&self, job_id: &str) -> Option<JobStatus> {
        let jobs = self.jobs.read().await;
        jobs.get(job_id).map(|job| job.status.clone())
    }

    pub async fn update_job_status(&self, job_id: &str, status: JobStatus) {
        let mut jobs = self.jobs.write().await;
        if let Some(job) = jobs.get_mut(job_id) {
            job.status = status;
        }
    }

    pub async fn get_next_queued_job(&self) -> Option<Job> {
        let mut jobs = self.jobs.write().await;
        
        for (_, job) in jobs.iter_mut() {
            if let JobStatus::Queued = job.status {
                job.status = JobStatus::Processing;
                return Some(job.clone());
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
        
        // Sleep for a short time before checking for new jobs
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    }
}
