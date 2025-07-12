use actix_web::{web, Responder, post, get};
use serde_json::json;
use tokio::sync::Mutex;
use std::sync::Arc;
use log::{info, error};
use jsonwebtoken::{decode, DecodingKey, Validation};
use std::env;

use crate::websocket::broadcast_comment;
use crate::models::{RegisterRequest, LoginRequest, CommentRequest, Comment, Video, User, Claims};
use crate::AppState;

#[post("/api/auth/register")]
async fn register(
    req: web::Json<RegisterRequest>,
    state: web::Data<Arc<Mutex<AppState>>>,
) -> impl Responder {
    let state = state.lock().await;
    let hashed_password = bcrypt::hash(&req.password, bcrypt::DEFAULT_COST).unwrap();
    let result = sqlx::query_as::<_, User>(
        "INSERT INTO users (username, email, password, created_at) VALUES ($1, $2, $3, $4) RETURNING id, username, email, password, created_at"
    )
    .bind(&req.username)
    .bind(&req.email)
    .bind(&hashed_password)
    .bind(chrono::Utc::now().naive_utc())
    .fetch_one(&state.db_pool)
    .await;

    match result {
        Ok(user) => {
            let claims = Claims {
                user_id: user.id,
                exp: (chrono::Utc::now().naive_utc() + chrono::Duration::hours(24)).and_utc().timestamp() as usize,
            };
            let token = jsonwebtoken::encode(
                &jsonwebtoken::Header::default(),
                &claims,
                &jsonwebtoken::EncodingKey::from_secret(
                    env::var("JWT_SECRET")
                        .unwrap_or_else(|_| "secure_jwt_secret_key_12345".to_string())
                        .as_ref(),
                ),
            )
            .unwrap();
            web::Json(json!({
                "message": "User registered successfully",
                "user": {
                    "id": user.id,
                    "username": user.username,
                    "email": user.email
                },
                "token": token
            }))
        }
        Err(e) => {
            error!("Error registering user: {:?}", e);
            web::Json(json!({
                "error": "Internal server error"
            }))
        }
    }
}

#[post("/api/auth/login")]
async fn login(
    req: web::Json<LoginRequest>,
    state: web::Data<Arc<Mutex<AppState>>>,
) -> impl Responder {
    let state = state.lock().await;
    let result = sqlx::query_as::<_, User>(
        "SELECT * FROM users WHERE email = $1"
    )
    .bind(&req.username)
    .fetch_one(&state.db_pool)
    .await;

    match result {
        Ok(user) => {
            if bcrypt::verify(&req.password, &user.password).unwrap() {
                let claims = Claims {
                    user_id: user.id,
                    exp: (chrono::Utc::now().naive_utc() + chrono::Duration::hours(24)).and_utc().timestamp() as usize,
                };
                let token = jsonwebtoken::encode(
                    &jsonwebtoken::Header::default(),
                    &claims,
                    &jsonwebtoken::EncodingKey::from_secret(
                        env::var("JWT_SECRET")
                            .unwrap_or_else(|_| "secure_jwt_secret_key_12345".to_string())
                            .as_ref(),
                    ),
                )
                .unwrap();
                web::Json(json!({
                    "message": "Login successful",
                    "user": {
                        "id": user.id,
                        "username": user.username,
                        "email": user.email
                    },
                    "token": token
                }))
            } else {
                web::Json(json!({
                    "error": "Invalid credentials"
                }))
            }
        }
        Err(_) => web::Json(json!({
            "error": "Invalid credentials"
        })),
    }
}

#[post("/api/auth/logout")]
async fn logout() -> impl Responder {
    web::Json(json!({
        "message": "Logout successful"
    }))
}

#[get("/api/auth/status")]
async fn auth_status() -> impl Responder {
    web::Json(json!({
        "isAuthenticated": false
    }))
}

#[get("/api/status")]
async fn status() -> impl Responder {
    web::Json(json!({
        "status": "running"
    }))
}

#[get("/api/videos")]
async fn get_videos(state: web::Data<Arc<Mutex<AppState>>>) -> actix_web::HttpResponse {
    let state = state.lock().await;
    let result = sqlx::query_as::<_, Video>("SELECT * FROM videos ORDER BY upload_date DESC")
        .fetch_all(&state.db_pool)
        .await;

    match result {
        Ok(videos) => actix_web::HttpResponse::Ok().json(videos),
        Err(e) => {
            error!("Error fetching videos: {:?}", e);
            actix_web::HttpResponse::InternalServerError().json(json!({
                "error": "Internal server error"
            }))
        }
    }
}

