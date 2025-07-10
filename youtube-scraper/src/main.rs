use actix_web::{web, App, HttpServer, HttpResponse, Responder, post, middleware};
use actix_cors::Cors;
use dotenv::dotenv;
use log::{info, error};
use sqlx::{PgPool};
use std::env;
use aws_sdk_s3::Client as S3Client;
use aws_sdk_s3::config::Credentials;
use aws_types::region::Region;
use clap::Parser;

mod models;
mod scraper;

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
                .service(scrape_video)
                .service(scrape_status)
        })
        .bind(("0.0.0.0", 5060))?
        .run()
        .await
    } else if let Some(url) = args.url {
        // Run as CLI tool
        info!("Running YouTube scraper in CLI mode");
        let scraper = scraper::YoutubeScraper::new(db_pool, s3_client);
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

#[post("/api/scrape")]
async fn scrape_video(
    req: web::Json<scraper::ScrapeRequest>,
    db_pool: web::Data<PgPool>,
    s3_client: web::Data<S3Client>,
) -> impl Responder {
    let scraper = scraper::YoutubeScraper::new(db_pool.get_ref().clone(), s3_client.get_ref().clone());
    
    match scraper.scrape_video(req.into_inner()).await {
        Ok(response) => HttpResponse::Ok().json(response),
        Err(e) => {
            error!("Error scraping video: {}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": e
            }))
        }
    }
}

#[post("/api/status")]
async fn scrape_status() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "running"
    }))
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
    S3Client::from_conf(s3_config)
}
