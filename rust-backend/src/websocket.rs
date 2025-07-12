use actix_web::{web, get, HttpRequest, HttpResponse};
use actix_web_actors::ws;
use actix::ActorContext;
use actix::AsyncContext;
use tokio::sync::mpsc;
use std::{collections::HashMap, sync::Arc};
use tokio::sync::Mutex;
use log::info;

use crate::models::Comment;
use crate::AppState;

pub fn broadcast_comment(video_id: i32, comment: Comment, clients: HashMap<i32, Vec<tokio::sync::mpsc::Sender<String>>>) {
    if let Some(client_list) = clients.get(&video_id).cloned() {
        for tx in client_list {
            let comment_json = serde_json::to_string(&comment).unwrap_or_else(|_| String::from("Error serializing comment"));
            // Clone the comment_json for each task
            let msg = comment_json.clone();
            tokio::spawn(async move {
                let _ = tx.send(msg).await;
            });
        }
    }
}

struct VideoWebSocket {
    video_id: i32,
    state: Arc<Mutex<AppState>>,
    tx: mpsc::Sender<String>,
}

impl actix::Actor for VideoWebSocket {
    type Context = ws::WebsocketContext<Self>;

    fn started(&mut self, _ctx: &mut Self::Context) {
        let state = self.state.clone();
        let video_id = self.video_id;
        let tx = self.tx.clone();
        tokio::spawn(async move {
            let state = state.lock().await;
            let mut clients = state.video_clients.lock().unwrap();
            clients.entry(video_id)
                .or_insert_with(Vec::new)
                .push(tx);
            info!("WebSocket client connected for video_id: {}", video_id);
        });
    }

    fn stopped(&mut self, ctx: &mut Self::Context) {
        let state = self.state.clone();
        let video_id = self.video_id;
        let tx = self.tx.clone();
        tokio::spawn(async move {
            let state = state.lock().await;
            let mut clients = state.video_clients.lock().unwrap();
            if let Some(client_list) = clients.get_mut(&video_id) {
                client_list.retain(|tx_ref| !tx_ref.same_channel(&tx));
                if client_list.is_empty() {
                    clients.remove(&video_id);
                }
            }
            info!("WebSocket client disconnected for video_id: {}", video_id);
        });
        ctx.terminate();
    }
}

impl actix::StreamHandler<Result<ws::Message, ws::ProtocolError>> for VideoWebSocket {
    fn handle(&mut self, msg: Result<ws::Message, ws::ProtocolError>, ctx: &mut Self::Context) {
        match msg {
            Ok(ws::Message::Ping(msg)) => ctx.pong(&msg),
            Ok(ws::Message::Text(text)) => {
                info!("Received WebSocket message for video_id {}: {}", self.video_id, text);
                // Echo back for testing or handle client messages if needed
                ctx.text(text)
            }
            Ok(ws::Message::Close(reason)) => {
                ctx.close(reason);
                ctx.stop();
            }
            _ => (),
        }
    }
}

#[get("/api/ws/comments/{video_id}")]
async fn websocket_comments(
    path: web::Path<i32>,
    req: HttpRequest,
    stream: web::Payload,
    state: web::Data<Arc<Mutex<AppState>>>,
) -> Result<HttpResponse, actix_web::Error> {
    let video_id = path.into_inner();
    let (tx, mut rx) = mpsc::channel(100);

    let resp = ws::start(
        VideoWebSocket {
            video_id,
            state: state.get_ref().clone(),
            tx,
        },
        &req,
        stream,
    )?;

    // Spawn a task to send messages from the channel to the WebSocket client
    tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            // This is a placeholder; in a real implementation, you would send the message to the WebSocket client
            info!("Sending message to WebSocket client for video_id {}: {}", video_id, msg);
            // Here, you would typically send the message to the WebSocket context, but since we can't access it directly,
            // this is handled by the actor's context in a real implementation.
        }
    });

    Ok(resp)
}

use serde::{Deserialize, Serialize};
use jsonwebtoken::{decode, DecodingKey, Validation};
use std::env;

// Message type for the WebSocket actor
#[derive(actix::Message)]
#[rtype(result = "()")]
struct WsMessage(String);

// Watch Party WebSocket for synchronization
struct WatchPartyWebSocket {
    video_id: i32,
    user_id: Option<i32>,
    state: Arc<Mutex<AppState>>,
    tx: mpsc::Sender<String>,
    authenticated: bool,
}

// Handle messages sent to the actor
impl actix::Handler<WsMessage> for WatchPartyWebSocket {
    type Result = ();

