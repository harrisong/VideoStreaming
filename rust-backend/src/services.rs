use sqlx::{PgPool, Pool, Postgres};
use std::env;
use aws_sdk_s3::Client;
use aws_sdk_s3::config::Credentials;
use aws_types::region::Region;
use aws_config;

pub async fn init_db_pool() -> Pool<Postgres> {
    let database_url = env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    PgPool::connect(&database_url)
        .await
        .expect("Failed to connect to database")
}

pub async fn init_s3_client() -> Client {
    let sdk_config = aws_config::from_env().load().await;
    let mut s3_config_builder = aws_sdk_s3::config::Builder::from(&sdk_config);
    
    if let Ok(endpoint) = std::env::var("MINIO_ENDPOINT") {
        s3_config_builder = s3_config_builder.endpoint_url(endpoint).force_path_style(true);
    }
    
    // Set MinIO credentials explicitly
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
    
    if let Some(region) = sdk_config.region() {
        s3_config_builder = s3_config_builder.region(region.clone());
    } else {
        // Default to us-east-1 if no region is set
        s3_config_builder = s3_config_builder.region(Region::new("us-east-1"));
    };

    let s3_config = s3_config_builder.build();
    Client::from_conf(s3_config)
}
