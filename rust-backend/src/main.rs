use actix_web::{web, App, HttpServer, http};
use actix_cors::Cors;
use dotenv::dotenv;
use std::collections::HashMap;
use tokio::sync::Mutex;
use std::sync::Arc;
use log::{info, error};
use env_logger;

// Import from the crate root
use video_streaming_backend::{AppState, job_queue, handlers, websocket, services};

#[tokio::main]
async fn main() -> std::io::Result<()> {
    dotenv().ok();
    env_logger::init();
    let db_pool = services::init_db_pool().await;
    let s3_client = services::init_s3_client().await;
    
    // Ensure the videos bucket exists
    services::ensure_bucket_exists(&s3_client).await;
    
    // Initialize Redis client and job queue with retry logic
    let (redis_client, job_queue) = match video_streaming_backend::redis_service::init_redis_client() {
        Ok(client) => {
            info!("Successfully connected to Redis");
            let job_queue = job_queue::JobQueue::new(client.clone(), db_pool.clone(), s3_client.clone());
            (Some(client), Some(job_queue))
        },
        Err(e) => {
            error!("Failed to connect to Redis: {:?}. Will retry in background.", e);
            
            // Start a background task to retry Redis connection
            let db_pool_clone = db_pool.clone();
            let s3_client_clone = s3_client.clone();
            tokio::spawn(async move {
                let mut retry_count = 0;
                loop {
                    tokio::time::sleep(std::time::Duration::from_secs(5)).await;
                    retry_count += 1;
                    info!("Retrying Redis connection (attempt {})", retry_count);
                    
                    match video_streaming_backend::redis_service::init_redis_client() {
                        Ok(client) => {
                            info!("Successfully connected to Redis after {} retries", retry_count);
                            
                            // Create job queue
                            let job_queue = job_queue::JobQueue::new(client.clone(), db_pool_clone.clone(), s3_client_clone.clone());
                            
                            // Queue existing videos without duration
                            if let Err(e) = job_queue.queue_missing_durations().await {
                                error!("Failed to queue missing durations: {:?}", e);
                            }
                            
                            // Start background job processor
                            let job_queue_processor = job_queue.clone();
                            tokio::spawn(async move {
                                job_queue_processor.process_duration_extraction_jobs().await;
                            });
                            
                            info!("Started background job processor for duration extraction after Redis reconnection");
                            break;
                        },
                        Err(e) => {
                            error!("Failed to connect to Redis (retry {}): {:?}", retry_count, e);
                            // Continue retrying
                        }
                    }
                }
            });
            
            // Return None for now, but the background task will initialize Redis later
            (None, None)
        }
    };
    
    let app_state = Arc::new(Mutex::new(AppState {
        db_pool,
        s3_client,
        redis_client,
        job_queue,
        video_clients: std::sync::Mutex::new(HashMap::new()),
        watchparty_clients: std::sync::Mutex::new(HashMap::new()),
    }));

    // Start background job processor if Redis is available
    if let Some(ref job_queue_ref) = app_state.lock().await.job_queue {
        let job_queue_clone = job_queue_ref.clone();
        
        // Queue existing videos without duration
        tokio::spawn(async move {
            if let Err(e) = job_queue_clone.queue_missing_durations().await {
                error!("Failed to queue missing durations: {:?}", e);
            }
        });
        
        // Start background job processor
        let job_queue_processor = job_queue_ref.clone();
        tokio::spawn(async move {
            job_queue_processor.process_duration_extraction_jobs().await;
        });
        
        info!("Started background job processor for duration extraction");
    }

    let app_state_clone = app_state.clone();

    info!("Starting HTTP server on 0.0.0.0:5050");
    let http_server = HttpServer::new(move || {
        let allowed_origins = std::env::var("CORS_ALLOWED_ORIGINS")
            .unwrap_or_else(|_| "http://localhost:3000".to_string());
        
        let mut cors = Cors::default()
            .allowed_methods(vec!["GET", "POST", "PUT", "DELETE", "OPTIONS"])
            .allowed_headers(vec![http::header::CONTENT_TYPE, http::header::AUTHORIZATION])
            .supports_credentials();

        // Add each origin from the comma-separated list
        for origin in allowed_origins.split(',') {
            cors = cors.allowed_origin(origin.trim());
        }

        App::new()
            .wrap(cors)
            .app_data(web::Data::new(app_state.clone()))
            .configure(handlers::configure_routes)
    })
    .bind(("0.0.0.0", 5050))?
    .run();

    info!("Starting WebSocket server on 0.0.0.0:8080");
    let ws_server = HttpServer::new(move || {
        let allowed_origins = std::env::var("CORS_ALLOWED_ORIGINS")
            .unwrap_or_else(|_| "http://localhost:3000".to_string());
        
        let mut cors = Cors::default()
            .allowed_methods(vec!["GET", "POST", "PUT", "DELETE", "OPTIONS"])
            .allowed_headers(vec![http::header::CONTENT_TYPE, http::header::AUTHORIZATION])
            .supports_credentials();

        // Add each origin from the comma-separated list
        for origin in allowed_origins.split(',') {
            cors = cors.allowed_origin(origin.trim());
        }

        App::new()
            .wrap(cors)
            .app_data(web::Data::new(app_state_clone.clone()))
            .configure(websocket::configure_ws_routes)
    })
    .bind(("0.0.0.0", 8080))?
    .run();

    tokio::try_join!(http_server, ws_server)?;
    Ok(())
}
