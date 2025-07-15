use actix_web::{web, App, HttpServer, http};
use actix_cors::Cors;
use dotenv::dotenv;
use std::collections::HashMap;
use tokio::sync::Mutex;
use std::sync::Arc;
use log::{info, error};
use env_logger;

// Import from the crate root
use video_streaming_backend::AppState;

mod models;
mod handlers;
mod websocket;
mod services;
mod redis_service;

#[tokio::main]
async fn main() -> std::io::Result<()> {
    dotenv().ok();
    env_logger::init();
    let db_pool = services::init_db_pool().await;
    let s3_client = services::init_s3_client().await;
    
    // Ensure the videos bucket exists
    services::ensure_bucket_exists(&s3_client).await;
    
    // Initialize Redis client
    let redis_client = match video_streaming_backend::redis_service::init_redis_client() {
        Ok(client) => {
            info!("Successfully connected to Redis");
            Some(client)
        },
        Err(e) => {
            error!("Failed to connect to Redis: {:?}", e);
            None
        }
    };
    
    let app_state = Arc::new(Mutex::new(AppState {
        db_pool,
        s3_client,
        redis_client,
        video_clients: std::sync::Mutex::new(HashMap::new()),
        watchparty_clients: std::sync::Mutex::new(HashMap::new()),
    }));

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
