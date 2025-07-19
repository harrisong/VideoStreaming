import React, { useState, useRef, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import Plyr from 'plyr-react';
import CommentSection from './CommentSection';
import Navbar from './Navbar';
import { buildApiUrl, buildWebSocketUrl, API_CONFIG } from '../config';

const VideoPlayer: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [video, setVideo] = useState<any>(null);
  const [videoUrl, setVideoUrl] = useState<string>('');
  const [isWatchParty, setIsWatchParty] = useState(false);
  const [ws, setWs] = useState<WebSocket | null>(null);
  const [currentUserId, setCurrentUserId] = useState<number | null>(null);
  
  // Extract user ID from JWT token
  useEffect(() => {
    const token = localStorage.getItem('token');
    if (token) {
      try {
        // JWT tokens are in the format: header.payload.signature
        const payload = token.split('.')[1];
        // Decode the base64 payload
        const decodedPayload = JSON.parse(atob(payload));
        if (decodedPayload.user_id) {
          setCurrentUserId(decodedPayload.user_id);
        }
      } catch (error) {
        console.error('Error extracting user ID from token:', error);
      }
    }
  }, []);

  const plyrRef = useRef<any>(null);
  const [currentTime, setCurrentTime] = useState(0);

  useEffect(() => {
    const fetchVideo = async () => {
      try {
        const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEO_BY_ID, id!), {
          credentials: 'include'
        });
        const data = await response.json();
        setVideo(data);
        
        setVideoUrl(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEO_STREAM, id!, 'stream'));
      } catch (error) {
        console.error('Error fetching video:', error);
      }
    };
    fetchVideo();
  }, [id]);

  useEffect(() => {
    if (videoUrl && plyrRef.current && plyrRef.current.plyr) {
      plyrRef.current.plyr.source = {
        type: 'video',
        sources: [
          {
            src: videoUrl,
            type: 'video/mp4',
          }
        ]
      };
    }
  }, [videoUrl]);

  useEffect(() => {
    if (isWatchParty) {
      // Join watch party
      const joinWatchParty = async () => {
      try {
        const token = localStorage.getItem('token');
        if (!token) {
          console.error('No token found, user not logged in');
          setIsWatchParty(false);
          alert('Failed to join watch party. Please ensure you are logged in.');
          return;
        }
        const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.WATCHPARTY_JOIN, id!, 'join'), {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
        });
        if (!response.ok) {
          console.error('Failed to join watch party:', await response.text());
          setIsWatchParty(false);
          alert('Failed to join watch party. Please ensure you are logged in.');
        }
      } catch (error) {
        console.error('Error joining watch party:', error);
        setIsWatchParty(false);
        alert('Error joining watch party. Please ensure you are logged in.');
      }
      };
      joinWatchParty();

      // Setup WebSocket for watch party synchronization
      const token = localStorage.getItem('token');
      // Include the token in the URL as a query parameter
      const websocket = new WebSocket(buildWebSocketUrl(API_CONFIG.ENDPOINTS.WS_WATCHPARTY, id!));
      
      websocket.onopen = () => {
        console.log('Watch Party WebSocket connected');
        // Send the token as the first message for authentication
        if (token) {
          websocket.send(JSON.stringify({
            type: 'auth',
            token: token
          }));
        }
      };
      websocket.onmessage = (event) => {
        console.log('Received WebSocket message:', event.data);
        try {
          const message = JSON.parse(event.data);
          console.log('Parsed message:', message);
          
          if (message.type_field === 'watchPartyControl') {
            console.log('Received watchPartyControl message:', message);
            
            // Check if this message is from the current user
            if (message.source_id && currentUserId) {
              // Parse the user_id from the source_id (format: "user_{user_id}_time_{timestamp}")
              const sourceIdParts = message.source_id.split('_');
              if (sourceIdParts.length >= 2) {
                const sourceUserId = parseInt(sourceIdParts[1]);
                
                // If the message is from the current user, drop it to avoid infinite loops
                if (sourceUserId === currentUserId) {
                  console.log('Dropping message from current user to avoid infinite loops');
                  return;
                }
              }
            }
            
            const player = plyrRef.current?.plyr;
            if (player) {
              if (message.action === 'play') {
                console.log('Playing video at time:', player.currentTime);
                player.play();
              } else if (message.action === 'pause') {
                console.log('Pausing video at time:', player.currentTime);
                player.pause();
              } else if (message.action === 'seek' && message.time !== undefined) {
                console.log('Seeking video to time:', message.time);
                player.currentTime = message.time;
              }
            } else {
              console.error('Plyr player not found');
            }
          } else {
            console.log('Ignoring non-control message:', message);
          }
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      };
      websocket.onerror = (error) => {
        console.error('Watch Party WebSocket error:', error);
      };
      websocket.onclose = () => {
        console.log('Watch Party WebSocket closed');
      };

      setWs(websocket);

      return () => {
        websocket.close();
      };
    }
  }, [isWatchParty, id, currentUserId]);

  // Event handlers for Plyr
  const handleTimeUpdate = () => {
    const player = plyrRef.current?.plyr;
    if (player) {
      setCurrentTime(player.currentTime);
    }
  };

  const handlePlay = () => {
    const player = plyrRef.current?.plyr;
    if (player && isWatchParty && ws && ws.readyState === WebSocket.OPEN) {
      const message = {
        action: 'play',
        time: player.currentTime
      };
      console.log('Sending play message:', message);
      ws.send(JSON.stringify(message));
    }
  };

  const handlePause = () => {
    const player = plyrRef.current?.plyr;
    if (player && isWatchParty && ws && ws.readyState === WebSocket.OPEN) {
      const message = {
        action: 'pause',
        time: player.currentTime
      };
      console.log('Sending pause message:', message);
      ws.send(JSON.stringify(message));
    }
  };

  const handleSeeked = () => {
    const player = plyrRef.current?.plyr;
    if (player && isWatchParty && ws && ws.readyState === WebSocket.OPEN) {
      const message = {
        action: 'seek',
        time: player.currentTime
      };
      console.log('Sending seek message:', message);
      ws.send(JSON.stringify(message));
    }
  };

  return (
    <div className="video-container-themed min-h-screen">
      <Navbar onWatchPartyToggle={() => setIsWatchParty(!isWatchParty)} isWatchParty={isWatchParty} />
      <main className="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col lg:flex-row gap-4">
          <div className="flex-1">
            <div className="video-card-themed rounded-lg shadow-md overflow-hidden">
              <div className="aspect-w-16 aspect-h-9">
                <Plyr
                  ref={plyrRef}
                  source={{
                    type: 'video',
                    sources: [
                      {
                        src: videoUrl,
                        type: 'video/mp4',
                      }
                    ]
                  }}
                  options={{
                    controls: [
                      'play-large',
                      'play',
                      'progress',
                      'current-time',
                      'duration',
                      'mute',
                      'volume',
                      'settings',
                      'fullscreen'
                    ],
                    settings: ['quality', 'speed'],
                    quality: {
                      default: 720,
                      options: [1080, 720, 480, 360]
                    }
                  }}
                  onTimeUpdate={handleTimeUpdate}
                  onPlay={handlePlay}
                  onPause={handlePause}
                  onSeeked={handleSeeked}
                />
              </div>
              <div className="p-4">
                <h2 className="text-2xl font-bold video-title-themed">{video ? video.title : 'Loading...'}</h2>
                <p className="mt-2 video-description-themed">{video ? video.description : 'Loading description...'}</p>
                <p className="video-description-themed text-xs mt-1">Views: {video ? video.view_count : 0}</p>
                <div className="mt-2 flex flex-wrap gap-1">
                  {video && video.tags && video.tags.map((tag: string) => (
                    <button
                      key={tag}
                      onClick={() => navigate(`/tag/${tag}`)}
                      className="text-xs tag-themed px-2 py-1 rounded"
                    >
                      {tag}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          </div>
          <div className="lg:w-1/3">
            <CommentSection videoId={parseInt(id || '0')} currentTime={currentTime} />
          </div>
        </div>
      </main>
    </div>
  );
};

export default VideoPlayer;