#[get("/api/videos/{id}")]
async fn get_video(
    path: web::Path<i32>,
    state: web::Data<Arc<Mutex<AppState>>>,
) -> actix_web::HttpResponse {
    let state = state.lock().await;
    let video_id = path.into_inner();
    let update_result = sqlx::query("UPDATE videos SET view_count = view_count + 1 WHERE id = $1")
        .bind(video_id)
        .execute(&state.db_pool)
        .await;

    if let Err(e) = update_result {
        error!("Error updating view count: {:?}", e);
        return actix_web::HttpResponse::InternalServerError().json(json!({
            "error": "Internal server error"
        }));
    }

    let result = sqlx::query_as::<_, Video>("SELECT * FROM videos WHERE id = $1")
        .bind(video_id)
        .fetch_one(&state.db_pool)
        .await;

    match result {
        Ok(video) => actix_web::HttpResponse::Ok().json(video),
        Err(e) => {
            error!("Error fetching video: {:?}", e);
            actix_web::HttpResponse::NotFound().json(json!({
                "error": "Video not found"
            }))
        }
    }
}

#[get("/api/videos/tag/{tag}")]
async fn get_videos_by_tag(
    path: web::Path<String>,
    state: web::Data<Arc<Mutex<AppState>>>,
) -> actix_web::HttpResponse {
    let state = state.lock().await;
    let tag = path.into_inner();
    let result = sqlx::query_as::<_, Video>("SELECT * FROM videos WHERE $1 = ANY(tags)")
        .bind(&tag)
        .fetch_all(&state.db_pool)
        .await;

    match result {
        Ok(videos) => actix_web::HttpResponse::Ok().json(videos),
        Err(e) => {
            error!("Error fetching videos by tag: {:?}", e);
            actix_web::HttpResponse::InternalServerError().json(json!({
                "error": "Internal server error"
            }))
        }
    }
}

#[get("/api/videos/{id}/stream")]
async fn stream_video(
    path: web::Path<i32>,
    state: web::Data<Arc<Mutex<AppState>>>,
) -> impl Responder {
    let state = state.lock().await;
    let video_id = path.into_inner();
    let video_result = sqlx::query_as::<_, Video>("SELECT * FROM videos WHERE id = $1")
        .bind(video_id)
        .fetch_one(&state.db_pool)
        .await;

    match video_result {
        Ok(video) => {
            let s3_key = video.s3_key;
            
            let bucket_name = env::var("MINIO_BUCKET").unwrap_or_else(|_| "videos".to_string());
            let get_object_output = state.s3_client.get_object()
                .bucket(bucket_name)
                .key(s3_key)
                .send()
                .await;

            match get_object_output {
                Ok(output) => {
                    let body = output.body.collect().await.unwrap().into_bytes();
                    actix_web::HttpResponse::Ok()
                        .content_type("video/webm")
                        .append_header((actix_web::http::header::ACCEPT_RANGES, "bytes"))
                        .body(body)
                }
                Err(e) => {
                    error!("Error streaming video from MinIO: {:?}", e);
                    actix_web::HttpResponse::InternalServerError().json(json!({
                        "error": "Internal server error"
                    }))
                }
            }
        }
        Err(e) => {
            error!("Error fetching video stream: {:?}", e);
            actix_web::HttpResponse::NotFound().json(json!({
                "error": "Video not found"
            }))
        }
    }
}

#[post("/api/comments/{video_id}")]
async fn post_comment(
    path: web::Path<i32>,
    json_req: web::Json<CommentRequest>,
    state: web::Data<Arc<Mutex<AppState>>>,
    http_req: actix_web::HttpRequest,
) -> actix_web::HttpResponse {
    let state = state.lock().await;
    let video_id = path.into_inner();

    // Extract the JWT token from the Authorization header
    let auth_header = http_req.headers().get(actix_web::http::header::AUTHORIZATION);
    let token = auth_header.and_then(|h| h.to_str().ok()).and_then(|h| h.strip_prefix("Bearer ")).map(String::from);

    let jwt_secret = env::var("JWT_SECRET").unwrap_or_else(|_| "secure_jwt_secret_key_12345".to_string());
    let claims_result = token.and_then(|t| {
        decode::<Claims>(
            &t,
            &DecodingKey::from_secret(jwt_secret.as_ref()),
            &Validation::default(),
        ).ok()
    });

    let claims = match claims_result {
        Some(decoded) => decoded.claims,
        None => {
            return actix_web::HttpResponse::Forbidden().json(json!({
                "error": "Unauthorized: Invalid or missing token"
            }));
        }
    };

    let user_id = claims.user_id;

    // Log the incoming request for debugging
    info!("Received comment request for video_id: {}, user_id: {}, text: {}, video_time: {}", video_id, user_id, json_req.text, json_req.video_time);

    let result = sqlx::query_as::<_, Comment>(
        "INSERT INTO comments (video_id, user_id, content, video_time, created_at) VALUES ($1, $2, $3, $4, $5) RETURNING *"
    )
    .bind(video_id)
    .bind(user_id)
    .bind(&json_req.text)
    .bind(json_req.video_time)
    .bind(chrono::Utc::now().naive_utc())
    .fetch_one(&state.db_pool)
    .await;

    match result {
        Ok(comment) => {
            // Clone necessary data for the background task
            let comment_clone = comment.clone();
            
            // Get the video_clients_clone directly from the state we already have locked
            let video_clients_clone = state.video_clients.lock().unwrap().clone();
            
            broadcast_comment(video_id, comment_clone, video_clients_clone);
            
            // Return the response immediately without waiting for broadcast
            actix_web::HttpResponse::Ok().json(comment)
        }
        Err(e) => {
            error!("Error posting comment: {:?}", e);
            actix_web::HttpResponse::InternalServerError().json(json!({
                "error": "Internal server error"
            }))
        }
    }
}

