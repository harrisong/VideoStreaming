use actix_web::{test, web, App};
use dotenv::dotenv;
use std::sync::Arc;
use tokio::sync::Mutex;
use std::collections::HashMap;
use sqlx::PgPool;

use video_streaming_backend::handlers;
use video_streaming_backend::AppState;
use video_streaming_backend::services;

async fn setup_test_app(pool: PgPool) -> impl actix_web::dev::Service<
    actix_http::Request,
    Response = actix_web::dev::ServiceResponse,
    Error = actix_web::Error,
> {
    dotenv().ok();
    
    // Initialize S3 client
    let s3_client = services::init_s3_client().await;
    
    // Create the app state using the provided pool
    let app_state = Arc::new(Mutex::new(AppState {
        db_pool: pool,
        s3_client,
        redis_client: None,
        job_queue: None, // No job queue in tests
        video_clients: std::sync::Mutex::new(HashMap::new()),
        watchparty_clients: std::sync::Mutex::new(HashMap::new()),
    }));
    
    // Create the test app
    test::init_service(
        App::new()
            .app_data(web::Data::new(app_state))
            .configure(handlers::configure_routes)
    ).await
}

#[sqlx::test]
async fn test_search_videos_by_title(pool: PgPool) {
    // Insert test data
    sqlx::query(
        "INSERT INTO users (username, email, password) VALUES ($1, $2, $3) ON CONFLICT (username) DO NOTHING"
    )
    .bind("testuser")
    .bind("test@example.com")
    .bind("hashedpassword")
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO videos (title, description, s3_key, uploaded_by) VALUES ($1, $2, $3, $4) ON CONFLICT (s3_key) DO NOTHING"
    )
    .bind("Test Video About Cats")
    .bind("A video about cats")
    .bind("test_key_1")
    .bind(1)
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO videos (title, description, s3_key, uploaded_by) VALUES ($1, $2, $3, $4) ON CONFLICT (s3_key) DO NOTHING"
    )
    .bind("Another Video")
    .bind("A video about dogs")
    .bind("test_key_2")
    .bind(1)
    .execute(&pool)
    .await
    .unwrap();

    let app = setup_test_app(pool).await;

    // Test search by title
    let req = test::TestRequest::get()
        .uri("/api/videos/search/cats")
        .to_request();
    let resp = test::call_service(&app, req).await;
    
    assert!(resp.status().is_success());
    
    let body: serde_json::Value = test::read_body_json(resp).await;
    let videos = body.as_array().unwrap();
    
    assert_eq!(videos.len(), 1);
    assert_eq!(videos[0]["title"], "Test Video About Cats");
}

#[sqlx::test]
async fn test_search_videos_by_description(pool: PgPool) {
    // Insert test data
    sqlx::query(
        "INSERT INTO users (username, email, password) VALUES ($1, $2, $3) ON CONFLICT (username) DO NOTHING"
    )
    .bind("testuser")
    .bind("test@example.com")
    .bind("hashedpassword")
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO videos (title, description, s3_key, uploaded_by) VALUES ($1, $2, $3, $4) ON CONFLICT (s3_key) DO NOTHING"
    )
    .bind("Video One")
    .bind("This is about programming")
    .bind("test_key_1")
    .bind(1)
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO videos (title, description, s3_key, uploaded_by) VALUES ($1, $2, $3, $4) ON CONFLICT (s3_key) DO NOTHING"
    )
    .bind("Video Two")
    .bind("This is about cooking")
    .bind("test_key_2")
    .bind(1)
    .execute(&pool)
    .await
    .unwrap();

    let app = setup_test_app(pool).await;

    // Test search by description
    let req = test::TestRequest::get()
        .uri("/api/videos/search/programming")
        .to_request();
    let resp = test::call_service(&app, req).await;
    
    assert!(resp.status().is_success());
    
    let body: serde_json::Value = test::read_body_json(resp).await;
    let videos = body.as_array().unwrap();
    
    assert_eq!(videos.len(), 1);
    assert_eq!(videos[0]["title"], "Video One");
}

#[sqlx::test]
async fn test_search_videos_by_tags(pool: PgPool) {
    // Insert test data
    sqlx::query(
        "INSERT INTO users (username, email, password) VALUES ($1, $2, $3) ON CONFLICT (username) DO NOTHING"
    )
    .bind("testuser")
    .bind("test@example.com")
    .bind("hashedpassword")
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO videos (title, description, s3_key, uploaded_by, tags) VALUES ($1, $2, $3, $4, $5) ON CONFLICT (s3_key) DO NOTHING"
    )
    .bind("Tagged Video")
    .bind("A video with tags")
    .bind("test_key_1")
    .bind(1)
    .bind(&vec!["rust", "programming"])
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO videos (title, description, s3_key, uploaded_by, tags) VALUES ($1, $2, $3, $4, $5) ON CONFLICT (s3_key) DO NOTHING"
    )
    .bind("Another Video")
    .bind("Another video")
    .bind("test_key_2")
    .bind(1)
    .bind(&vec!["cooking", "food"])
    .execute(&pool)
    .await
    .unwrap();

    let app = setup_test_app(pool).await;

    // Test search by tag
    let req = test::TestRequest::get()
        .uri("/api/videos/search/rust")
        .to_request();
    let resp = test::call_service(&app, req).await;
    
    assert!(resp.status().is_success());
    
    let body: serde_json::Value = test::read_body_json(resp).await;
    let videos = body.as_array().unwrap();
    
    assert_eq!(videos.len(), 1);
    assert_eq!(videos[0]["title"], "Tagged Video");
}

#[sqlx::test]
async fn test_search_videos_case_insensitive(pool: PgPool) {
    // Insert test data
    sqlx::query(
        "INSERT INTO users (username, email, password) VALUES ($1, $2, $3) ON CONFLICT (username) DO NOTHING"
    )
    .bind("testuser")
    .bind("test@example.com")
    .bind("hashedpassword")
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO videos (title, description, s3_key, uploaded_by) VALUES ($1, $2, $3, $4) ON CONFLICT (s3_key) DO NOTHING"
    )
    .bind("UPPERCASE TITLE")
    .bind("lowercase description")
    .bind("test_key_1")
    .bind(1)
    .execute(&pool)
    .await
    .unwrap();

    let app = setup_test_app(pool).await;

    // Test case insensitive search
    let req = test::TestRequest::get()
        .uri("/api/videos/search/uppercase")
        .to_request();
    let resp = test::call_service(&app, req).await;
    
    assert!(resp.status().is_success());
    
    let body: serde_json::Value = test::read_body_json(resp).await;
    let videos = body.as_array().unwrap();
    
    assert_eq!(videos.len(), 1);
    assert_eq!(videos[0]["title"], "UPPERCASE TITLE");
}

#[sqlx::test]
async fn test_search_videos_no_results(pool: PgPool) {
    let app = setup_test_app(pool).await;

    // Test search with no results
    let req = test::TestRequest::get()
        .uri("/api/videos/search/nonexistent")
        .to_request();
    let resp = test::call_service(&app, req).await;
    
    assert!(resp.status().is_success());
    
    let body: serde_json::Value = test::read_body_json(resp).await;
    let videos = body.as_array().unwrap();
    
    assert_eq!(videos.len(), 0);
}
