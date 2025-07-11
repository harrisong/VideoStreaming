import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import Navbar from './Navbar';

interface Video {
  id: string;
  title: string;
  description: string;
  thumbnail_url: string;
  view_count: number;
  tags: string[];
}

const TagVideos = () => {
  const { tag } = useParams<{ tag: string }>();
  const navigate = useNavigate();
  const [videos, setVideos] = useState<Video[]>([]);

  useEffect(() => {
    const fetchVideosByTag = async () => {
      try {
        const response = await fetch(`http://localhost:5050/api/videos/tag/${tag}`, {
          credentials: 'include'
        });
        const data = await response.json();
        setVideos(data);
      } catch (error) {
        console.error('Error fetching videos by tag:', error);
      }
    };
    fetchVideosByTag();
  }, [tag]);

  return (
    <div className="bg-gray-100 min-h-screen">
      <Navbar />
      <main className="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        <h2 className="text-2xl font-bold mb-4">Videos tagged with: {tag}</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
          {videos.map((video: Video) => (
            <div key={video.id} className="bg-white rounded-lg shadow-md overflow-hidden">
              <img 
                src={video.thumbnail_url ? `http://localhost:5050/api/thumbnails/${video.thumbnail_url.split('/').pop()}` : ''} 
                alt={video.title} 
                className="w-full h-48 object-cover" 
              />
              <div className="p-4">
                <h3 className="font-bold text-lg mb-2 text-gray-900">{video.title}</h3>
                <p className="text-gray-700 text-sm">{video.description}</p>
                <p className="text-gray-500 text-xs mt-1">Views: {video.view_count}</p>
                <div className="mt-2 flex flex-wrap gap-1">
                  {video.tags && video.tags.map((tag: string) => (
                    <button
                      key={tag}
                      onClick={() => navigate(`/tag/${tag}`)}
                      className="text-xs bg-indigo-100 text-indigo-800 px-2 py-1 rounded"
                    >
                      {tag}
                    </button>
                  ))}
                </div>
                <button 
                  onClick={() => navigate(`/video/${video.id}`)}
                  className="mt-4 w-full inline-flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                >
                  Watch Now
                </button>
              </div>
            </div>
          ))}
        </div>
      </main>
    </div>
  );
};

export default TagVideos;
