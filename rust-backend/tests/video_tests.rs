use actix_web::{test, web, App, http};
use dotenv::dotenv;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;
use std::collections::HashMap;

// Import the necessary modules from the main application
use video_streaming_backend::models::{RegisterRequest, CommentRequest};
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
        redis_client: None, // No Redis client in tests
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

// #[actix_web::test]
async fn test_video_streaming() {
    // Setup the test app
    let app = setup_test_app().await;
    
    // First, get a list of videos to find one to stream
    let list_req = test::TestRequest::get()
        .uri("/api/videos")
        .to_request();
    
    let list_resp = test::call_service(&app, list_req).await;
    assert!(list_resp.status().is_success());
    
    let list_body = test::read_body(list_resp).await;
    let videos: Vec<serde_json::Value> = serde_json::from_slice(&list_body).unwrap();
    
    // Make sure we have at least one video
    assert!(!videos.is_empty(), "No videos found for streaming test");
    
    // Get the ID of the first video
    let video_id = videos[0]["id"].as_i64().unwrap();
    
    // Now try to stream the video
    let stream_req = test::TestRequest::get()
        .uri(&format!("/api/videos/{}/stream", video_id))
        .to_request();
    
    let stream_resp = test::call_service(&app, stream_req).await;
    
    // Assert that the streaming request was successful
    assert!(stream_resp.status().is_success(), "Failed to stream video: {:?}", stream_resp.status());
    
    // Check that the content type is correct
    let content_type = stream_resp.headers().get(http::header::CONTENT_TYPE)
        .expect("Content-Type header missing")
        .to_str()
        .expect("Content-Type header is not valid UTF-8");
    
    assert!(content_type.contains("video/"), "Content-Type is not a video type: {}", content_type);
    
    // Check that we got some data
    let body = test::read_body(stream_resp).await;
    assert!(!body.is_empty(), "Video stream is empty");
    
    println!("Successfully streamed video with ID {}, received {} bytes", video_id, body.len());
}

#[actix_web::test]
async fn test_video_listing() {
    // Setup the test app
    let app = setup_test_app().await;
    
    // Test listing all videos
    let list_req = test::TestRequest::get()
        .uri("/api/videos")
        .to_request();
    
    let list_resp = test::call_service(&app, list_req).await;
    assert!(list_resp.status().is_success());
    
    let list_body = test::read_body(list_resp).await;
    let videos: Vec<serde_json::Value> = serde_json::from_slice(&list_body).unwrap();
    
    // Make sure we have at least one video
    assert!(!videos.is_empty(), "No videos found for listing test");
    
    // Check that each video has the expected fields
    for video in &videos {
        assert!(video.get("id").is_some(), "Video is missing 'id' field");
        assert!(video.get("title").is_some(), "Video is missing 'title' field");
        assert!(video.get("s3_key").is_some(), "Video is missing 's3_key' field");
    }
    
    println!("Successfully listed {} videos", videos.len());
    
    // Now test listing videos by tag
    // First, find a video with tags
    let video_with_tags = videos.iter().find(|v| {
        v.get("tags").is_some() && v["tags"].is_array() && !v["tags"].as_array().unwrap().is_empty()
    });
    
    if let Some(video) = video_with_tags {
        let tag = video["tags"][0].as_str().unwrap();
        
        // URL encode the tag to handle special characters
        let encoded_tag = urlencoding::encode(tag);
        
        // Test listing videos by this tag
        let tag_req = test::TestRequest::get()
            .uri(&format!("/api/videos/tag/{}", encoded_tag))
            .to_request();
        
        let tag_resp = test::call_service(&app, tag_req).await;
        assert!(tag_resp.status().is_success());
        
        let tag_body = test::read_body(tag_resp).await;
        let tagged_videos: Vec<serde_json::Value> = serde_json::from_slice(&tag_body).unwrap();
        
        // Make sure we found at least one video with this tag
        assert!(!tagged_videos.is_empty(), "No videos found with tag '{}'", tag);
        
        // Check that all returned videos have this tag
        for video in &tagged_videos {
            let video_tags = video["tags"].as_array().unwrap();
            let has_tag = video_tags.iter().any(|t| t.as_str().unwrap() == tag);
            assert!(has_tag, "Video {} does not have tag '{}'", video["id"], tag);
        }
        
        println!("Successfully listed {} videos with tag '{}'", tagged_videos.len(), tag);
    } else {
        println!("No videos with tags found, skipping tag listing test");
    }
}

#[actix_web::test]
async fn test_view_count_increment() {
    // Setup the test app
    let app = setup_test_app().await;
    
    // First, get a list of videos to find one to test
    let list_req = test::TestRequest::get()
        .uri("/api/videos")
        .to_request();
    
    let list_resp = test::call_service(&app, list_req).await;
    assert!(list_resp.status().is_success());
    
    let list_body = test::read_body(list_resp).await;
    let videos: Vec<serde_json::Value> = serde_json::from_slice(&list_body).unwrap();
    
    // Make sure we have at least one video
    assert!(!videos.is_empty(), "No videos found for view count test");
    
    // Get the ID of the first video
    let video_id = videos[0]["id"].as_i64().unwrap();
    
    // Get the initial view count
    let initial_req = test::TestRequest::get()
        .uri(&format!("/api/videos/{}", video_id))
        .to_request();
    
    let initial_resp = test::call_service(&app, initial_req).await;
    assert!(initial_resp.status().is_success());
    
    let initial_body = test::read_body(initial_resp).await;
    let initial_video: serde_json::Value = serde_json::from_slice(&initial_body).unwrap();
    
    let initial_view_count = initial_video["view_count"].as_i64().unwrap_or(0);
    
    // View the video again to increment the count
    let view_req = test::TestRequest::get()
        .uri(&format!("/api/videos/{}", video_id))
        .to_request();
    
    let view_resp = test::call_service(&app, view_req).await;
    assert!(view_resp.status().is_success());
    
    let view_body = test::read_body(view_resp).await;
    let viewed_video: serde_json::Value = serde_json::from_slice(&view_body).unwrap();
    
    let new_view_count = viewed_video["view_count"].as_i64().unwrap_or(0);
    
    // Check that the view count has increased
    assert_eq!(new_view_count, initial_view_count + 1, 
        "View count did not increment as expected. Initial: {}, New: {}", 
        initial_view_count, new_view_count);
    
    println!("Successfully verified view count increment for video {}: {} -> {}", 
        video_id, initial_view_count, new_view_count);
}

#[actix_web::test]
async fn test_comment_addition_and_listing() {
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
    
    // Now get all comments for the video
    let get_req = test::TestRequest::get()
        .uri(&format!("/api/comments/{}", video_id))
        .to_request();
    
    let get_resp = test::call_service(&app, get_req).await;
    assert!(get_resp.status().is_success());
    
    let get_body = test::read_body(get_resp).await;
    let comments: Vec<serde_json::Value> = serde_json::from_slice(&get_body).unwrap();
    
    // Check that our comment is in the list
    let found_comment = comments.iter().any(|c| {
        c["content"].as_str().unwrap() == comment_text &&
        c["video_id"].as_i64().unwrap() == video_id &&
        c["user_id"].as_i64().unwrap() == user_id as i64 &&
        c["video_time"].as_i64().unwrap() == video_time as i64
    });
    
    assert!(found_comment, "Could not find our posted comment in the comments list");
    
    println!("Successfully verified comment listing for video {}", video_id);
}
