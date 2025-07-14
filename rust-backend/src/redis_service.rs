use redis::{Client, AsyncCommands, RedisResult};
use std::env;
use log::{info, error};
use serde::{Serialize, Deserialize};
use futures::StreamExt;

// Define a struct for the message that will be published to Redis
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct WatchPartyMessage {
    pub type_field: String,
    pub video_id: i32,
    pub user_id: i32,
    pub action: String,
    pub time: Option<f64>,
    pub source_id: String,
}

// Initialize the Redis client
pub fn init_redis_client() -> RedisResult<Client> {
    let redis_url = env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    info!("Connecting to Redis at {}", redis_url);
    Client::open(redis_url)
}

// Publish a message to a Redis channel
pub async fn publish_message(client: &Client, channel: &str, message: &WatchPartyMessage) -> RedisResult<()> {
    let mut con = client.get_async_connection().await?;
    let message_json = serde_json::to_string(message).unwrap_or_else(|e| {
        error!("Failed to serialize message: {:?}", e);
        "{}".to_string()
    });
    
    info!("Publishing message to channel {}: {}", channel, message_json);
    con.publish::<_, _, ()>(channel, message_json).await?;
    Ok(())
}

// Subscribe to a Redis channel and process messages
pub async fn subscribe_to_channel(client: &Client, channel: String, callback: impl Fn(WatchPartyMessage) + Send + 'static) -> RedisResult<()> {
    let client_clone = client.clone();
    
    // Run the subscription in a separate task
    tokio::spawn(async move {
        let channel_name = channel.clone(); // Clone for logging
        info!("Subscribing to Redis channel: {}", channel_name);
        
        // Create a pubsub connection
        let conn = match client_clone.get_async_connection().await {
            Ok(conn) => conn,
            Err(e) => {
                error!("Failed to get Redis connection: {:?}", e);
                return;
            }
        };
        
        let mut pubsub = conn.into_pubsub();
        
        // Subscribe to the channel
        if let Err(e) = pubsub.subscribe(&channel).await {
            error!("Failed to subscribe to channel {}: {:?}", channel_name, e);
            return;
        }
        
        // Process incoming messages
        let mut msg_stream = pubsub.on_message();
        while let Some(msg) = msg_stream.next().await {
            let payload: String = match msg.get_payload() {
                Ok(payload) => payload,
                Err(e) => {
                    error!("Failed to get message payload: {:?}", e);
                    continue;
                }
            };
            
            // Parse the message
            match serde_json::from_str::<WatchPartyMessage>(&payload) {
                Ok(message) => {
                    info!("Received message on channel {}: {:?}", channel_name, message);
                    callback(message);
                },
                Err(e) => {
                    error!("Failed to parse message: {:?}", e);
                }
            }
        }
    });
    
    Ok(())
}

// Generate a channel name for a video
pub fn get_video_channel(video_id: i32) -> String {
    format!("watchparty:video:{}", video_id)
}
