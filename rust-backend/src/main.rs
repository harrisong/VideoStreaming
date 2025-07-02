use actix_web::{web, App, HttpServer, http};
use actix_cors::Cors;
use dotenv::dotenv;
use std::sync::Mutex as StdMutex;
use std::collections::HashMap;
use tokio::sync::Mutex;
use std::sync::Arc;
use log::info;
use env_logger;

mod models;
mod handlers;
mod websocket;
mod services;

use sqlx::PgPool;
use aws_sdk_s3::Client;

pub struct AppState {
    db_pool: PgPool,
    s3_client: Client,
    video_clients: StdMutex<HashMap<i32, Vec<tokio::sync::mpsc::Sender<String>>>>,
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    dotenv().ok();
    env_logger::init();
    let db_pool = services::init_db_pool().await;
    let s3_client = services::init_s3_client().await;
    let app_state = Arc::new(Mutex::new(AppState { 
        db_pool, 
        s3_client, 
        video_clients: StdMutex::new(HashMap::new()) 
    }));

    let app_state_clone = app_state.clone();

    info!("Starting HTTP server on 0.0.0.0:5050");
    let http_server = HttpServer::new(move || {
        let cors = Cors::default()
            .allowed_origin("http://localhost:3000")
            .allowed_methods(vec!["GET", "POST", "PUT", "DELETE", "OPTIONS"])
            .allowed_headers(vec![http::header::CONTENT_TYPE, http::header::AUTHORIZATION])
            .supports_credentials();

        App::new()
            .wrap(cors)
            .app_data(web::Data::new(app_state.clone()))
            .configure(handlers::configure_routes)
    })
    .bind(("0.0.0.0", 5050))?
    .run();

    info!("Starting WebSocket server on 0.0.0.0:8080");
    let ws_server = HttpServer::new(move || {
        let cors = Cors::default()
            .allowed_origin("http://localhost:3000")
            .allowed_methods(vec!["GET", "POST", "PUT", "DELETE", "OPTIONS"])
            .allowed_headers(vec![http::header::CONTENT_TYPE, http::header::AUTHORIZATION])
            .supports_credentials();

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
