import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import Navbar from './Navbar';
import { buildApiUrl, API_CONFIG } from '../config';

const Home: React.FC = () => {
  const [videos, setVideos] = useState<any[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const navigate = useNavigate();

  useEffect(() => {
    const fetchVideos = async () => {
      try {
        const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEOS), {
          credentials: 'include'
        });
        const data = await response.json();
        setVideos(data);
      } catch (error) {
        console.error('Error fetching videos:', error);
      }
    };
    fetchVideos();
  }, []);

  const handleSearch = async (query: string) => {
    setIsSearching(true);
    setSearchQuery(query);
    try {
      const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEO_SEARCH, encodeURIComponent(query)), {
        credentials: 'include'
      });
      const data = await response.json();
      setVideos(data);
    } catch (error) {
      console.error('Error searching videos:', error);
    }
  };

  const handleClearSearch = async () => {
    setIsSearching(false);
    setSearchQuery('');
    try {
      const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEOS), {
        credentials: 'include'
      });
      const data = await response.json();
      setVideos(data);
    } catch (error) {
      console.error('Error fetching videos:', error);
    }
  };

  return (
    <div className="video-container-themed min-h-screen">
      <Navbar onSearch={handleSearch} />
      <main className="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        {/* Search Results Header */}
        {isSearching && (
          <div className="mb-6 flex items-center justify-between">
            <h2 className="text-xl font-semibold theme-text">
              Search results for "{searchQuery}" ({videos.length} videos found)
            </h2>
            <button
              onClick={handleClearSearch}
              className="inline-flex items-center px-3 py-2 border shadow-sm text-sm leading-4 font-medium rounded-md hover:opacity-80 focus:outline-none focus:ring-2"
              style={{
                backgroundColor: 'var(--theme-surface)',
                color: 'var(--theme-text)',
                borderColor: 'var(--theme-text-secondary)'
              }}
            >
              Clear Search
            </button>
          </div>
        )}
        
        {/* No Results Message */}
        {isSearching && videos.length === 0 && (
          <div className="text-center py-12">
            <h3 className="text-lg font-medium theme-text mb-2">No videos found</h3>
            <p className="theme-text-secondary">Try searching with different keywords</p>
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
          {videos.map((video) => (
            <div key={video.id} className="video-card-themed rounded-lg shadow-md overflow-hidden">
              <img 
                src={video.thumbnail_url ? buildApiUrl(API_CONFIG.ENDPOINTS.THUMBNAILS, video.thumbnail_url.split('/').pop()) : ''}
                alt={video.title} 
                className="w-full h-48 object-cover" 
              />
              <div className="p-4">
                <h3 className="font-bold text-lg mb-2 video-title-themed">{video.title}</h3>
                <p className="video-description-themed text-sm">{video.description}</p>
                <p className="video-description-themed text-xs mt-1">Views: {video.view_count}</p>
                <div className="mt-2 flex flex-wrap gap-1">
                  {video.tags && video.tags.map((tag: string) => (
                    <button
                      key={tag}
                      onClick={() => navigate(`/tag/${tag}`)}
                      className="text-xs tag-themed px-2 py-1 rounded"
                    >
                      {tag}
                    </button>
                  ))}
                </div>
                <button 
                  onClick={() => navigate(`/video/${video.id}`)}
                  className="mt-4 w-full inline-flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white hover:opacity-90 focus:outline-none focus:ring-2"
                  style={{
                    backgroundColor: 'var(--theme-primary)'
                  }}
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

export default Home;