    fn handle(&mut self, msg: WsMessage, ctx: &mut Self::Context) {
        // Forward the message to the WebSocket client
        ctx.text(msg.0);
    }
}

impl actix::Actor for WatchPartyWebSocket {
    type Context = ws::WebsocketContext<Self>;

    fn started(&mut self, ctx: &mut Self::Context) {
        let state = self.state.clone();
        let video_id = self.video_id;
        let tx = self.tx.clone();
        let addr = ctx.address();
        
        // Register this client in the watchparty_clients map
        tokio::spawn(async move {
            let state = state.lock().await;
            let mut clients = state.watchparty_clients.lock().unwrap();
            clients.entry(video_id)
                .or_insert_with(Vec::new)
                .push(tx);
            
            info!("WatchParty WebSocket client connected for video_id: {}. Total clients: {}", 
                  video_id, 
                  clients.get(&video_id).map(|list| list.len()).unwrap_or(0));
        });
        
        // Create a receiver for this client
        let (client_tx, mut client_rx) = mpsc::channel::<String>(100);
        
        // Store the sender in the watchparty_clients map
        let state_clone = self.state.clone();
        let video_id_clone = self.video_id;
        tokio::spawn(async move {
            let state = state_clone.lock().await;
            let mut clients = state.watchparty_clients.lock().unwrap();
            
            clients.entry(video_id_clone)
                .or_insert_with(Vec::new)
                .push(client_tx);
            
            info!("Added client channel to watchparty_clients map for video_id: {}", video_id_clone);
        });
        
        // Spawn a task to forward messages from the channel to the WebSocket
        let addr_clone = addr.clone();
        actix::spawn(async move {
            while let Some(msg) = client_rx.recv().await {
                info!("Forwarding message to WebSocket client for video_id {}: {}", video_id, msg);
                addr_clone.do_send(WsMessage(msg));
            }
        });
    }

    fn stopped(&mut self, ctx: &mut Self::Context) {
        let state = self.state.clone();
        let video_id = self.video_id;
        let tx = self.tx.clone();
        tokio::spawn(async move {
            let state = state.lock().await;
            let mut clients = state.watchparty_clients.lock().unwrap();
            if let Some(client_list) = clients.get_mut(&video_id) {
                client_list.retain(|tx_ref| !tx_ref.same_channel(&tx));
                info!("WatchParty WebSocket client disconnected. Remaining clients for video_id {}: {}", 
                      video_id, client_list.len());
                if client_list.is_empty() {
                    clients.remove(&video_id);
                    info!("Removed empty client list for video_id: {}", video_id);
                }
            }
            info!("WatchParty WebSocket client disconnected for video_id: {}", video_id);
        });
        ctx.terminate();
    }
}

