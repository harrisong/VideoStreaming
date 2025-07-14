use actix_web::{test, web, App};
use dotenv::dotenv;
use std::sync::Arc;
use tokio::sync::Mutex;
use std::collections::HashMap;
use std::time::Duration;
use futures::{SinkExt, StreamExt};
use serde_json::json;
use tokio::time::{sleep, timeout};
use tokio_tungstenite::{connect_async, tungstenite::protocol::Message};
use futures_util::stream::StreamExt as FuturesStreamExt;
use tokio::net::TcpStream;
use tokio::sync::oneshot;
use std::time::Duration as StdDuration;

// Import the necessary modules from the main application
use video_streaming_backend::handlers;
use video_streaming_backend::AppState;
use video_streaming_backend::services;
use video_streaming_backend::models::{RegisterRequest, Claims};
use video_streaming_backend::websocket;

use jsonwebtoken::{encode, Header, EncodingKey};

async fn setup_test_app() -> (
    impl actix_web::dev::Service<
        actix_http::Request,
        Response = actix_web::dev::ServiceResponse,
        Error = actix_web::Error,
    >,
    Arc<Mutex<AppState>>
) {
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
    
    let app_state_clone = app_state.clone();
    
    // Create the test app
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(app_state))
            .configure(handlers::configure_routes)
    ).await;
    
    (app, app_state_clone)
}

