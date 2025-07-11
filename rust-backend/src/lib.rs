use actix_web::{web, App, HttpServer, http};
use std::sync::Mutex as StdMutex;
use std::collections::HashMap;
use tokio::sync::Mutex;
use std::sync::Arc;

pub mod models;
pub mod handlers;
pub mod websocket;
pub mod services;

use sqlx::PgPool;
use aws_sdk_s3::Client;

pub struct AppState {
    pub db_pool: PgPool,
    pub s3_client: Client,
    pub video_clients: StdMutex<HashMap<i32, Vec<tokio::sync::mpsc::Sender<String>>>>,
}
