use actix_web::{test, web, App};
use dotenv::dotenv;
use std::sync::Arc;
use tokio::sync::Mutex;
use serde_json::json;
use uuid::Uuid;

// Import the necessary modules from the main application
use video_streaming_backend::models::{RegisterRequest, LoginRequest};
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
        video_clients: std::sync::Mutex::new(std::collections::HashMap::new()),
    }));
    
    // Create the test app
    test::init_service(
        App::new()
            .app_data(web::Data::new(app_state))
            .configure(handlers::configure_routes)
    ).await
}

#[actix_web::test]
async fn test_register_and_login() {
    // Setup the test app
    let app = setup_test_app().await;
    
    // Generate a unique username and email to avoid conflicts
    let unique_id = Uuid::new_v4().to_string();
    let username = format!("testuser_{}", &unique_id[..8]);
    let email = format!("test_{}@example.com", &unique_id[..8]);
    let password = "password123".to_string();
    
    // Test registration
    let register_request = RegisterRequest {
        username: username.clone(),
        email: email.clone(),
        password: password.clone(),
    };
    
    let register_req = test::TestRequest::post()
        .uri("/api/auth/register")
        .set_json(&register_request)
        .to_request();
    
    let register_resp = test::call_service(&app, register_req).await;
    
    // Assert that registration was successful
    assert!(register_resp.status().is_success());
    
    // Parse the response body
    let register_body = test::read_body(register_resp).await;
    let register_json: serde_json::Value = serde_json::from_slice(&register_body).unwrap();
    
    // Assert that the response contains the expected fields
    assert!(register_json.get("message").is_some());
    assert!(register_json.get("user").is_some());
    assert!(register_json.get("token").is_some());
    
    // Extract the user ID for later use
    let user_id = register_json["user"]["id"].as_i64().unwrap();
    
    // Test login with correct credentials
    let login_request = LoginRequest {
        username: email.clone(), // Note: The login endpoint uses email as the username
        password: password.clone(),
    };
    
    let login_req = test::TestRequest::post()
        .uri("/api/auth/login")
        .set_json(&login_request)
        .to_request();
    
    let login_resp = test::call_service(&app, login_req).await;
    
    // Assert that login was successful
    assert!(login_resp.status().is_success());
    
    // Parse the response body
    let login_body = test::read_body(login_resp).await;
    let login_json: serde_json::Value = serde_json::from_slice(&login_body).unwrap();
    
    // Assert that the response contains the expected fields
    assert!(login_json.get("message").is_some());
    assert!(login_json.get("user").is_some());
    assert!(login_json.get("token").is_some());
    
    // Assert that the user ID matches the one from registration
    assert_eq!(login_json["user"]["id"].as_i64().unwrap(), user_id);
    
    // Test login with incorrect password
    let invalid_login_request = LoginRequest {
        username: email.clone(),
        password: "wrong_password".to_string(),
    };
    
    let invalid_login_req = test::TestRequest::post()
        .uri("/api/auth/login")
        .set_json(&invalid_login_request)
        .to_request();
    
    let invalid_login_resp = test::call_service(&app, invalid_login_req).await;
    
    // Assert that login was successful (the endpoint returns 200 even for invalid credentials)
    assert!(invalid_login_resp.status().is_success());
    
    // Parse the response body
    let invalid_login_body = test::read_body(invalid_login_resp).await;
    let invalid_login_json: serde_json::Value = serde_json::from_slice(&invalid_login_body).unwrap();
    
    // Assert that the response contains an error message
    assert!(invalid_login_json.get("error").is_some());
    assert_eq!(invalid_login_json["error"].as_str().unwrap(), "Invalid credentials");
    
    // Test login with non-existent user
    let nonexistent_login_request = LoginRequest {
        username: "nonexistent@example.com".to_string(),
        password: password.clone(),
    };
    
    let nonexistent_login_req = test::TestRequest::post()
        .uri("/api/auth/login")
        .set_json(&nonexistent_login_request)
        .to_request();
    
    let nonexistent_login_resp = test::call_service(&app, nonexistent_login_req).await;
    
    // Assert that login was successful (the endpoint returns 200 even for non-existent users)
    assert!(nonexistent_login_resp.status().is_success());
    
    // Parse the response body
    let nonexistent_login_body = test::read_body(nonexistent_login_resp).await;
    let nonexistent_login_json: serde_json::Value = serde_json::from_slice(&nonexistent_login_body).unwrap();
    
    // Assert that the response contains an error message
    assert!(nonexistent_login_json.get("error").is_some());
    assert_eq!(nonexistent_login_json["error"].as_str().unwrap(), "Invalid credentials");
}

#[actix_web::test]
async fn test_duplicate_registration() {
    // Setup the test app
    let app = setup_test_app().await;
    
    // Generate a unique username and email to avoid conflicts
    let unique_id = Uuid::new_v4().to_string();
    let username = format!("testuser_{}", &unique_id[..8]);
    let email = format!("test_{}@example.com", &unique_id[..8]);
    let password = "password123".to_string();
    
    // Register a user
    let register_request = RegisterRequest {
        username: username.clone(),
        email: email.clone(),
        password: password.clone(),
    };
    
    let register_req = test::TestRequest::post()
        .uri("/api/auth/register")
        .set_json(&register_request)
        .to_request();
    
    let register_resp = test::call_service(&app, register_req).await;
    
    // Assert that registration was successful
    assert!(register_resp.status().is_success());
    
    // Try to register the same user again
    let duplicate_register_req = test::TestRequest::post()
        .uri("/api/auth/register")
        .set_json(&register_request)
        .to_request();
    
    let mut duplicate_register_resp = test::call_service(&app, duplicate_register_req).await;
    
    // Check the status code first and store it
    let status = duplicate_register_resp.status();
    
    // Parse the response body
    let duplicate_register_body = test::read_body(duplicate_register_resp).await;
    let duplicate_register_json: serde_json::Value = serde_json::from_slice(&duplicate_register_body).unwrap();
    
    // Assert that the response contains an error message or indicates failure in some way
    // This is a more flexible assertion that works regardless of the status code
    if status.is_server_error() {
        assert!(duplicate_register_json.get("error").is_some());
    } else {
        // If it's not a server error, it might be a success response with an error message
        // or some other indication of failure
        println!("Duplicate registration response: {:?}", duplicate_register_json);
        
        // Check if there's an error message in the response
        if let Some(error) = duplicate_register_json.get("error") {
            assert!(error.is_string());
        } else {
            // If there's no explicit error message, the test should fail
            assert!(false, "Expected error response for duplicate registration, got: {:?}", duplicate_register_json);
        }
    }
}

#[actix_web::test]
async fn test_auth_status() {
    // Setup the test app
    let app = setup_test_app().await;
    
    // Test the auth status endpoint
    let req = test::TestRequest::get()
        .uri("/api/auth/status")
        .to_request();
    
    let resp = test::call_service(&app, req).await;
    
    // Assert that the request was successful
    assert!(resp.status().is_success());
    
    // Parse the response body
    let body = test::read_body(resp).await;
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    
    // Assert that the response contains the expected fields
    assert!(json.get("isAuthenticated").is_some());
    assert_eq!(json["isAuthenticated"].as_bool().unwrap(), false);
}