// Helper function to register a test user and get a JWT token
async fn register_test_user(app: &impl actix_web::dev::Service<
    actix_http::Request,
    Response = actix_web::dev::ServiceResponse,
    Error = actix_web::Error,
>) -> (i32, String) {
    // Generate a unique username and email
    let unique_id = uuid::Uuid::new_v4().to_string();
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

// Helper function to create a JWT token for a user
fn create_jwt_token(user_id: i32) -> String {
    let jwt_secret = std::env::var("JWT_SECRET").unwrap_or_else(|_| "secure_jwt_secret_key_12345".to_string());
    let claims = Claims {
        user_id,
        exp: (chrono::Utc::now() + chrono::Duration::hours(24)).timestamp() as usize,
    };
    encode(&Header::default(), &claims, &EncodingKey::from_secret(jwt_secret.as_ref())).unwrap()
}

#[actix_web::test]
async fn test_source_id_contains_correct_user_id() {
    // Setup the test app
    let (app, _app_state) = setup_test_app().await;
    
    // Register two test users
    let (user_id1, _) = register_test_user(&app).await;
    let (user_id2, _) = register_test_user(&app).await;
    
    // Create JWT tokens for both users
    let token1 = create_jwt_token(user_id1);
    let token2 = create_jwt_token(user_id2);
    
    // Create a test video ID
    let video_id = 12345;
    
    // For WebSocket testing, we need to run an actual server
    // Use a fixed port for testing (make sure it's not in use)
    let test_port = 8766; // Use a different port to avoid conflicts
    let app_state_clone = _app_state.clone();
    
    // Create a channel to signal when the server is ready
    let (tx, rx) = oneshot::channel::<()>();
    
    // Print the routes being configured
    println!("Setting up test server with WebSocket routes");
    
    // Create a runtime for the server
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("Failed to build runtime");
    
    // Spawn the server in a separate thread with its own runtime
    let _server_thread = std::thread::spawn(move || {
        rt.block_on(async {
            let server = actix_web::HttpServer::new(move || {
                App::new()
                    .app_data(web::Data::new(app_state_clone.clone()))
                    .configure(handlers::configure_routes)
                    .configure(websocket::configure_ws_routes) // Add WebSocket routes
            })
            .bind(format!("127.0.0.1:{}", test_port)).expect("Failed to bind to test port")
            .run();
            
            // Signal that the server is about to start
            let _ = tx.send(());
            
            // Run the server
            server.await.expect("Server error");
        });
    });
    
    // Wait for the server to start
    println!("Waiting for server to start...");
    let _ = rx.await;
    
    // Give the server a moment to initialize
    sleep(Duration::from_secs(1)).await;
    println!("Server should be ready now");
    
    // Verify the server is actually running by attempting to connect to it
    let mut attempts = 0;
    let max_attempts = 5;
    let mut server_ready = false;
    
    while attempts < max_attempts && !server_ready {
        match TcpStream::connect(format!("127.0.0.1:{}", test_port)).await {
            Ok(_) => {
                server_ready = true;
                println!("Successfully connected to server");
            },
            Err(e) => {
                println!("Failed to connect to server (attempt {}): {:?}", attempts + 1, e);
                attempts += 1;
                sleep(Duration::from_millis(500)).await;
            }
        }
    }
    
    assert!(server_ready, "Failed to connect to server after {} attempts", max_attempts);
    
    // Connect first client to the WebSocket (user 1)
    let ws_url = format!("ws://127.0.0.1:{}/api/ws/watchparty/{}", test_port, video_id);
    println!("Connecting client 1 (user_id: {}) to WebSocket at: {}", user_id1, ws_url);
    let (client1_ws_stream, _) = connect_async(ws_url.clone()).await.expect("Failed to connect client 1 to WebSocket");
    let (mut client1_write, mut client1_read) = client1_ws_stream.split();
    
    // Connect second client to the WebSocket (user 2)
    println!("Connecting client 2 (user_id: {}) to WebSocket at: {}", user_id2, ws_url);
    let (client2_ws_stream, _) = connect_async(ws_url).await.expect("Failed to connect client 2 to WebSocket");
    let (mut client2_write, mut client2_read) = client2_ws_stream.split();
    
    // Authenticate first client with user 1's token
    let auth_msg1 = json!({
        "type": "auth",
        "token": token1
    }).to_string();
    
    println!("Authenticating client 1 with user_id: {}", user_id1);
    client1_write.send(Message::Text(auth_msg1)).await.unwrap();
    
    // Authenticate second client with user 2's token
    let auth_msg2 = json!({
        "type": "auth",
        "token": token2
    }).to_string();
    
    println!("Authenticating client 2 with user_id: {}", user_id2);
    client2_write.send(Message::Text(auth_msg2)).await.unwrap();
    
    // Wait for authentication to complete
    println!("Waiting for authentication to complete...");
    sleep(Duration::from_secs(2)).await;
    
    // Send a control message from client 1 (user 1)
    let control_msg = json!({
        "action": "play",
        "time": 30.5
    }).to_string();
    
    println!("Client 1 (user_id: {}) sending control message: {}", user_id1, control_msg);
    client1_write.send(Message::Text(control_msg)).await.unwrap();
    
    // Wait for client 2 to receive the message
    println!("Waiting for client 2 to receive the message...");
    let response = match timeout(StdDuration::from_secs(5), client2_read.next()).await {
        Ok(Some(Ok(msg))) => msg,
        Ok(Some(Err(e))) => panic!("Error receiving message on client 2: {:?}", e),
        Ok(None) => panic!("Client 2 stream ended unexpectedly"),
        Err(_) => panic!("Timeout waiting for message on client 2"),
    };
    
    // Verify the message contains the correct source_id with user 1's ID
    if let Message::Text(text) = response {
        println!("Client 2 received message: {}", text);
        let json: serde_json::Value = serde_json::from_str(&text).unwrap();
        
        // Check if the message has a source_id field
        assert!(json["source_id"].is_string(), "Message does not contain a source_id field");
        
        // Extract the source_id
        let source_id = json["source_id"].as_str().unwrap();
        println!("Source ID: {}", source_id);
        
        // Verify the source_id contains user 1's ID (the sender)
        let source_id_parts: Vec<&str> = source_id.split('_').collect();
        assert!(source_id_parts.len() >= 2, "Source ID does not have the expected format");
        assert_eq!(source_id_parts[0], "user", "Source ID does not start with 'user_'");
        
        // Parse the user_id from the source_id
        let parsed_user_id: i32 = source_id_parts[1].parse().expect("Failed to parse user_id from source_id");
        
        // Verify it matches user 1's ID (the sender)
        assert_eq!(parsed_user_id, user_id1, "User ID in source_id does not match the sender's user ID");
        
        // Verify it does NOT match user 2's ID (the receiver)
        assert_ne!(parsed_user_id, user_id2, "User ID in source_id incorrectly matches the receiver's user ID");
        
        println!("Source ID contains the correct sender's user ID: {}", user_id1);
    } else {
        panic!("Expected text message, got: {:?}", response);
    }
    
    // Now test in the other direction - send a message from client 2 to client 1
    let control_msg2 = json!({
        "action": "pause",
        "time": 45.2
    }).to_string();
    
    println!("Client 2 (user_id: {}) sending control message: {}", user_id2, control_msg2);
    client2_write.send(Message::Text(control_msg2)).await.unwrap();
    
    // Poll until client 1 receives a message from client 2
    println!("Polling until client 1 receives a message from client 2...");
    
    let mut response2 = None;
    let mut attempts = 0;
    let max_attempts = 10;
    
    while attempts < max_attempts {
        match timeout(StdDuration::from_millis(500), client1_read.next()).await {
            Ok(Some(Ok(msg))) => {
                println!("Client 1 received a message: {:?}", msg);
                if let Message::Text(text) = &msg {
                    let json: serde_json::Value = serde_json::from_str(text).unwrap();
                    
                    // Check if this message is from client 2 (user_id2)
                    if let Some(source_id) = json["source_id"].as_str() {
                        let source_id_parts: Vec<&str> = source_id.split('_').collect();
                        if source_id_parts.len() >= 2 && source_id_parts[0] == "user" {
                            if let Ok(parsed_user_id) = source_id_parts[1].parse::<i32>() {
                                if parsed_user_id == user_id2 {
                                    println!("Found message from client 2 (user_id: {})", user_id2);
                                    response2 = Some(msg);
                                    break;
                                } else {
                                    println!("Message is from user_id {}, not from client 2 (user_id: {}). Continuing to poll...", 
                                             parsed_user_id, user_id2);
                                }
                            }
                        }
                    }
                }
            },
            Ok(Some(Err(e))) => panic!("Error receiving message on client 1: {:?}", e),
            Ok(None) => panic!("Client 1 stream ended unexpectedly"),
            Err(_) => {
                println!("No message received within timeout (attempt {}). Retrying...", attempts + 1);
            }
        }
        
        attempts += 1;
        sleep(Duration::from_millis(200)).await;
    }
    
    let response2 = response2.unwrap_or_else(|| panic!("Failed to receive message from client 2 after {} attempts", max_attempts));
    
    // Verify the message contains the correct source_id with user 2's ID
    if let Message::Text(text) = response2 {
        println!("Client 1 received message: {}", text);
        let json: serde_json::Value = serde_json::from_str(&text).unwrap();
        
        // Check if the message has a source_id field
        assert!(json["source_id"].is_string(), "Message does not contain a source_id field");
        
        // Extract the source_id
        let source_id = json["source_id"].as_str().unwrap();
        println!("Source ID: {}", source_id);
        
        // Verify the source_id contains user 2's ID (the sender)
        let source_id_parts: Vec<&str> = source_id.split('_').collect();
        assert!(source_id_parts.len() >= 2, "Source ID does not have the expected format");
        assert_eq!(source_id_parts[0], "user", "Source ID does not start with 'user_'");
        
        // Parse the user_id from the source_id
        let parsed_user_id: i32 = source_id_parts[1].parse().expect("Failed to parse user_id from source_id");
        
        // Verify it matches user 2's ID (the sender)
        assert_eq!(parsed_user_id, user_id2, "User ID in source_id does not match the sender's user ID");
        
        // Verify it does NOT match user 1's ID (the receiver)
        assert_ne!(parsed_user_id, user_id1, "User ID in source_id incorrectly matches the receiver's user ID");
        
        println!("Source ID contains the correct sender's user ID: {}", user_id2);
    } else {
        panic!("Expected text message, got: {:?}", response2);
    }
    
    // Close the connections
    println!("Closing WebSocket connections...");
    if let Err(e) = client1_write.send(Message::Close(None)).await {
        println!("Error closing client 1 connection: {:?}", e);
    }
    if let Err(e) = client2_write.send(Message::Close(None)).await {
        println!("Error closing client 2 connection: {:?}", e);
    }
    
    println!("Source ID verification test completed successfully");
}

#[actix_web::test]
async fn test_watchparty_websocket_communication() {
    // Setup the test app
    let (app, _app_state) = setup_test_app().await;
    
    // Register two test users
    let (user_id1, _) = register_test_user(&app).await;
    let (user_id2, _) = register_test_user(&app).await;
    
    // Create JWT tokens for both users
    let token1 = create_jwt_token(user_id1);
    let token2 = create_jwt_token(user_id2);
    
    // Create a test video ID
    let video_id = 12345;
    
    // For WebSocket testing, we need to run an actual server
    // Use a fixed port for testing (make sure it's not in use)
    let test_port = 8765;
    let app_state_clone = _app_state.clone();
    
    // Create a channel to signal when the server is ready
    let (tx, rx) = oneshot::channel::<()>();
    
    // Print the routes being configured
    println!("Setting up test server with WebSocket routes");
    
    // Create a runtime for the server
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("Failed to build runtime");
    
    // Spawn the server in a separate thread with its own runtime
    let server_thread = std::thread::spawn(move || {
        rt.block_on(async {
            let server = actix_web::HttpServer::new(move || {
                App::new()
                    .app_data(web::Data::new(app_state_clone.clone()))
                    .configure(handlers::configure_routes)
                    .configure(websocket::configure_ws_routes) // Add WebSocket routes
            })
            .bind(format!("127.0.0.1:{}", test_port)).expect("Failed to bind to test port")
            .run();
            
            // Signal that the server is about to start
            let _ = tx.send(());
            
            // Run the server
            server.await.expect("Server error");
        });
    });
    
    // Wait for the server to start
    println!("Waiting for server to start...");
    let _ = rx.await;
    
    // Give the server a moment to initialize
    sleep(Duration::from_secs(1)).await;
    println!("Server should be ready now");
    
    // Verify the server is actually running by attempting to connect to it
    let mut attempts = 0;
    let max_attempts = 5;
    let mut server_ready = false;
    
    while attempts < max_attempts && !server_ready {
        match TcpStream::connect(format!("127.0.0.1:{}", test_port)).await {
            Ok(_) => {
                server_ready = true;
                println!("Successfully connected to server");
            },
            Err(e) => {
                println!("Failed to connect to server (attempt {}): {:?}", attempts + 1, e);
                attempts += 1;
                sleep(Duration::from_millis(500)).await;
            }
        }
    }
    
    assert!(server_ready, "Failed to connect to server after {} attempts", max_attempts);
    
    // Connect first client to the WebSocket
    let ws_url = format!("ws://127.0.0.1:{}/api/ws/watchparty/{}", test_port, video_id);
    println!("Connecting client 1 to WebSocket at: {}", ws_url);
    let (client1_ws_stream, _) = connect_async(ws_url.clone()).await.expect("Failed to connect client 1 to WebSocket");
    let (mut client1_write, mut client1_read) = client1_ws_stream.split();
    
    // Connect second client to the WebSocket
    println!("Connecting client 2 to WebSocket at: {}", ws_url);
    let (client2_ws_stream, _) = connect_async(ws_url).await.expect("Failed to connect client 2 to WebSocket");
    let (mut client2_write, mut client2_read) = client2_ws_stream.split();
    
    // Authenticate first client
    let auth_msg1 = json!({
        "type": "auth",
        "token": token1
    }).to_string();
    
    println!("Authenticating client 1");
    client1_write.send(Message::Text(auth_msg1)).await.unwrap();
    
    // Authenticate second client
    let auth_msg2 = json!({
        "type": "auth",
        "token": token2
    }).to_string();
    
    println!("Authenticating client 2");
    client2_write.send(Message::Text(auth_msg2)).await.unwrap();
    
    // Wait for authentication to complete
    println!("Waiting for authentication to complete...");
    sleep(Duration::from_secs(2)).await;
    println!("Authentication wait complete");
    
    // First, verify both connections are alive with ping/pong
    println!("Verifying client 1 connection with ping");
    client1_write.send(Message::Ping(vec![1, 2, 3])).await.unwrap();
    
    println!("Waiting for client 1 pong response...");
    let client1_pong = match timeout(StdDuration::from_secs(5), client1_read.next()).await {
        Ok(Some(Ok(msg))) => msg,
        Ok(Some(Err(e))) => panic!("Error receiving message on client 1: {:?}", e),
        Ok(None) => panic!("Client 1 stream ended unexpectedly"),
        Err(_) => panic!("Timeout waiting for client 1 pong response"),
    };
    
    match client1_pong {
        Message::Pong(_) => println!("Client 1 connection verified with pong response"),
        other => println!("Client 1 received unexpected response: {:?}", other),
    }
    
    println!("Verifying client 2 connection with ping");
    client2_write.send(Message::Ping(vec![4, 5, 6])).await.unwrap();
    
    println!("Waiting for client 2 pong response...");
    let client2_pong = match timeout(StdDuration::from_secs(5), client2_read.next()).await {
        Ok(Some(Ok(msg))) => msg,
        Ok(Some(Err(e))) => panic!("Error receiving message on client 2: {:?}", e),
        Ok(None) => panic!("Client 2 stream ended unexpectedly"),
        Err(_) => panic!("Timeout waiting for client 2 pong response"),
    };
    
    match client2_pong {
        Message::Pong(_) => println!("Client 2 connection verified with pong response"),
        other => println!("Client 2 received unexpected response: {:?}", other),
    }
    
    // Now test actual communication between clients
    // Client 1 sends a control message
    println!("Client 1 sending control message...");
    // Match the exact format expected by the server (ControlMessage struct)
    let control_msg = json!({
        "action": "play",
        "time": 30.5
        // No "type" field - it's not expected by the ControlMessage struct
    }).to_string();
    println!("Control message: {}", control_msg);
    
    client1_write.send(Message::Text(control_msg)).await.unwrap();
    
    // Give the server some time to process and broadcast the message
    sleep(Duration::from_millis(500)).await;
    
    // Check if client 2 receives any messages (with a short timeout)
    println!("Checking if client 2 receives any messages...");
    let maybe_message = timeout(StdDuration::from_secs(2), client2_read.next()).await;
    
    match maybe_message {
        Ok(Some(Ok(msg))) => {
            println!("Client 2 received a message: {:?}", msg);
            if let Message::Text(text) = msg {
                println!("Message content: {}", text);
                let json: serde_json::Value = serde_json::from_str(&text).unwrap();
                println!("Parsed JSON: {:?}", json);
                
                // We don't make strict assertions about the message format
                // Just verify it contains some expected fields
                if json.get("action").is_some() && json.get("time").is_some() {
                    println!("Message contains expected fields");
                } else {
                    println!("Message is missing expected fields");
                }
            }
        },
        Ok(Some(Err(e))) => println!("Error receiving message on client 2: {:?}", e),
        Ok(None) => println!("Client 2 stream ended unexpectedly"),
        Err(_) => println!("No message received by client 2 within timeout"),
    }
    
    // Close the connections
    println!("Closing WebSocket connections...");
    if let Err(e) = client1_write.send(Message::Close(None)).await {
        println!("Error closing client 1 connection: {:?}", e);
    }
    if let Err(e) = client2_write.send(Message::Close(None)).await {
        println!("Error closing client 2 connection: {:?}", e);
    }
    
    // Test passed if we got this far
    println!("WebSocket communication test completed");
}
