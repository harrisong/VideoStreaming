use actix_web::{web, get, HttpRequest, HttpResponse};
use actix_web_actors::ws;
use actix::ActorContext;
use tokio::sync::mpsc;
use std::sync::Arc;
use tokio::sync::Mutex;
use log::info;

use crate::models::Comment;
use crate::AppState;

pub async fn broadcast_comment(video_id: i32, comment: &Comment, state: &Arc<Mutex<AppState>>) {
    let state = state.lock().await;
    let clients = state.video_clients.lock().unwrap();
    if let Some(client_list) = clients.get(&video_id) {
        let comment_json = serde_json::to_string(comment).unwrap_or_else(|_| String::from("Error serializing comment"));
        for tx in client_list {
            let _ = tx.send(comment_json.clone()).await;
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

// Watch Party WebSocket for synchronization
struct WatchPartyWebSocket {
    video_id: i32,
    user_id: Option<i32>,
    state: Arc<Mutex<AppState>>,
    tx: mpsc::Sender<String>,
}

impl actix::Actor for WatchPartyWebSocket {
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
            info!("WatchParty WebSocket client connected for video_id: {}", video_id);
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
                if let Ok(control_msg) = serde_json::from_str::<ControlMessage>(&text) {
                    let state = self.state.clone();
                    let video_id = self.video_id;
                    let msg_json = serde_json::to_string(&ControlMessageWithUser {
                        type_field: "watchPartyControl".to_string(),
                        action: control_msg.action,
                        time: control_msg.time,
                        user_id: self.user_id.unwrap_or(-1),
                        video_id,
                    }).unwrap_or_else(|_| text.to_string());
                    // Use a separate async task to handle broadcasting without blocking the current context
                    tokio::spawn(async move {
                        // Get the client list and clone it to avoid holding the mutex across await points
                        let client_list = {
                            let state_guard = state.lock().await;
                            let clients = state_guard.video_clients.lock().unwrap();
                            clients.get(&video_id).cloned()
                        };

                        // Now send messages if we have clients
                        if let Some(client_list) = client_list {
                            for tx in client_list {
                                let _ = tx.send(msg_json.clone()).await;
                            }
                        }
                    });
                }
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
}

#[get("/api/ws/watchparty/{video_id}")]
async fn websocket_watchparty(
    path: web::Path<i32>,
    req: HttpRequest,
    stream: web::Payload,
    state: web::Data<Arc<Mutex<AppState>>>,
) -> Result<HttpResponse, actix_web::Error> {
    let video_id = path.into_inner();
    let (tx, mut rx) = mpsc::channel(100);
    let auth_header = req.headers().get(actix_web::http::header::AUTHORIZATION);
    let user_id = auth_header.and_then(|h| h.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
        .and_then(|token| {
            let jwt_secret = env::var("JWT_SECRET").unwrap_or_else(|_| "secure_jwt_secret_key_12345".to_string());
            decode::<crate::models::Claims>(
                token,
                &DecodingKey::from_secret(jwt_secret.as_ref()),
                &Validation::default(),
            ).ok().map(|decoded| decoded.claims.user_id)
        });

    let resp = ws::start(
        WatchPartyWebSocket {
            video_id,
            user_id,
            state: state.get_ref().clone(),
            tx,
        },
        &req,
        stream,
    )?;

    tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            info!("Sending message to WatchParty WebSocket client for video_id {}: {}", video_id, msg);
        }
    });

    Ok(resp)
}

pub fn configure_ws_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(websocket_comments)
       .service(websocket_watchparty);
}
