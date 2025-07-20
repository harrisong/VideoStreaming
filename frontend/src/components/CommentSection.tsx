import React, { useState, useEffect } from 'react';
import EmojiPicker from './EmojiPicker';
import {
  Box,
  Typography,
  TextField,
  Button,
  IconButton,
  Collapse,
} from '@mui/material';
import {
  ExpandMore as ExpandMoreIcon,
  ExpandLess as ExpandLessIcon,
  EmojiEmotions as EmojiEmotionsIcon,
  Send as SendIcon,
} from '@mui/icons-material';
import { buildApiUrl, buildWebSocketUrl, API_CONFIG } from '../config';

interface Comment {
  id: number;
  user_id: number;
  content: string;
  video_time: number;
  created_at: string;
}

interface CommentSectionProps {
  videoId: number;
  currentTime: number;
}

const CommentSection: React.FC<CommentSectionProps> = ({ videoId, currentTime }) => {
  const [comments, setComments] = useState<Comment[]>([]);
  const [visibleComments, setVisibleComments] = useState<Comment[]>([]);
  const [newComment, setNewComment] = useState('');
  const [showEmojiPicker, setShowEmojiPicker] = useState(false);

  useEffect(() => {
    // Fetch comments from backend
    const fetchComments = async () => {
      try {
        const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.COMMENTS, videoId.toString()), {
          credentials: 'include'
        });
        if (response.ok) {
          const data = await response.json();
          setComments(data);
          setVisibleComments([]);
        } else {
          console.error('Failed to fetch comments');
        }
      } catch (error) {
        console.error('Error fetching comments:', error);
      }
    };

    fetchComments();

    // Setup WebSocket for real-time comments
    const websocket = new WebSocket(buildWebSocketUrl(API_CONFIG.ENDPOINTS.WS_COMMENTS, videoId.toString()));
    websocket.onopen = () => {
      console.log('WebSocket connected');
    };
    websocket.onmessage = (event) => {
      try {
        if (event.data) {
          const message = JSON.parse(event.data);
          if (message.type === 'newComment') {
            setComments(prev => [...prev, message.comment]);
          }
        }
      } catch (error) {
        console.error('Error parsing WebSocket message:', error);
      }
    };
    websocket.onerror = (error) => {
      console.error('WebSocket error:', error);
    };
    websocket.onclose = () => {
      console.log('WebSocket closed');
    };

    return () => {
      websocket.close();
    };
  }, [videoId]);

  useEffect(() => {
    // Reset visible comments if currentTime changes significantly (e.g., on seek)
    setVisibleComments(prev => {
      // If currentTime is less than the last visible comment's time by a threshold, assume a seek backward
      if (prev.length > 0 && currentTime < prev[prev.length - 1].video_time - 2) {
        return [];
      }
      return prev;
    });

    const newlyVisible = comments.filter(comment => comment.video_time <= currentTime && !visibleComments.some(vc => vc.id === comment.id));
    if (newlyVisible.length > 0) {
      setVisibleComments(prev => [...prev, ...newlyVisible].sort((a, b) => a.video_time - b.video_time));
    }
  }, [currentTime, comments, visibleComments]);

  const handleCommentSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newComment.trim()) {
      try {
        // Check if token exists in localStorage
        const token = localStorage.getItem('token');
        if (!token) {
          alert('You must be logged in to post a comment. Please log in and try again.');
          return;
        }

        const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.COMMENTS, videoId.toString()), {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
          body: JSON.stringify({
            text: newComment,
            videoTime: Math.floor(currentTime)
          }),
        });

        if (response.ok) {
          const newCommentData = await response.json();
          setComments([...comments, newCommentData]);
          setNewComment('');
        } else if (response.status === 401) {
          alert('You must be logged in to post a comment. Please log in and try again.');
        } else {
          console.error('Failed to post comment');
        }
      } catch (error) {
        console.error('Error posting comment:', error);
      }
    }
  };

  const onEmojiClick = (emoji: string) => {
    setNewComment(prev => prev + emoji);
    setShowEmojiPicker(false);
  };

  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  };

  const [isCollapsed, setIsCollapsed] = useState(true); // Start collapsed by default
  const [showComments, setShowComments] = useState(false);

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
      {/* Live Comments - Subtle and Minimized */}
      <Box sx={{ 
        backgroundColor: 'background.paper', 
        borderRadius: 1, 
        p: 1.5,
        border: '1px solid',
        borderColor: 'divider',
      }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 0.5 }}>
          <Typography 
            variant="caption" 
            sx={{ 
              color: 'text.secondary',
              fontSize: '0.75rem',
              fontWeight: 500,
            }}
          >
            Live Comments ({visibleComments.length})
          </Typography>
          <IconButton 
            onClick={() => setIsCollapsed(!isCollapsed)}
            size="small"
            sx={{ 
              opacity: 0.5,
              '&:hover': { opacity: 0.8 },
              p: 0.25,
            }}
          >
            {isCollapsed ? <ExpandMoreIcon fontSize="small" /> : <ExpandLessIcon fontSize="small" />}
          </IconButton>
        </Box>
        
        <Collapse in={!isCollapsed}>
          <Box sx={{ 
            border: '1px solid',
            borderColor: 'divider',
            borderRadius: 1,
            maxHeight: 120,
            overflow: 'auto',
            p: 0.5,
            backgroundColor: 'background.default',
          }}>
            {visibleComments.slice(-5).map(comment => (
              <Box key={comment.id} sx={{ mb: 0.5, p: 0.5, opacity: 0.8 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <Typography variant="caption" sx={{ fontWeight: 500, fontSize: '0.7rem' }}>
                    User {comment.user_id}
                  </Typography>
                  <Typography variant="caption" sx={{ color: 'text.secondary', fontSize: '0.65rem' }}>
                    {formatTime(comment.video_time)}
                  </Typography>
                </Box>
                <Typography 
                  variant="caption" 
                  sx={{ 
                    fontSize: '0.7rem',
                    display: '-webkit-box',
                    WebkitLineClamp: 2,
                    WebkitBoxOrient: 'vertical',
                    overflow: 'hidden',
                  }}
                >
                  {comment.content}
                </Typography>
              </Box>
            ))}
          </Box>
        </Collapse>
      </Box>

      {/* Comments Toggle */}
      <Button
        onClick={() => setShowComments(!showComments)}
        variant="text"
        size="small"
        endIcon={showComments ? <ExpandLessIcon /> : <ExpandMoreIcon />}
        sx={{ 
          justifyContent: 'flex-start',
          textTransform: 'none',
          color: 'text.primary',
          fontSize: '0.875rem',
          fontWeight: 500,
          p: 1,
        }}
      >
        Comments ({comments.length})
      </Button>

      {/* Comments Section - Collapsible */}
      <Collapse in={showComments}>
        <Box sx={{ mt: 1 }}>
          <Box component="form" onSubmit={handleCommentSubmit} sx={{ mb: 2 }}>
            <Box sx={{ display: 'flex', gap: 1, alignItems: 'flex-start' }}>
              <TextField
                value={newComment}
                onChange={(e) => setNewComment(e.target.value)}
                placeholder="Add a comment..."
                multiline
                rows={2}
                size="small"
                fullWidth
                variant="outlined"
                sx={{ 
                  '& .MuiOutlinedInput-root': {
                    fontSize: '0.875rem',
                  }
                }}
              />
              <IconButton
                onClick={() => setShowEmojiPicker(!showEmojiPicker)}
                size="small"
                color="primary"
                sx={{ mt: 0.5 }}
              >
                <EmojiEmotionsIcon fontSize="small" />
              </IconButton>
              <IconButton
                type="submit"
                size="small"
                color="primary"
                sx={{ 
                  mt: 0.5,
                  '&:hover': { 
                    backgroundColor: 'rgba(0, 0, 0, 0.04)' 
                  }
                }}
              >
                <SendIcon fontSize="small" />
              </IconButton>
            </Box>
            
            {showEmojiPicker && (
              <Box sx={{ position: 'absolute', zIndex: 10, mt: 1 }}>
                <EmojiPicker 
                  onEmojiClick={onEmojiClick}
                  onClose={() => setShowEmojiPicker(false)}
                />
              </Box>
            )}
          </Box>

          {/* All Comments List */}
          <Box sx={{ maxHeight: 300, overflow: 'auto' }}>
            {comments.map(comment => (
              <Box key={comment.id} sx={{ p: 1.5, borderBottom: '1px solid', borderColor: 'divider' }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 0.5 }}>
                  <Typography variant="body2" sx={{ fontWeight: 500 }}>
                    User {comment.user_id}
                  </Typography>
                  <Typography variant="caption" color="text.secondary">
                    {formatTime(comment.video_time)}
                  </Typography>
                </Box>
                <Typography variant="body2" color="text.primary">
                  {comment.content}
                </Typography>
              </Box>
            ))}
          </Box>
        </Box>
      </Collapse>
    </Box>
  );
};

export default CommentSection;
