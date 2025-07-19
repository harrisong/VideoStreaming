use serde::{Deserialize, Serialize};
use chrono::NaiveDateTime;
use sqlx::FromRow;

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct User {
    pub id: i32,
    pub username: String,
    pub email: String,
    pub password: String,
    pub created_at: Option<NaiveDateTime>,
    pub settings: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RegisterRequest {
    pub username: String,
    pub email: String,
    pub password: String,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Video {
    pub id: i32,
    pub title: String,
    pub description: Option<String>,
    pub s3_key: String,
    pub thumbnail_url: Option<String>,
    pub uploaded_by: Option<i32>,
    pub upload_date: Option<NaiveDateTime>,
    pub tags: Option<Vec<String>>,
    pub view_count: Option<i32>,
    pub category_id: Option<i32>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Category {
    pub id: i32,
    pub name: String,
    pub description: Option<String>,
    pub created_at: Option<NaiveDateTime>,
    pub icon_svg: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, FromRow, Clone)]
pub struct Comment {
    pub id: i32,
    pub video_id: i32,
    pub user_id: i32,
    pub content: String,
    pub video_time: i32,
    pub created_at: NaiveDateTime,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CommentRequest {
    pub text: String,
    #[serde(rename = "videoTime")]
    pub video_time: i32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub user_id: i32,
    pub exp: usize,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UserSettingsRequest {
    pub theme: Option<serde_json::Value>,
}
