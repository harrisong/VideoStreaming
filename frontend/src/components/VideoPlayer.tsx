import React, { useState, useRef, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Container,
  Box,
  Typography,
  Chip,
  Paper,
  IconButton,
  Slider,
  Stack,
  List,
  ListItem,
  ListItemText,
  ListItemAvatar,
  Avatar,
  Divider,
  Button,
  Tooltip,
} from '@mui/material';
import {
  PlayArrow as PlayIcon,
  Pause as PauseIcon,
  VolumeUp as VolumeUpIcon,
  VolumeOff as VolumeOffIcon,
  Fullscreen as FullscreenIcon,
  FullscreenExit as FullscreenExitIcon,
  Settings as SettingsIcon,
  AspectRatio as AspectRatioIcon,
  SkipNext as SkipNextIcon,
  SkipPrevious as SkipPreviousIcon,
  PlaylistPlay as PlaylistPlayIcon,
  Shuffle as ShuffleIcon,
  Repeat as RepeatIcon,
} from '@mui/icons-material';
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
  
  // Video player state
  const videoRef = useRef<HTMLVideoElement>(null);
  const previewVideoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const progressBarRef = useRef<HTMLDivElement>(null);
  
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(1);
  const [isMuted, setIsMuted] = useState(false);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [showControls, setShowControls] = useState(true);
  const [controlsTimeout, setControlsTimeout] = useState<NodeJS.Timeout | null>(null);
  
  // Preview state
  const [showPreview, setShowPreview] = useState(false);
  const [previewTime, setPreviewTime] = useState(0);
  const [previewPosition, setPreviewPosition] = useState({ x: 0, y: 0 });

  // Playlist state
  const [playlist, setPlaylist] = useState<any[]>([]);
  const [currentVideoIndex, setCurrentVideoIndex] = useState(0);
  const [suggestedVideos, setSuggestedVideos] = useState<any[]>([]);
  const [autoplay, setAutoplay] = useState(true);
  const [shuffle, setShuffle] = useState(false);
  const [repeat, setRepeat] = useState(false);
  const [showPlaylist, setShowPlaylist] = useState(false);

  // Extract user ID from JWT token
  useEffect(() => {
    const token = localStorage.getItem('token');
    if (token) {
      try {
        const payload = token.split('.')[1];
        const decodedPayload = JSON.parse(atob(payload));
        if (decodedPayload.user_id) {
          setCurrentUserId(decodedPayload.user_id);
        }
      } catch (error) {
        console.error('Error extracting user ID from token:', error);
      }
    }
  }, []);

  // Fetch video data and suggested videos
  useEffect(() => {
    const fetchVideo = async () => {
      try {
        const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEO_BY_ID, id!), {
          credentials: 'include'
        });
        const data = await response.json();
        setVideo(data);
        setVideoUrl(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEO_STREAM, id!, 'stream'));
        
        // If no playlist, add current video and fetch suggested videos
        if (playlist.length === 0) {
          setPlaylist([data]);
          setCurrentVideoIndex(0);
          fetchSuggestedVideos(data);
        }
      } catch (error) {
        console.error('Error fetching video:', error);
      }
    };
    fetchVideo();
  }, [id]);

  // Fetch suggested videos
  const fetchSuggestedVideos = async (currentVideo: any) => {
    try {
      // Fetch videos from the same category or with similar tags
      const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEOS), {
        credentials: 'include'
      });
      const allVideos = await response.json();
      
      // Filter out current video and get suggested ones
      const suggested = allVideos
        .filter((v: any) => v.id !== currentVideo.id)
        .slice(0, 10); // Get top 10 suggested videos
      
      setSuggestedVideos(suggested);
      
      // Auto-queue suggested videos if no playlist
      if (playlist.length <= 1) {
        setPlaylist([currentVideo, ...suggested.slice(0, 5)]);
      }
    } catch (error) {
      console.error('Error fetching suggested videos:', error);
    }
  };

  // Video event handlers
  const handlePlay = () => {
    if (videoRef.current) {
      videoRef.current.play();
      setIsPlaying(true);
      
      if (isWatchParty && ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          action: 'play',
          time: videoRef.current.currentTime
        }));
      }
    }
  };

  const handlePause = () => {
    if (videoRef.current) {
      videoRef.current.pause();
      setIsPlaying(false);
      
      if (isWatchParty && ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          action: 'pause',
          time: videoRef.current.currentTime
        }));
      }
    }
  };

  const handleTimeUpdate = () => {
    if (videoRef.current) {
      setCurrentTime(videoRef.current.currentTime);
    }
  };

  const handleLoadedMetadata = () => {
    if (videoRef.current) {
      setDuration(videoRef.current.duration);
    }
  };

  const handleSeek = (newTime: number) => {
    if (videoRef.current) {
      videoRef.current.currentTime = newTime;
      setCurrentTime(newTime);
      
      if (isWatchParty && ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          action: 'seek',
          time: newTime
        }));
      }
    }
  };

  const handleVolumeChange = (newVolume: number) => {
    if (videoRef.current) {
      videoRef.current.volume = newVolume;
      setVolume(newVolume);
      setIsMuted(newVolume === 0);
    }
  };

  const toggleMute = () => {
    if (videoRef.current) {
      if (isMuted) {
        videoRef.current.volume = volume;
        setIsMuted(false);
      } else {
        videoRef.current.volume = 0;
        setIsMuted(true);
      }
    }
  };

  const toggleFullscreen = () => {
    if (!document.fullscreenElement) {
      videoRef.current?.requestFullscreen();
      setIsFullscreen(true);
    } else {
      document.exitFullscreen();
      setIsFullscreen(false);
    }
  };

  // Timeline preview handlers
  const handleProgressMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
    if (progressBarRef.current && duration > 0) {
      const rect = progressBarRef.current.getBoundingClientRect();
      const percent = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
      const hoverTime = percent * duration;
      
      setPreviewTime(hoverTime);
      setPreviewPosition({
        x: e.clientX,
        y: rect.top
      });
      setShowPreview(true);
      
      // Update preview video
      if (previewVideoRef.current && Math.abs(previewVideoRef.current.currentTime - hoverTime) > 0.5) {
        previewVideoRef.current.currentTime = hoverTime;
        
        // Update canvas when video seeks
        const updateCanvas = () => {
          if (previewVideoRef.current && canvasRef.current) {
            const canvas = canvasRef.current;
            const ctx = canvas.getContext('2d');
            if (ctx && previewVideoRef.current.readyState >= 2) {
              ctx.clearRect(0, 0, 160, 90);
              ctx.drawImage(previewVideoRef.current, 0, 0, 160, 90);
            }
          }
        };
        
        previewVideoRef.current.addEventListener('seeked', updateCanvas, { once: true });
        setTimeout(updateCanvas, 100); // Fallback
      }
    }
  };

  const handleProgressMouseLeave = () => {
    setShowPreview(false);
  };

  const handleProgressClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (progressBarRef.current && duration > 0) {
      const rect = progressBarRef.current.getBoundingClientRect();
      const percent = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
      const newTime = percent * duration;
      handleSeek(newTime);
    }
  };

  // Controls visibility
  const showControlsTemporarily = () => {
    setShowControls(true);
    if (controlsTimeout) {
      clearTimeout(controlsTimeout);
    }
    const timeout = setTimeout(() => {
      if (isPlaying) {
        setShowControls(false);
      }
    }, 3000);
    setControlsTimeout(timeout);
  };

  // Playlist handlers
  const playNext = () => {
    if (playlist.length === 0) return;
    
    let nextIndex;
    if (shuffle) {
      nextIndex = Math.floor(Math.random() * playlist.length);
    } else {
      nextIndex = currentVideoIndex + 1;
      if (nextIndex >= playlist.length) {
        if (repeat) {
          nextIndex = 0;
        } else {
          return; // End of playlist
        }
      }
    }
    
    setCurrentVideoIndex(nextIndex);
    navigate(`/video/${playlist[nextIndex].id}`);
  };

  const playPrevious = () => {
    if (playlist.length === 0) return;
    
    let prevIndex;
    if (shuffle) {
      prevIndex = Math.floor(Math.random() * playlist.length);
    } else {
      prevIndex = currentVideoIndex - 1;
      if (prevIndex < 0) {
        if (repeat) {
          prevIndex = playlist.length - 1;
        } else {
          return; // Beginning of playlist
        }
      }
    }
    
    setCurrentVideoIndex(prevIndex);
    navigate(`/video/${playlist[prevIndex].id}`);
  };

  const playVideoFromPlaylist = (index: number) => {
    setCurrentVideoIndex(index);
    navigate(`/video/${playlist[index].id}`);
  };

  const addToPlaylist = (video: any) => {
    if (!playlist.find(v => v.id === video.id)) {
      setPlaylist([...playlist, video]);
    }
  };

  const removeFromPlaylist = (index: number) => {
    const newPlaylist = playlist.filter((_, i) => i !== index);
    setPlaylist(newPlaylist);
    
    if (index < currentVideoIndex) {
      setCurrentVideoIndex(currentVideoIndex - 1);
    } else if (index === currentVideoIndex && newPlaylist.length > 0) {
      // If current video is removed, play next or previous
      const newIndex = Math.min(currentVideoIndex, newPlaylist.length - 1);
      setCurrentVideoIndex(newIndex);
      navigate(`/video/${newPlaylist[newIndex].id}`);
    }
  };

  // Auto-play next video when current ends
  const handleVideoEnded = () => {
    if (autoplay && playlist.length > 1) {
      playNext();
    }
  };

  // Format time
  const formatTime = (time: number) => {
    const minutes = Math.floor(time / 60);
    const seconds = Math.floor(time % 60);
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  // Watch party setup (same as before)
  useEffect(() => {
    if (isWatchParty) {
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

      const token = localStorage.getItem('token');
      const websocket = new WebSocket(buildWebSocketUrl(API_CONFIG.ENDPOINTS.WS_WATCHPARTY, id!));
      
      websocket.onopen = () => {
        console.log('Watch Party WebSocket connected');
        if (token) {
          websocket.send(JSON.stringify({
            type: 'auth',
            token: token
          }));
        }
      };

      websocket.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data);
          if (message.type_field === 'watchPartyControl') {
            if (message.source_id && currentUserId) {
              const sourceIdParts = message.source_id.split('_');
              if (sourceIdParts.length >= 2) {
                const sourceUserId = parseInt(sourceIdParts[1]);
                if (sourceUserId === currentUserId) {
                  return;
                }
              }
            }
            
            if (videoRef.current) {
              if (message.action === 'play') {
                videoRef.current.play();
                setIsPlaying(true);
              } else if (message.action === 'pause') {
                videoRef.current.pause();
                setIsPlaying(false);
              } else if (message.action === 'seek' && message.time !== undefined) {
                videoRef.current.currentTime = message.time;
                setCurrentTime(message.time);
              }
            }
          }
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      };

      setWs(websocket);
      return () => websocket.close();
    }
  }, [isWatchParty, id, currentUserId]);

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
              {/* Custom Video Player */}
              <Box 
                sx={{ 
                  aspectRatio: '16/9', 
                  position: 'relative',
                  backgroundColor: '#000',
                  cursor: showControls ? 'default' : 'none',
                }}
                onMouseMove={showControlsTemporarily}
                onMouseLeave={() => setShowControls(false)}
              >
                {/* Main Video */}
                <video
                  ref={videoRef}
                  src={videoUrl}
                  style={{
                    width: '100%',
                    height: '100%',
                    display: 'block',
                  }}
                  onTimeUpdate={handleTimeUpdate}
                  onLoadedMetadata={handleLoadedMetadata}
                  onPlay={() => setIsPlaying(true)}
                  onPause={() => setIsPlaying(false)}
                  onEnded={handleVideoEnded}
                  onClick={() => isPlaying ? handlePause() : handlePlay()}
                />

                {/* Hidden Preview Video */}
                <video
                  ref={previewVideoRef}
                  src={videoUrl}
                  style={{
                    position: 'absolute',
                    top: '-9999px',
                    left: '-9999px',
                    width: '160px',
                    height: '90px',
                    visibility: 'hidden',
                    pointerEvents: 'none'
                  }}
                  muted
                  preload="metadata"
                />

                {/* Video Preview Tooltip */}
                {showPreview && (
                  <Box
                    sx={{
                      position: 'fixed',
                      left: previewPosition.x,
                      top: previewPosition.y - 10,
                      zIndex: 9999,
                      pointerEvents: 'none',
                      transform: 'translateX(-50%) translateY(-100%)',
                    }}
                  >
                    <Paper
                      elevation={8}
                      sx={{
                        p: 1,
                        backgroundColor: 'rgba(0, 0, 0, 0.9)',
                        backdropFilter: 'blur(10px)',
                        border: '1px solid rgba(255, 255, 255, 0.1)',
                        borderRadius: 2,
                      }}
                    >
                      <Box
                        sx={{
                          width: 160,
                          height: 90,
                          borderRadius: 1,
                          overflow: 'hidden',
                          mb: 1,
                          backgroundColor: '#000',
                        }}
                      >
                        <canvas
                          ref={canvasRef}
                          width={160}
                          height={90}
                          style={{
                            width: '100%',
                            height: '100%',
                            display: 'block',
                          }}
                        />
                      </Box>
                      <Typography
                        variant="caption"
                        sx={{
                          color: 'white',
                          textAlign: 'center',
                          display: 'block',
                          fontSize: '0.75rem',
                        }}
                      >
                        {formatTime(previewTime)}
                      </Typography>
                    </Paper>
                  </Box>
                )}

                {/* Video Controls */}
                <Box
                  sx={{
                    position: 'absolute',
                    bottom: 0,
                    left: 0,
                    right: 0,
                    background: 'linear-gradient(transparent, rgba(0,0,0,0.7))',
                    p: 2,
                    opacity: showControls ? 1 : 0,
                    transition: 'opacity 0.3s ease',
                  }}
                >
                  {/* Progress Bar */}
                  <Box
                    ref={progressBarRef}
                    sx={{
                      height: 6,
                      backgroundColor: 'rgba(255,255,255,0.3)',
                      borderRadius: 3,
                      mb: 2,
                      cursor: 'pointer',
                      position: 'relative',
                    }}
                    onMouseMove={handleProgressMouseMove}
                    onMouseLeave={handleProgressMouseLeave}
                    onClick={handleProgressClick}
                  >
                    <Box
                      sx={{
                        height: '100%',
                        backgroundColor: 'primary.main',
                        borderRadius: 3,
                        width: `${duration > 0 ? (currentTime / duration) * 100 : 0}%`,
                      }}
                    />
                  </Box>

                  {/* Control Buttons */}
                  <Stack direction="row" alignItems="center" spacing={1}>
                    <Tooltip title="Previous">
                      <IconButton
                        onClick={playPrevious}
                        sx={{ color: 'white' }}
                        disabled={playlist.length <= 1}
                      >
                        <SkipPreviousIcon />
                      </IconButton>
                    </Tooltip>

                    <IconButton
                      onClick={() => isPlaying ? handlePause() : handlePlay()}
                      sx={{ color: 'white' }}
                    >
                      {isPlaying ? <PauseIcon /> : <PlayIcon />}
                    </IconButton>

                    <Tooltip title="Next">
                      <IconButton
                        onClick={playNext}
                        sx={{ color: 'white' }}
                        disabled={playlist.length <= 1}
                      >
                        <SkipNextIcon />
                      </IconButton>
                    </Tooltip>

                    <Typography variant="body2" sx={{ color: 'white', minWidth: 100 }}>
                      {formatTime(currentTime)} / {formatTime(duration)}
                    </Typography>

                    <Box sx={{ flexGrow: 1 }} />

                    <Tooltip title="Shuffle">
                      <IconButton
                        onClick={() => setShuffle(!shuffle)}
                        sx={{ 
                          color: shuffle ? 'primary.main' : 'white',
                          opacity: shuffle ? 1 : 0.7
                        }}
                      >
                        <ShuffleIcon />
                      </IconButton>
                    </Tooltip>

                    <Tooltip title="Repeat">
                      <IconButton
                        onClick={() => setRepeat(!repeat)}
                        sx={{ 
                          color: repeat ? 'primary.main' : 'white',
                          opacity: repeat ? 1 : 0.7
                        }}
                      >
                        <RepeatIcon />
                      </IconButton>
                    </Tooltip>

                    <Tooltip title="Playlist">
                      <IconButton
                        onClick={() => setShowPlaylist(!showPlaylist)}
                        sx={{ 
                          color: showPlaylist ? 'primary.main' : 'white',
                          opacity: showPlaylist ? 1 : 0.7
                        }}
                      >
                        <PlaylistPlayIcon />
                      </IconButton>
                    </Tooltip>

                    <IconButton
                      onClick={toggleMute}
                      sx={{ color: 'white' }}
                    >
                      {isMuted ? <VolumeOffIcon /> : <VolumeUpIcon />}
                    </IconButton>

                    <Box sx={{ width: 100 }}>
                      <Slider
                        value={isMuted ? 0 : volume}
                        onChange={(_, value) => handleVolumeChange(value as number)}
                        min={0}
                        max={1}
                        step={0.1}
                        size="small"
                        sx={{ color: 'white' }}
                      />
                    </Box>

                    <IconButton
                      onClick={() => setIsFullWidth(!isFullWidth)}
                      sx={{ color: 'white' }}
                    >
                      <AspectRatioIcon />
                    </IconButton>

                    <IconButton
                      onClick={toggleFullscreen}
                      sx={{ color: 'white' }}
                    >
                      {isFullscreen ? <FullscreenExitIcon /> : <FullscreenIcon />}
                    </IconButton>
                  </Stack>
                </Box>
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
          
          {/* Playlist/Comments Section */}
          {!isFullWidth && (
            <Box sx={{ width: { xs: '100%', lg: '400px' }, flexShrink: 0 }}>
              {showPlaylist ? (
                <Paper elevation={0} sx={{ height: 'fit-content' }}>
                  <Box sx={{ p: 2, borderBottom: '1px solid', borderColor: 'divider' }}>
                    <Typography variant="h6" sx={{ fontWeight: 600 }}>
                      Playlist ({playlist.length} videos)
                    </Typography>
                  </Box>
                  <List sx={{ maxHeight: '600px', overflow: 'auto' }}>
                    {playlist.map((video, index) => (
                      <ListItem
                        key={video.id}
                        onClick={() => playVideoFromPlaylist(index)}
                        sx={{
                          backgroundColor: index === currentVideoIndex ? 'action.selected' : 'transparent',
                          cursor: 'pointer',
                          '&:hover': {
                            backgroundColor: 'action.hover',
                          },
                        }}
                      >
                        <ListItemAvatar>
                          <Avatar
                            variant="rounded"
                            sx={{ width: 60, height: 40 }}
                            src={`/api/videos/${video.id}/thumbnail`}
                          >
                            {index + 1}
                          </Avatar>
                        </ListItemAvatar>
                        <ListItemText
                          primary={
                            <Typography
                              variant="body2"
                              sx={{
                                fontWeight: index === currentVideoIndex ? 600 : 400,
                                color: index === currentVideoIndex ? 'primary.main' : 'text.primary',
                              }}
                            >
                              {video.title}
                            </Typography>
                          }
                          secondary={
                            <Typography variant="caption" color="text.secondary">
                              {video.view_count?.toLocaleString() || 0} views
                            </Typography>
                          }
                        />
                        {index !== currentVideoIndex && (
                          <IconButton
                            size="small"
                            onClick={(e) => {
                              e.stopPropagation();
                              removeFromPlaylist(index);
                            }}
                            sx={{ opacity: 0.7 }}
                          >
                            ×
                          </IconButton>
                        )}
                      </ListItem>
                    ))}
                  </List>
                  
                  {/* Add suggested videos section */}
                  {suggestedVideos.length > 0 && (
                    <>
                      <Divider />
                      <Box sx={{ p: 2, borderBottom: '1px solid', borderColor: 'divider' }}>
                        <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>
                          Suggested Videos
                        </Typography>
                      </Box>
                      <List sx={{ maxHeight: '400px', overflow: 'auto' }}>
                        {suggestedVideos.slice(0, 5).map((video) => (
                          <ListItem
                            key={video.id}
                            onClick={() => addToPlaylist(video)}
                            sx={{
                              cursor: 'pointer',
                              '&:hover': {
                                backgroundColor: 'action.hover',
                              },
                            }}
                          >
                            <ListItemAvatar>
                              <Avatar
                                variant="rounded"
                                sx={{ width: 60, height: 40 }}
                                src={`/api/videos/${video.id}/thumbnail`}
                              >
                                +
                              </Avatar>
                            </ListItemAvatar>
                            <ListItemText
                              primary={
                                <Typography variant="body2">
                                  {video.title}
                                </Typography>
                              }
                              secondary={
                                <Typography variant="caption" color="text.secondary">
                                  {video.view_count?.toLocaleString() || 0} views
                                </Typography>
                              }
                            />
                          </ListItem>
                        ))}
                      </List>
                    </>
                  )}
                </Paper>
              ) : (
                <CommentSection videoId={parseInt(id || '0')} currentTime={currentTime} />
              )}
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
