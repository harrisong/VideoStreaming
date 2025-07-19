import React, { useState, useEffect } from 'react';
import EmojiPicker from 'emoji-picker-react';
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
      const message = JSON.parse(event.data);
      if (message.type === 'newComment') {
        setComments(prev => [...prev, message.comment]);
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

  const onEmojiClick = (emojiObject: any) => {
    setNewComment(prev => prev + emojiObject.emoji);
    setShowEmojiPicker(false);
  };

  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  };

  const [isCollapsed, setIsCollapsed] = useState(false);

  return (
    <div className="flex flex-col gap-4">
      <div className="comment-section-themed rounded-lg shadow-md p-3">
        <div className="flex justify-between items-center mb-2">
          <h3 className="text-lg font-semibold theme-text">Live Comments</h3>
          <button 
            onClick={() => setIsCollapsed(!isCollapsed)}
            className="p-1 rounded-md hover:opacity-80 focus:outline-none"
            style={{
              backgroundColor: 'var(--theme-accent)',
              color: 'var(--theme-text)'
            }}
          >
            {isCollapsed ? '▶' : '▼'}
          </button>
        </div>
        {!isCollapsed && (
          <div className="border rounded-md overflow-y-auto h-96 p-2" style={{
            backgroundColor: 'var(--theme-background)',
            borderColor: 'var(--theme-text-secondary)'
          }}>
            {visibleComments.map(comment => (
              <div key={comment.id} className="comment-themed mb-2 p-2 border-b">
                <div className="flex justify-between items-center mb-1">
                  <span className="font-semibold text-sm theme-text">User {comment.user_id}</span>
                  <span className="text-xs theme-text-secondary">{formatTime(comment.video_time)}</span>
                </div>
                <p className="theme-text text-sm">{comment.content}</p>
              </div>
            ))}
          </div>
        )}
      </div>
      <div className="flex-1">
        <h3 className="text-lg font-semibold mb-2 theme-text">Comments</h3>
        <form onSubmit={handleCommentSubmit} className="mb-4">
          <div className="flex items-start gap-2">
            <textarea
              value={newComment}
              onChange={(e) => setNewComment(e.target.value)}
              placeholder="Add a comment..."
              className="flex-1 p-2 border rounded-md focus:outline-none focus:ring-2"
              style={{
                backgroundColor: 'var(--theme-surface)',
                color: 'var(--theme-text)',
                borderColor: 'var(--theme-text-secondary)'
              }}
              rows={3}
            />
            <button
              type="button"
              onClick={() => setShowEmojiPicker(!showEmojiPicker)}
              className="p-2 rounded-md hover:opacity-80"
              style={{
                backgroundColor: 'var(--theme-accent)',
                color: 'var(--theme-text)'
              }}
            >
              😊
            </button>
          </div>
          {showEmojiPicker && (
            <div className="absolute z-10 mt-2">
              <EmojiPicker onEmojiClick={onEmojiClick} />
            </div>
          )}
          <button
            type="submit"
            className="mt-2 px-4 py-2 text-white rounded-md hover:opacity-90 focus:outline-none focus:ring-2"
            style={{
              backgroundColor: 'var(--theme-primary)'
            }}
          >
            Post Comment
          </button>
        </form>
      </div>
    </div>
  );
};

export default CommentSection;
