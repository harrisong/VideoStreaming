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
    Client::from_conf(s3_config)
}

pub async fn ensure_bucket_exists(client: &Client) {
    // In production, use the bucket name from environment variable (set by Terraform)
    // In development, fall back to local MinIO bucket name
    let bucket_name = std::env::var("S3_BUCKET")
        .or_else(|_| std::env::var("MINIO_BUCKET"))
        .unwrap_or_else(|_| "videos".to_string());
    
    log::info!("Using S3 bucket: {}", bucket_name);
    
    // In AWS, buckets are created by Terraform, so we don't need to create them
    // Just verify we can access the bucket
    if std::env::var("MINIO_ENDPOINT").is_ok() {
        // Local development - try to create bucket
        match client.create_bucket().bucket(&bucket_name).send().await {
            Ok(_) => log::info!("Bucket created successfully: {}", bucket_name),
            Err(err) => {
                if err.to_string().contains("BucketAlreadyExists") || err.to_string().contains("BucketAlreadyOwnedByYou") {
                    log::info!("Bucket already exists: {}", bucket_name);
                } else {
                    log::warn!("Error creating bucket {}: {:?}", bucket_name, err);
                }
            }
        }
    } else {
        // Production - bucket should already exist, just verify access
        match client.head_bucket().bucket(&bucket_name).send().await {
            Ok(_) => log::info!("Successfully connected to S3 bucket: {}", bucket_name),
            Err(err) => log::error!("Cannot access S3 bucket {}: {:?}", bucket_name, err),
        }
    }
}