impl actix::StreamHandler<Result<ws::Message, ws::ProtocolError>> for WatchPartyWebSocket {
    fn handle(&mut self, msg: Result<ws::Message, ws::ProtocolError>, ctx: &mut Self::Context) {
        match msg {
            Ok(ws::Message::Ping(msg)) => ctx.pong(&msg),
            Ok(ws::Message::Text(text)) => {
                info!("Received WatchParty WebSocket message for video_id {}: {}", self.video_id, text);
                
                // Try to parse as an auth message first
                if let Ok(auth_msg) = serde_json::from_str::<serde_json::Value>(&text) {
                    if auth_msg["type"] == "auth" && auth_msg["token"].is_string() {
                        let token = auth_msg["token"].as_str().unwrap();
                        let jwt_secret = env::var("JWT_SECRET").unwrap_or_else(|_| "secure_jwt_secret_key_12345".to_string());
                        let claims_result = decode::<crate::models::Claims>(
                            token,
                            &DecodingKey::from_secret(jwt_secret.as_ref()),
                            &Validation::default(),
                        ).ok().map(|decoded| decoded.claims.user_id);
                        
                        if let Some(user_id) = claims_result {
                            self.user_id = Some(user_id);
                            self.authenticated = true;
                            info!("WatchParty WebSocket authenticated for user_id: {}", user_id);
                            return;
                        }
                    }
                }
                
                // If not authenticated and not an auth message, ignore
                if !self.authenticated && self.user_id.is_none() {
                    info!("Ignoring message from unauthenticated WatchParty WebSocket");
                    return;
                }
                
                // Handle control messages
                if let Ok(control_msg) = serde_json::from_str::<ControlMessage>(&text) {
                    info!("Processing control message: action={}, time={:?}", control_msg.action, control_msg.time);
                    let state = self.state.clone();
                    let video_id = self.video_id;
                    let user_id = self.user_id.unwrap_or(-1);
                    // Generate a unique source_id for this message
                    let timestamp = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_millis();
                    let source_id = format!("user_{}_time_{}", user_id, timestamp);
                    
                    // Create the control message with user info
                    let control_msg_with_user = ControlMessageWithUser {
                        type_field: "watchPartyControl".to_string(),
                        action: control_msg.action.clone(),
                        time: control_msg.time,
                        user_id,
                        video_id,
                        source_id: source_id.clone(),
                    };
                    
                    // Convert to JSON string for sending to clients
                    let msg_json = serde_json::to_string(&control_msg_with_user)
                        .unwrap_or_else(|_| text.to_string());
                    
                    info!("Broadcasting control message from user_id={} to all clients for video_id={}", user_id, video_id);

                    // Echo back the enhanced message with source_id to the sender
                    // This ensures the sender gets the same message format as other clients
                    ctx.text(msg_json.clone());
                    
                    // Use a separate async task to handle broadcasting without blocking the current context
                    let sender_tx = self.tx.clone();
                    tokio::spawn(async move {
                        // Get the client list and clone it to avoid holding the mutex across await points
                        let client_list = {
                            let state_guard = state.lock().await;
                            let clients = state_guard.watchparty_clients.lock().unwrap();
                            clients.get(&video_id).cloned()
                        };

                        // Now send messages if we have clients
                        if let Some(client_list) = client_list {
                            info!("Found {} clients for video_id={}", client_list.len(), video_id);
                            
                            // For each client in the watchparty_clients HashMap for this video_id
                            for (i, tx) in client_list.iter().enumerate() {
                                // Skip sending the message back to the sender to avoid infinite loops
                                if tx.same_channel(&sender_tx) {
                                    info!("Skipping sender (client {}) for video_id={}", i, video_id);
                                    continue;
                                }
                                
                                // Send the message to the client's channel
                                // This will be received by the task in the actor's started method
                                // which will then forward it to the WebSocket connection
                                let result = tx.send(msg_json.clone()).await;
                                match result {
                                    Ok(_) => info!("Successfully sent message to client {} for video_id={}", i, video_id),
                                    Err(e) => info!("Failed to send message to client {} for video_id={}: {:?}", i, video_id, e),
                                }
                            }
                        } else {
                            info!("No clients found for video_id={}", video_id);
                        }
                    });
                } else {
                    // For non-control messages, just echo back the original text
                    ctx.text(text);
                }
            }
            Ok(ws::Message::Close(reason)) => {
                ctx.close(reason);
                ctx.stop();
            }
            _ => (),
        }
    }
}

#[derive(Serialize, Deserialize)]
struct ControlMessage {
    action: String,
    time: Option<f64>,
}

#[derive(Serialize)]
struct ControlMessageWithUser {
    type_field: String,
    action: String,
    time: Option<f64>,
    user_id: i32,
    video_id: i32,
    source_id: String, // Add a source_id field to identify the origin of the message
}

#[get("/api/ws/watchparty/{video_id}")]
async fn websocket_watchparty(
    path: web::Path<i32>,
    req: HttpRequest,
    stream: web::Payload,
    state: web::Data<Arc<Mutex<AppState>>>,
) -> Result<HttpResponse, actix_web::Error> {
    let video_id = path.into_inner();
    
    // Create a channel for this specific WebSocket connection
    let (tx, mut _rx) = mpsc::channel(100);
    
    info!("Setting up new WebSocket connection for video_id: {}", video_id);
    
    // Initialize the WebSocket actor with no user_id and not authenticated
    // The client will send an auth message with the token after connecting
    let ws = WatchPartyWebSocket {
        video_id,
        user_id: None,
        state: state.get_ref().clone(),
        tx: tx.clone(), // Clone the sender for the actor
        authenticated: false,
    };
    
    // Start the WebSocket actor
    let resp = ws::start(ws, &req, stream)?;
    
    // Store the sender in the watchparty_clients map
    tokio::spawn(async move {
        let state = state.get_ref().clone();
        let state_guard = state.lock().await;
        let mut clients = state_guard.watchparty_clients.lock().unwrap();
        
        clients.entry(video_id)
            .or_insert_with(Vec::new)
            .push(tx);
        
        info!("Added WebSocket client to watchparty_clients map for video_id: {}", video_id);
    });
    
    Ok(resp)
}

pub fn configure_ws_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(websocket_comments)
       .service(websocket_watchparty);
}
