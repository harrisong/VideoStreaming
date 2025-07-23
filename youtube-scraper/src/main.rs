use actix_web::{web, App, HttpServer, HttpResponse, Responder, post, get, middleware};
use actix_cors::Cors;
use dotenv::dotenv;
use log::{info, error};
use sqlx::{PgPool};
use std::env;
use std::sync::Arc;
use aws_sdk_s3::Client as S3Client;
use aws_sdk_s3::config::Credentials;
use aws_types::region::Region;
use clap::Parser;
use serde::{Serialize, Deserialize};
use futures::future::join_all;

mod models;
mod scraper;
mod job_queue;

use job_queue::JobQueue;

#[derive(Debug, Serialize, Deserialize)]
struct JobResponse {
    job_id: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct JobStatusRequest {
    job_id: String,
}

#[post("/api/scrape")]
async fn scrape_video(
    req: web::Json<scraper::ScrapeRequest>,
    job_queue: web::Data<Arc<JobQueue>>,
) -> impl Responder {
    // Add the job to the queue
    let job_id = job_queue.add_job(req.into_inner()).await;
    
    HttpResponse::Accepted().json(JobResponse { job_id })
}

#[post("/api/search")]
async fn search_videos(
    req: web::Json<scraper::SearchRequest>,
    job_queue: web::Data<Arc<JobQueue>>,
    scraper: web::Data<Arc<scraper::YoutubeScraper>>,
) -> impl Responder {
    let query = req.query.clone();
    let max_results = req.max_results.unwrap_or(10);
    let user_id = req.user_id;
    
    info!("Searching YouTube for: {}", query);
    
    // Search for videos
    match scraper.as_ref().search_videos(&query, max_results).await {
        Ok(video_urls) => {
            info!("Found {} videos for query: {}", video_urls.len(), query);
            
            // Add each video URL to the job queue
            let mut futures = Vec::new();
            
            for url in video_urls {
                let scrape_request = scraper::ScrapeRequest {
                    youtube_url: url,
                    title: None,
                    description: None,
                    tags: Some(vec![query.clone()]),
                    user_id,
                };
                
                futures.push(job_queue.add_job(scrape_request));
            }
            
            // Wait for all jobs to be added
            let job_ids = join_all(futures).await;
            
            HttpResponse::Accepted().json(scraper::SearchResponse { job_ids })
        },
        Err(e) => {
            error!("Failed to search YouTube: {}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": format!("Failed to search YouTube: {}", e)
            }))
        }
    }
}

#[get("/api/jobs/{job_id}")]
async fn get_job_status(
    path: web::Path<String>,
    job_queue: web::Data<Arc<JobQueue>>,
) -> impl Responder {
    let job_id = path.into_inner();
    
    match job_queue.get_job_status(&job_id).await {
        Some(status) => HttpResponse::Ok().json(status),
        None => HttpResponse::NotFound().json(serde_json::json!({
            "error": "Job not found"
        }))
    }
}

#[post("/api/status")]
async fn scrape_status() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "running"
    }))
}

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Run in API server mode
    #[arg(short, long)]
    server: bool,

    /// YouTube URL to scrape
    #[arg(short, long)]
    url: Option<String>,

    /// User ID to associate with the video
    #[arg(short = 'i', long)]
    user_id: Option<i32>,

    /// Path to cookies file for yt-dlp
    #[arg(short, long)]
    cookies: Option<String>,
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    dotenv().ok();
    env_logger::init();

    // Parse command line arguments
    let args = Args::parse();

    // Initialize database and S3 client
    let db_pool = init_db_pool().await;
    let s3_client = init_s3_client().await;

    if args.server {
        // Create job queue
        let job_queue = Arc::new(JobQueue::new(db_pool.clone()));
        
        // Start worker thread
        let worker_db_pool = db_pool.clone();
        let worker_s3_client = s3_client.clone();
        let worker_job_queue = job_queue.clone();
        tokio::spawn(async move {
            let scraper = scraper::YoutubeScraper::new(worker_db_pool, worker_s3_client);
            job_queue::start_worker(worker_job_queue, scraper).await;
        });
        
        // Run as API server
        info!("Starting YouTube scraper API server on 0.0.0.0:5060");
        HttpServer::new(move || {
            let cors = Cors::default()
                .allow_any_origin()
                .allow_any_method()
                .allow_any_header();

            App::new()
                .wrap(cors)
                .wrap(middleware::Logger::default())
                .app_data(web::Data::new(db_pool.clone()))
                .app_data(web::Data::new(s3_client.clone()))
                .app_data(web::Data::new(job_queue.clone()))
                .app_data(web::Data::new(Arc::new(scraper::YoutubeScraper::new(db_pool.clone(), s3_client.clone()))))
                .service(scrape_video)
                .service(search_videos)
                .service(get_job_status)
                .service(scrape_status)
        })
        .bind(("0.0.0.0", 5060))?
        .run()
        .await
    } else if let Some(url) = args.url {
        // Run as CLI tool
        info!("Running YouTube scraper in CLI mode");
        let mut scraper = scraper::YoutubeScraper::new(db_pool, s3_client);
        
        // Set cookies file if provided
        if let Some(cookies_path) = args.cookies {
            scraper.set_cookies_file(cookies_path);
        }
        
        let request = scraper::ScrapeRequest {
            youtube_url: url,
            title: None,
            description: None,
            tags: None,
            user_id: args.user_id,
        };

        match scraper.scrape_video(request).await {
            Ok(response) => {
                info!("Video scraped successfully: {:?}", response);
                Ok(())
            }
            Err(e) => {
                error!("Failed to scrape video: {}", e);
                std::process::exit(1);
            }
        }
    } else {
        error!("No YouTube URL provided. Use --url to specify a URL or --server to run in server mode.");
        std::process::exit(1);
    }
}

async fn init_db_pool() -> PgPool {
    let database_url = env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    PgPool::connect(&database_url)
        .await
        .expect("Failed to connect to database")
}

async fn init_s3_client() -> S3Client {
    let sdk_config = aws_config::from_env().load().await;
    let mut s3_config_builder = aws_sdk_s3::config::Builder::from(&sdk_config);
    
    // Check if we're in local development mode (MinIO)
    if let Ok(endpoint) = std::env::var("MINIO_ENDPOINT") {
        log::info!("Using MinIO endpoint: {}", endpoint);
        s3_config_builder = s3_config_builder.endpoint_url(endpoint).force_path_style(true);
        
        // Set MinIO credentials explicitly for local development
        let access_key = std::env::var("MINIO_ACCESS_KEY").unwrap_or_else(|_| "minio".to_string());
        let secret_key = std::env::var("MINIO_SECRET_KEY").unwrap_or_else(|_| "minio123".to_string());
        let credentials = Credentials::new(
            access_key,
            secret_key,
            None, // session_token
            None, // expires_after
            "env", // provider_name
        );
        s3_config_builder = s3_config_builder.credentials_provider(credentials);
    } else {
        // Production mode - use AWS S3 with IAM roles (ECS task role)
        log::info!("Using AWS S3 with IAM role credentials");
        // No need to set credentials explicitly - ECS task role will be used
    }
    
    // Set region
    if let Some(region) = sdk_config.region() {
        s3_config_builder = s3_config_builder.region(region.clone());
    } else {
        // Default to us-west-2 for AWS deployment
        let aws_region = std::env::var("AWS_REGION").unwrap_or_else(|_| "us-west-2".to_string());
        s3_config_builder = s3_config_builder.region(Region::new(aws_region));
    };

    let s3_config = s3_config_builder.build();
    S3Client::from_conf(s3_config)
}
