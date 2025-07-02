import React, { useState, useRef, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import CommentSection from './CommentSection';
import Navbar from './Navbar';

const VideoPlayer: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [video, setVideo] = useState<any>(null);
  const [videoUrl, setVideoUrl] = useState<string>('');
  const [isWatchParty, setIsWatchParty] = useState(false);
  const [ws, setWs] = useState<WebSocket | null>(null);

  const videoRef = useRef<HTMLVideoElement>(null);
  const [currentTime, setCurrentTime] = useState(0);

  useEffect(() => {
    const fetchVideo = async () => {
      try {
        const response = await fetch(`http://localhost:5050/api/videos/${id}`, {
          credentials: 'include'
        });
        const data = await response.json();
        setVideo(data);
        
        setVideoUrl(`http://localhost:5050/api/videos/${id}/stream`);
      } catch (error) {
        console.error('Error fetching video:', error);
      }
    };
    fetchVideo();
  }, [id]);

  useEffect(() => {
    if (videoUrl && videoRef.current) {
      videoRef.current.load(); // Reload the video element when the URL changes
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
        const response = await fetch(`http://localhost:5050/api/watchparty/${id}/join`, {
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
      const websocket = new WebSocket(`ws://localhost:8080/api/ws/watchparty/${id}`);
      websocket.onopen = () => {
        console.log('Watch Party WebSocket connected');
      };
      websocket.onmessage = (event) => {
        const message = JSON.parse(event.data);
        if (message.type_field === 'watchPartyControl') {
          const videoElement = videoRef.current;
          if (videoElement) {
            if (message.action === 'play') {
              videoElement.play();
            } else if (message.action === 'pause') {
              videoElement.pause();
            } else if (message.action === 'seek' && message.time !== undefined) {
              videoElement.currentTime = message.time;
            }
          }
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
  }, [isWatchParty, id]);

  useEffect(() => {
    const videoElement = videoRef.current;
    if (!videoElement) return;

    const updateTime = () => {
      setCurrentTime(videoElement.currentTime);
    };

    const handlePlay = () => {
      if (isWatchParty && ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          action: 'play',
          time: videoElement.currentTime
        }));
      }
    };

    const handlePause = () => {
      if (isWatchParty && ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          action: 'pause',
          time: videoElement.currentTime
        }));
      }
    };

    const handleSeeked = () => {
      if (isWatchParty && ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          action: 'seek',
          time: videoElement.currentTime
        }));
      }
    };

    videoElement.addEventListener('timeupdate', updateTime);
    videoElement.addEventListener('play', handlePlay);
    videoElement.addEventListener('pause', handlePause);
    videoElement.addEventListener('seeked', handleSeeked);

    return () => {
      videoElement.removeEventListener('timeupdate', updateTime);
      videoElement.removeEventListener('play', handlePlay);
      videoElement.removeEventListener('pause', handlePause);
      videoElement.removeEventListener('seeked', handleSeeked);
    };
  }, [isWatchParty, ws, id]);

  return (
    <div className="bg-gray-100 min-h-screen">
      <Navbar onWatchPartyToggle={() => setIsWatchParty(!isWatchParty)} isWatchParty={isWatchParty} />
      <main className="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col lg:flex-row gap-4">
          <div className="flex-1">
            <div className="bg-white rounded-lg shadow-md overflow-hidden">
              <div className="aspect-w-16 aspect-h-9">
                <video ref={videoRef} controls className="w-full h-full object-contain">
                  <source src={videoUrl} type="video/webm" />
                  <source src={videoUrl} type="video/mp4" />
                  Your browser does not support the video tag.
                </video>
              </div>
              <div className="p-4">
                <h2 className="text-2xl font-bold text-gray-900">{video ? video.title : 'Loading...'}</h2>
                <p className="mt-2 text-gray-600">{video ? video.description : 'Loading description...'}</p>
                <p className="text-gray-500 text-xs mt-1">Views: {video ? video.view_count : 0}</p>
                <div className="mt-2 flex flex-wrap gap-1">
                  {video && video.tags && video.tags.map((tag: string) => (
                    <button
                      key={tag}
                      onClick={() => navigate(`/tag/${tag}`)}
                      className="text-xs bg-indigo-100 text-indigo-800 px-2 py-1 rounded"
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
