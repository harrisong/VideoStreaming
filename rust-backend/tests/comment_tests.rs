use actix_web::{test, web, App, http};
use dotenv::dotenv;
use std::sync::Arc;
use tokio::sync::Mutex;
use serde_json::json;
use uuid::Uuid;
use std::collections::HashMap;
use std::sync::Mutex as StdMutex;

// Import the necessary modules from the main application
use video_streaming_backend::models::{RegisterRequest, LoginRequest, CommentRequest};
use video_streaming_backend::handlers;
use video_streaming_backend::AppState;
use video_streaming_backend::services;

async fn setup_test_app() -> impl actix_web::dev::Service<
    actix_http::Request,
    Response = actix_web::dev::ServiceResponse,
    Error = actix_web::Error,
> {
    dotenv().ok();
    
    // Initialize the database pool and S3 client
    let db_pool = services::init_db_pool().await;
    let s3_client = services::init_s3_client().await;
    
    // Create the app state
    let app_state = Arc::new(Mutex::new(AppState {
        db_pool,
        s3_client,
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

// Helper function to register a test user and get a JWT token
async fn register_test_user(app: &impl actix_web::dev::Service<
    actix_http::Request,
    Response = actix_web::dev::ServiceResponse,
    Error = actix_web::Error,
>) -> (i32, String) {
    // Generate a unique username and email
    let unique_id = Uuid::new_v4().to_string();
    let username = format!("testuser_{}", &unique_id[..8]);
    let email = format!("test_{}@example.com", &unique_id[..8]);
    let password = "password123".to_string();
    
    // Register the user
    let register_request = RegisterRequest {
        username,
        email,
        password,
    };
    
    let register_req = test::TestRequest::post()
        .uri("/api/auth/register")
        .set_json(&register_request)
        .to_request();
    
    let register_resp = test::call_service(app, register_req).await;
    assert!(register_resp.status().is_success());
    
    // Parse the response to get the user ID and token
    let register_body = test::read_body(register_resp).await;
    let register_json: serde_json::Value = serde_json::from_slice(&register_body).unwrap();
    
    let user_id = register_json["user"]["id"].as_i64().unwrap() as i32;
    let token = register_json["token"].as_str().unwrap().to_string();
    
    (user_id, token)
}

#[actix_web::test]
async fn test_add_comment() {
    // Setup the test app
    let app = setup_test_app().await;
    
    // Register a test user to post comments
    let (user_id, token) = register_test_user(&app).await;
    
    // Get a list of videos to find one to comment on
    let list_req = test::TestRequest::get()
        .uri("/api/videos")
        .to_request();
    
    let list_resp = test::call_service(&app, list_req).await;
    assert!(list_resp.status().is_success());
    
    let list_body = test::read_body(list_resp).await;
    let videos: Vec<serde_json::Value> = serde_json::from_slice(&list_body).unwrap();
    
    // Make sure we have at least one video
    assert!(!videos.is_empty(), "No videos found for comment test");
    
    // Get the ID of the first video
    let video_id = videos[0]["id"].as_i64().unwrap();
    
    // Create a unique comment
    let comment_text = format!("Test comment {}", Uuid::new_v4());
    let video_time = 30; // 30 seconds into the video
    
    let comment_request = CommentRequest {
        text: comment_text.clone(),
        video_time,
    };
    
    // Post the comment
    let post_req = test::TestRequest::post()
        .uri(&format!("/api/comments/{}", video_id))
        .insert_header((http::header::AUTHORIZATION, format!("Bearer {}", token)))
        .set_json(&comment_request)
        .to_request();
    
    let post_resp = test::call_service(&app, post_req).await;
    assert!(post_resp.status().is_success(), "Failed to post comment: {:?}", post_resp.status());
    
    let post_body = test::read_body(post_resp).await;
    let posted_comment: serde_json::Value = serde_json::from_slice(&post_body).unwrap();
    
    // Verify the posted comment has the expected fields
    assert_eq!(posted_comment["content"].as_str().unwrap(), comment_text);
    assert_eq!(posted_comment["video_id"].as_i64().unwrap(), video_id);
    assert_eq!(posted_comment["user_id"].as_i64().unwrap(), user_id as i64);
    assert_eq!(posted_comment["video_time"].as_i64().unwrap(), video_time as i64);
    
    println!("Successfully posted comment to video {}", video_id);
}

#[actix_web::test]
async fn test_get_comments() {
    // Setup the test app
    let app = setup_test_app().await;
    
    // Register a test user to post comments
    let (user_id, token) = register_test_user(&app).await;
    
    // Get a list of videos to find one to comment on
    let list_req = test::TestRequest::get()
        .uri("/api/videos")
        .to_request();
    
    let list_resp = test::call_service(&app, list_req).await;
    assert!(list_resp.status().is_success());
    
    let list_body = test::read_body(list_resp).await;
    let videos: Vec<serde_json::Value> = serde_json::from_slice(&list_body).unwrap();
    
    // Make sure we have at least one video
    assert!(!videos.is_empty(), "No videos found for comment test");
    
    // Get the ID of the first video
    let video_id = videos[0]["id"].as_i64().unwrap();
    
    // Create multiple unique comments
    for i in 1..=3 {
        let comment_text = format!("Test comment {} - {}", i, Uuid::new_v4());
        let video_time = i * 10; // 10, 20, 30 seconds into the video
        
        let comment_request = CommentRequest {
            text: comment_text,
            video_time,
        };
        
        // Post the comment
        let post_req = test::TestRequest::post()
            .uri(&format!("/api/comments/{}", video_id))
            .insert_header((http::header::AUTHORIZATION, format!("Bearer {}", token)))
            .set_json(&comment_request)
            .to_request();
        
        let post_resp = test::call_service(&app, post_req).await;
        assert!(post_resp.status().is_success(), "Failed to post comment {}: {:?}", i, post_resp.status());
    }
    
    // Now get all comments for the video
    let get_req = test::TestRequest::get()
        .uri(&format!("/api/comments/{}", video_id))
        .to_request();
    
    let get_resp = test::call_service(&app, get_req).await;
    assert!(get_resp.status().is_success());
    
    let get_body = test::read_body(get_resp).await;
    let comments: Vec<serde_json::Value> = serde_json::from_slice(&get_body).unwrap();
    
    // Check that we got at least our 3 comments
    assert!(comments.len() >= 3, "Expected at least 3 comments, got {}", comments.len());
    
    // Check that the comments are sorted by video_time
    let mut last_time = -1;
    for comment in &comments {
        let current_time = comment["video_time"].as_i64().unwrap();
        assert!(current_time >= last_time, "Comments are not sorted by video_time");
        last_time = current_time;
    }
    
    // Check that our user's comments are in the list
    let user_comments = comments.iter()
        .filter(|c| c["user_id"].as_i64().unwrap() == user_id as i64)
        .count();
    
    assert!(user_comments >= 3, "Expected at least 3 comments from our user, got {}", user_comments);
    
    println!("Successfully verified comment listing for video {}, found {} total comments", video_id, comments.len());
}

#[actix_web::test]
async fn test_unauthorized_comment() {
    // Setup the test app
    let app = setup_test_app().await;
    
    // Get a list of videos to find one to comment on
    let list_req = test::TestRequest::get()
        .uri("/api/videos")
        .to_request();
    
    let list_resp = test::call_service(&app, list_req).await;
    assert!(list_resp.status().is_success());
    
    let list_body = test::read_body(list_resp).await;
    let videos: Vec<serde_json::Value> = serde_json::from_slice(&list_body).unwrap();
    
    // Make sure we have at least one video
    assert!(!videos.is_empty(), "No videos found for comment test");
    
    // Get the ID of the first video
    let video_id = videos[0]["id"].as_i64().unwrap();
    
    // Create a comment request
    let comment_request = CommentRequest {
        text: "Unauthorized comment".to_string(),
        video_time: 10,
    };
    
    // Try to post the comment without authentication
    let post_req = test::TestRequest::post()
        .uri(&format!("/api/comments/{}", video_id))
        .set_json(&comment_request)
        .to_request();
    
    let post_resp = test::call_service(&app, post_req).await;
    
    // Assert that we get a 403 Forbidden
    assert_eq!(post_resp.status(), http::StatusCode::FORBIDDEN, 
        "Expected 403 Forbidden for unauthorized comment, got: {:?}", post_resp.status());
    
    // Check the error message
    let body = test::read_body(post_resp).await;
    let error_json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    
    assert!(error_json.get("error").is_some(), "Error response missing 'error' field");
    assert!(error_json["error"].as_str().unwrap().contains("Unauthorized"), 
        "Unexpected error message: {}", error_json["error"]);
    
    println!("Successfully tested unauthorized comment rejection");
}

#[actix_web::test]
async fn test_comment_with_invalid_token() {
    // Setup the test app
    let app = setup_test_app().await;
    
    // Get a list of videos to find one to comment on
    let list_req = test::TestRequest::get()
        .uri("/api/videos")
        .to_request();
    
    let list_resp = test::call_service(&app, list_req).await;
    assert!(list_resp.status().is_success());
    
    let list_body = test::read_body(list_resp).await;
    let videos: Vec<serde_json::Value> = serde_json::from_slice(&list_body).unwrap();
    
    // Make sure we have at least one video
    assert!(!videos.is_empty(), "No videos found for comment test");
    
    // Get the ID of the first video
    let video_id = videos[0]["id"].as_i64().unwrap();
    
    // Create a comment request
    let comment_request = CommentRequest {
        text: "Comment with invalid token".to_string(),
        video_time: 10,
    };
    
    // Try to post the comment with an invalid token
    let post_req = test::TestRequest::post()
        .uri(&format!("/api/comments/{}", video_id))
        .insert_header((http::header::AUTHORIZATION, "Bearer invalid.token.here"))
        .set_json(&comment_request)
        .to_request();
    
    let post_resp = test::call_service(&app, post_req).await;
    
    // Assert that we get a 403 Forbidden
    assert_eq!(post_resp.status(), http::StatusCode::FORBIDDEN, 
        "Expected 403 Forbidden for comment with invalid token, got: {:?}", post_resp.status());
    
    // Check the error message
    let body = test::read_body(post_resp).await;
    let error_json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    
    assert!(error_json.get("error").is_some(), "Error response missing 'error' field");
    assert!(error_json["error"].as_str().unwrap().contains("Unauthorized"), 
        "Unexpected error message: {}", error_json["error"]);
    
    println!("Successfully tested comment rejection with invalid token");
}
