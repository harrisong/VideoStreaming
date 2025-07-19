use std::sync::Mutex as StdMutex;
use std::collections::HashMap;

pub mod models;
pub mod handlers;
pub mod websocket;
pub mod services;
pub mod redis_service;
pub mod video_utils;
pub mod job_queue;

use sqlx::PgPool;
use aws_sdk_s3::Client;
use crate::job_queue::JobQueue;
use std::sync::Arc;

pub struct AppState {
    pub db_pool: PgPool,
    pub s3_client: Client,
    pub redis_client: Option<redis::Client>,
    pub job_queue: Option<Arc<JobQueue>>,
    pub video_clients: StdMutex<HashMap<i32, Vec<tokio::sync::mpsc::Sender<String>>>>,
    pub watchparty_clients: StdMutex<HashMap<i32, Vec<tokio::sync::mpsc::Sender<String>>>>,
}
