import React, { useState, useRef, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Container,
  Box,
  Typography,
  Chip,
  IconButton,
  Paper,
  Tooltip,
} from '@mui/material';
import {
  Fullscreen as FullscreenIcon,
  FullscreenExit as FullscreenExitIcon,
} from '@mui/icons-material';
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
  const [isFullWidth, setIsFullWidth] = useState(false);
  
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

  // Custom Plyr setup with resize button
  useEffect(() => {
    const timer = setTimeout(() => {
      if (plyrRef.current?.plyr) {
        const player = plyrRef.current.plyr;
        const controls = player.elements?.controls;
        
        if (controls && !controls.querySelector('[data-plyr="resize"]')) {
          // Create custom resize button
          const resizeButton = document.createElement('button');
          resizeButton.className = 'plyr__control';
          resizeButton.type = 'button';
          resizeButton.setAttribute('data-plyr', 'resize');
          resizeButton.innerHTML = `
            <svg width="22" height="22" viewBox="0 0 24 24" role="presentation" focusable="false" style="display: block; margin: auto;">
              <path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z" fill="currentColor"/>
            </svg>
            <span class="plyr__tooltip" role="tooltip">${isFullWidth ? 'Fit to container' : 'Expand to full width'}</span>
          `;
          
          // Add custom styling for better alignment
          resizeButton.style.cssText = `
            display: flex;
            align-items: center;
            justify-content: center;
            width: 48px;
            height: 48px;
            padding: 0;
          `;
          
          // Add pressed class based on current state
          if (isFullWidth) {
            resizeButton.classList.add('plyr__control--pressed');
          }
          
          // Add click handler
          resizeButton.addEventListener('click', () => {
            setIsFullWidth(!isFullWidth);
            resizeButton.classList.toggle('plyr__control--pressed');
          });
          
          // Insert before fullscreen button
          const fullscreenButton = controls.querySelector('[data-plyr="fullscreen"]');
          if (fullscreenButton) {
            controls.insertBefore(resizeButton, fullscreenButton);
          }
        }
      }
    }, 1000); // Wait for Plyr to be fully initialized

    return () => clearTimeout(timer);
  }, [videoUrl, isFullWidth]);

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
    <Box sx={{ minHeight: '100vh', backgroundColor: 'background.default' }}>
      <Navbar onWatchPartyToggle={() => setIsWatchParty(!isWatchParty)} isWatchParty={isWatchParty} />
      
      <Container maxWidth="xl" sx={{ py: 3 }}>
        <Box sx={{ 
          display: 'flex', 
          flexDirection: { xs: 'column', lg: 'row' }, 
          gap: 3 
        }}>
          {/* Video Section */}
          <Box sx={{ flex: 1 }}>
            <Paper 
              elevation={0}
              sx={{ 
                overflow: 'hidden',
                position: 'relative',
              }}
            >
              {/* Video Player */}
              <Box sx={{ aspectRatio: '16/9', position: 'relative' }}>
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
                
              </Box>

              {/* Video Info */}
              <Box sx={{ p: 3 }}>
                <Typography variant="h4" component="h1" gutterBottom sx={{ fontWeight: 700 }}>
                  {video ? video.title : 'Loading...'}
                </Typography>
                
                <Typography variant="body1" color="text.secondary" sx={{ mb: 2, lineHeight: 1.6 }}>
                  {video ? video.description : 'Loading description...'}
                </Typography>
                
                <Typography variant="caption" color="text.secondary" sx={{ mb: 2, display: 'block' }}>
                  Views: {video ? video.view_count.toLocaleString() : 0}
                </Typography>
                
                {/* Tags */}
                {video && video.tags && video.tags.length > 0 && (
                  <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1, mt: 2 }}>
                    {video.tags.map((tag: string) => (
                      <Chip
                        key={tag}
                        label={tag}
                        size="small"
                        variant="outlined"
                        onClick={() => navigate(`/tag/${tag}`)}
                        sx={{ 
                          cursor: 'pointer',
                          '&:hover': {
                            backgroundColor: 'primary.main',
                            color: 'primary.contrastText',
                          },
                        }}
                      />
                    ))}
                  </Box>
                )}
              </Box>
            </Paper>
          </Box>
          
          {/* Comments Section */}
          {!isFullWidth && (
            <Box sx={{ width: { xs: '100%', lg: '400px' }, flexShrink: 0 }}>
              <CommentSection videoId={parseInt(id || '0')} currentTime={currentTime} />
            </Box>
          )}
        </Box>
        
        {/* Comments below video when full width */}
        {isFullWidth && (
          <Box sx={{ mt: 3 }}>
            <CommentSection videoId={parseInt(id || '0')} currentTime={currentTime} />
          </Box>
        )}
      </Container>
    </Box>
  );
};

export default VideoPlayer;
