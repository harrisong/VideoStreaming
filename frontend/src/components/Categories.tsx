import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import Navbar from './Navbar';
import { buildApiUrl, API_CONFIG } from '../config';
import { useSearchFocus } from '../contexts/SearchFocusContext';

interface Category {
  id: number;
  name: string;
  description: string;
  created_at: string;
  icon_svg?: string;
}

interface Video {
  id: number;
  title: string;
  description: string;
  thumbnail_url: string;
  view_count: number;
  tags: string[];
  category_id: number;
}

const Categories: React.FC = () => {
  const [categories, setCategories] = useState<Category[]>([]);
  const [videos, setVideos] = useState<Video[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<Category | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const navigate = useNavigate();
  const { categoryId } = useParams<{ categoryId: string }>();
  const { isSearchFocused } = useSearchFocus();

  useEffect(() => {
    fetchCategories();
  }, []);

  useEffect(() => {
    if (categoryId && categories.length > 0) {
      const category = categories.find(cat => cat.id === parseInt(categoryId));
      if (category) {
        setSelectedCategory(category);
        fetchVideosByCategory(parseInt(categoryId));
      }
    }
  }, [categoryId, categories]);

  const fetchCategories = async () => {
    try {
      const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.CATEGORIES), {
        credentials: 'include'
      });
      const data = await response.json();
      // Ensure data is an array
      if (Array.isArray(data)) {
        setCategories(data);
      } else {
        console.error('Categories API returned non-array data:', data);
        setCategories([]);
      }
    } catch (error) {
      console.error('Error fetching categories:', error);
      setCategories([]);
    }
  };

  const fetchVideosByCategory = async (categoryId: number) => {
    setIsLoading(true);
    try {
      const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEO_BY_CATEGORY, categoryId.toString()), {
        credentials: 'include'
      });
      const data = await response.json();
      setVideos(data);
    } catch (error) {
      console.error('Error fetching videos by category:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleCategoryClick = (category: Category) => {
    navigate(`/categories/${category.id}`);
  };

  const handleSearch = async (query: string) => {
    try {
      const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEO_SEARCH, encodeURIComponent(query)), {
        credentials: 'include'
      });
      const data = await response.json();
      setVideos(data);
      setSelectedCategory(null);
    } catch (error) {
      console.error('Error searching videos:', error);
    }
  };

  return (
    <div className="video-container-themed min-h-screen">
      <Navbar onSearch={handleSearch} />
      <main 
        className="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8 transition-all duration-300 ease-in-out"
        style={{
          filter: isSearchFocused ? 'blur(8px)' : 'none',
          opacity: isSearchFocused ? 0.3 : 1,
          pointerEvents: isSearchFocused ? 'none' : 'auto',
        }}
      >
        {/* Categories Grid */}
        {!selectedCategory && (
          <div>
            <h2 className="text-2xl font-bold theme-text mb-6">Browse by Category</h2>
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4 mb-8">
              {categories.map((category) => (
                <button
                  key={category.id}
                  onClick={() => handleCategoryClick(category)}
                  className="category-card-themed p-4 rounded-lg shadow-md hover:shadow-lg transition-shadow duration-200 text-center"
                >
                  {/* Category Icon */}
                  {category.icon_svg && (
                    <div 
                      className="w-8 h-8 mx-auto mb-3 theme-text"
                      dangerouslySetInnerHTML={{ __html: category.icon_svg }}
                    />
                  )}
                  <h3 className="font-semibold theme-text text-sm mb-2">{category.name}</h3>
                  <p className="theme-text-secondary text-xs">{category.description}</p>
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Selected Category Header */}
        {selectedCategory && (
          <div className="mb-6 flex items-center justify-between">
            <div>
              <h2 className="text-2xl font-bold theme-text">{selectedCategory.name}</h2>
              <p className="theme-text-secondary">{selectedCategory.description}</p>
              <p className="theme-text-secondary text-sm mt-1">
                {videos.length} video{videos.length !== 1 ? 's' : ''} found
              </p>
            </div>
            <button
              onClick={() => navigate('/categories')}
              className="inline-flex items-center px-3 py-2 border shadow-sm text-sm leading-4 font-medium rounded-md hover:opacity-80 focus:outline-none focus:ring-2"
              style={{
                backgroundColor: 'var(--theme-surface)',
                color: 'var(--theme-text)',
                borderColor: 'var(--theme-text-secondary)'
              }}
            >
              ← Back to Categories
            </button>
          </div>
        )}

        {/* Loading State */}
        {isLoading && (
          <div className="text-center py-12">
            <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900"></div>
            <p className="theme-text mt-2">Loading videos...</p>
          </div>
        )}

        {/* No Videos Message */}
        {selectedCategory && !isLoading && videos.length === 0 && (
          <div className="text-center py-12">
            <h3 className="text-lg font-medium theme-text mb-2">No videos found</h3>
            <p className="theme-text-secondary">This category doesn't have any videos yet</p>
          </div>
        )}

        {/* Videos Grid */}
        {videos.length > 0 && (
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
            {videos.map((video) => (
              <div key={video.id} className="video-card-themed rounded-lg shadow-md overflow-hidden">
                <img 
                  src={video.thumbnail_url ? buildApiUrl(API_CONFIG.ENDPOINTS.THUMBNAILS, video.thumbnail_url.split('/').pop() || '') : ''}
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
        )}
      </main>
    </div>
  );
};

export default Categories;
