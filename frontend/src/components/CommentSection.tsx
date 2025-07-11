import React, { useState, useEffect } from 'react';
import EmojiPicker from 'emoji-picker-react';

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
        const response = await fetch(`http://localhost:5050/api/comments/${videoId}`, {
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
    const websocket = new WebSocket(`ws://localhost:8080/api/ws/comments/${videoId}`);
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

        const response = await fetch(`http://localhost:5050/api/comments/${videoId}`, {
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
      <div className="bg-white rounded-lg shadow-md p-3">
        <div className="flex justify-between items-center mb-2">
          <h3 className="text-lg font-semibold">Live Comments</h3>
          <button 
            onClick={() => setIsCollapsed(!isCollapsed)}
            className="p-1 bg-gray-200 rounded-md hover:bg-gray-300 focus:outline-none"
          >
            {isCollapsed ? '▶' : '▼'}
          </button>
        </div>
        {!isCollapsed && (
          <div className="border rounded-md overflow-y-auto h-96 p-2 bg-gray-50">
            {visibleComments.map(comment => (
              <div key={comment.id} className="mb-2 p-2 border-b border-gray-200">
                <div className="flex justify-between items-center mb-1">
                  <span className="font-semibold text-sm">User {comment.user_id}</span>
                  <span className="text-xs text-gray-500">{formatTime(comment.video_time)}</span>
                </div>
                <p className="text-gray-800 text-sm">{comment.content}</p>
              </div>
            ))}
          </div>
        )}
      </div>
      <div className="flex-1">
        <h3 className="text-lg font-semibold mb-2">Comments</h3>
        <form onSubmit={handleCommentSubmit} className="mb-4">
          <div className="flex items-start gap-2">
            <textarea
              value={newComment}
              onChange={(e) => setNewComment(e.target.value)}
              placeholder="Add a comment..."
              className="flex-1 p-2 border rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500"
              rows={3}
            />
            <button
              type="button"
              onClick={() => setShowEmojiPicker(!showEmojiPicker)}
              className="p-2 bg-gray-200 rounded-md hover:bg-gray-300"
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
            className="mt-2 px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500"
          >
            Post Comment
          </button>
        </form>
      </div>
    </div>
  );
};

export default CommentSection;