#[get("/api/comments/{video_id}")]
async fn get_comments(
    path: web::Path<i32>,
    state: web::Data<Arc<Mutex<AppState>>>,
) -> actix_web::HttpResponse {
    let state = state.lock().await;
    let video_id = path.into_inner();
    let result = sqlx::query_as::<_, Comment>("SELECT * FROM comments WHERE video_id = $1 ORDER BY video_time ASC")
        .bind(video_id)
        .fetch_all(&state.db_pool)
        .await;

    match result {
        Ok(comments) => actix_web::HttpResponse::Ok().json(comments),
        Err(e) => {
            error!("Error fetching comments: {:?}", e);
            actix_web::HttpResponse::InternalServerError().json(json!({
                "error": "Internal server error"
            }))
        }
    }
}

#[post("/api/watchparty/{video_id}/join")]
async fn join_watch_party(
    path: web::Path<i32>,
    _state: web::Data<Arc<Mutex<AppState>>>,
    http_req: actix_web::HttpRequest,
) -> actix_web::HttpResponse {
    let video_id = path.into_inner();

    // Extract the JWT token from the Authorization header
    let auth_header = http_req.headers().get(actix_web::http::header::AUTHORIZATION);
    let token = auth_header.and_then(|h| h.to_str().ok()).and_then(|h| h.strip_prefix("Bearer ")).map(|t| t.to_owned());

    let jwt_secret = env::var("JWT_SECRET").unwrap_or_else(|_| "secure_jwt_secret_key_12345".to_string());
    let claims_result = token.and_then(|t| {
        decode::<Claims>(
            &t,
            &DecodingKey::from_secret(jwt_secret.as_ref()),
            &Validation::default(),
        ).ok()
    });

    let claims = match claims_result {
        Some(decoded) => decoded.claims,
        None => {
            return actix_web::HttpResponse::Forbidden().json(json!({
                "error": "Unauthorized: Invalid or missing token"
            }));
        }
    };

    let user_id = claims.user_id;

    actix_web::HttpResponse::Ok().json(json!({
        "message": "Joined watch party",
        "videoId": video_id,
        "userId": user_id
    }))
}

#[post("/api/watchparty/{video_id}/control")]
async fn control_watch_party(
    _path: web::Path<i32>,
    req: web::Json<serde_json::Value>,
    _state: web::Data<Arc<Mutex<AppState>>>,
    _auth: web::Data<Arc<Mutex<Claims>>>,
) -> actix_web::HttpResponse {
    // let claims = auth.lock().await;
    // let video_id = path.into_inner();
    // let user_id = claims.user_id;
    let action = req.get("action").and_then(|v| v.as_str()).unwrap_or("");
    let time = req.get("time").and_then(|v| v.as_f64()).unwrap_or(0.0);

    // Broadcast control message to all connected clients for this video
    // This would require WebSocket implementation
    actix_web::HttpResponse::Ok().json(json!({
        "message": "Control message sent",
        "action": action,
        "time": time
    }))
}

#[get("/api/thumbnails/{thumbnail_key}")]
async fn get_thumbnail(
    path: web::Path<String>,
    state: web::Data<Arc<Mutex<AppState>>>,
) -> impl Responder {
    let state = state.lock().await;
    let thumbnail_key = path.into_inner();
    
    // Prepend "thumbnails/" if it's not already there
    let s3_key = if thumbnail_key.starts_with("thumbnails/") {
        thumbnail_key
    } else {
        format!("thumbnails/{}", thumbnail_key)
    };
    
    let bucket_name = env::var("MINIO_BUCKET").unwrap_or_else(|_| "videos".to_string());
    let get_object_output = state.s3_client.get_object()
        .bucket(bucket_name)
        .key(s3_key)
        .send()
        .await;

    match get_object_output {
        Ok(output) => {
            let body = output.body.collect().await.unwrap().into_bytes();
            actix_web::HttpResponse::Ok()
                .content_type("image/jpeg")
                .body(body)
        }
        Err(e) => {
            error!("Error fetching thumbnail from MinIO: {:?}", e);
            actix_web::HttpResponse::NotFound().json(json!({
                "error": "Thumbnail not found"
            }))
        }
    }
}

pub fn configure_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(register)
       .service(login)
       .service(logout)
       .service(auth_status)
       .service(status)
       .service(get_videos)
       .service(get_video)
       .service(get_videos_by_tag)
       .service(stream_video)
       .service(post_comment)
       .service(get_comments)
       .service(join_watch_party)
       .service(control_watch_party)
       .service(get_thumbnail);
}
