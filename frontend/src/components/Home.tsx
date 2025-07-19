import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Container,
  Card,
  CardMedia,
  CardContent,
  CardActions,
  Typography,
  Button,
  Box,
  Chip,
  Alert,
  CircularProgress,
  Paper,
} from '@mui/material';
import {
  PlayArrow as PlayArrowIcon,
  Visibility as VisibilityIcon,
  Clear as ClearIcon,
} from '@mui/icons-material';
import Navbar from './Navbar';
import CategorySidebar from './CategorySidebar';
import { buildApiUrl, API_CONFIG } from '../config';
import { useSearchFocus } from '../contexts/SearchFocusContext';

const Home: React.FC = () => {
  const [videos, setVideos] = useState<any[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategoryId, setSelectedCategoryId] = useState<number | null>(null);
  const [isFilteringByCategory, setIsFilteringByCategory] = useState(false);
  const [loading, setLoading] = useState(true);
  const navigate = useNavigate();
  const { isSearchFocused } = useSearchFocus();

  // Helper function to format duration
  const formatDuration = (seconds: number | null | undefined): string => {
    if (!seconds || seconds <= 0) return '0:00';
    
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const remainingSeconds = Math.floor(seconds % 60);
    
    if (hours > 0) {
      return `${hours}:${minutes.toString().padStart(2, '0')}:${remainingSeconds.toString().padStart(2, '0')}`;
    } else {
      return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
    }
  };

  useEffect(() => {
    const fetchVideos = async () => {
      try {
        setLoading(true);
        const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEOS), {
          credentials: 'include'
        });
        const data = await response.json();
        setVideos(data);
      } catch (error) {
        console.error('Error fetching videos:', error);
      } finally {
        setLoading(false);
      }
    };
    fetchVideos();
  }, []);

  const handleSearch = async (query: string) => {
    setIsSearching(true);
    setSearchQuery(query);
    setLoading(true);
    try {
      const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEO_SEARCH, encodeURIComponent(query)), {
        credentials: 'include'
      });
      const data = await response.json();
      setVideos(data);
    } catch (error) {
      console.error('Error searching videos:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleClearSearch = async () => {
    setIsSearching(false);
    setSearchQuery('');
    setSelectedCategoryId(null);
    setIsFilteringByCategory(false);
    setLoading(true);
    try {
      const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEOS), {
        credentials: 'include'
      });
      const data = await response.json();
      setVideos(data);
    } catch (error) {
      console.error('Error fetching videos:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleCategorySelect = async (categoryId: number | null) => {
    setSelectedCategoryId(categoryId);
    setIsSearching(false);
    setSearchQuery('');
    setLoading(true);
    
    if (categoryId === null) {
      // Show all videos
      setIsFilteringByCategory(false);
      try {
        const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEOS), {
          credentials: 'include'
        });
        const data = await response.json();
        setVideos(data);
      } catch (error) {
        console.error('Error fetching videos:', error);
      }
    } else {
      // Filter by category
      setIsFilteringByCategory(true);
      try {
        const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.VIDEO_BY_CATEGORY, categoryId.toString()), {
          credentials: 'include'
        });
        const data = await response.json();
        setVideos(data);
      } catch (error) {
        console.error('Error fetching videos by category:', error);
      }
    }
    setLoading(false);
  };

  const handleTagClick = (tag: string) => {
    navigate(`/tag/${tag}`);
  };

  const handleVideoClick = (videoId: string) => {
    navigate(`/video/${videoId}`);
  };

  return (
    <Box sx={{ minHeight: '100vh', backgroundColor: 'background.default' }}>
      <Navbar onSearch={handleSearch} />
      
      <Container 
        maxWidth="xl" 
        sx={{ 
          py: 3,
          transition: 'all 0.3s ease-in-out',
          ...(isSearchFocused && {
            filter: 'blur(8px)',
            opacity: 0.3,
            pointerEvents: 'none',
          }),
        }}
      >
        <Box sx={{ display: 'flex', gap: 3 }}>
          {/* Category Sidebar */}
          <Box sx={{ 
            width: { xs: '100%', md: '250px' }, 
            flexShrink: 0,
            display: { xs: 'none', md: 'block' }
          }}>
            <CategorySidebar 
              onCategorySelect={handleCategorySelect}
              selectedCategoryId={selectedCategoryId}
            />
          </Box>
          
          {/* Main Content */}
          <Box sx={{ flex: 1, minWidth: 0 }}>
            {/* Search Results Header */}
            {isSearching && (
              <Paper sx={{ p: 2, mb: 3, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Typography variant="h6">
                  Search results for "{searchQuery}" ({videos.length} videos found)
                </Typography>
                <Button
                  variant="outlined"
                  startIcon={<ClearIcon />}
                  onClick={handleClearSearch}
                >
                  Clear Search
                </Button>
              </Paper>
            )}

            {/* Category Filter Header */}
            {isFilteringByCategory && !isSearching && (
              <Paper sx={{ p: 2, mb: 3, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Typography variant="h6">
                  Category Videos ({videos.length} videos found)
                </Typography>
                <Button
                  variant="outlined"
                  startIcon={<ClearIcon />}
                  onClick={() => handleCategorySelect(null)}
                >
                  Show All Videos
                </Button>
              </Paper>
            )}
            
            {/* Loading State */}
            {loading && (
              <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                <CircularProgress />
              </Box>
            )}

            {/* No Results Message */}
            {!loading && (isSearching || isFilteringByCategory) && videos.length === 0 && (
              <Alert severity="info" sx={{ mb: 3 }}>
                <Typography variant="h6" gutterBottom>
                  No videos found
                </Typography>
                <Typography>
                  {isSearching ? 'Try searching with different keywords' : 'This category doesn\'t have any videos yet'}
                </Typography>
              </Alert>
            )}

            {/* Video Grid */}
            {!loading && (
              <Box sx={{ 
                display: 'grid', 
                gridTemplateColumns: {
                  xs: '1fr',
                  sm: 'repeat(2, 1fr)',
                  md: 'repeat(3, 1fr)',
                  lg: 'repeat(4, 1fr)',
                  xl: 'repeat(5, 1fr)',
                },
                gap: 2 
              }}>
                {videos.map((video) => (
                  <Box 
                    key={video.id}
                    sx={{ 
                      cursor: 'pointer',
                      transition: 'transform 0.2s ease-in-out',
                      '&:hover': {
                        transform: 'scale(1.05)',
                      },
                    }}
                    onClick={() => handleVideoClick(video.id)}
                  >
                    {/* Thumbnail Container */}
                    <Box sx={{ 
                      position: 'relative',
                      aspectRatio: '16/9',
                      borderRadius: 2,
                      overflow: 'hidden',
                      mb: 1,
                      backgroundColor: '#f5f5f5',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                    }}>
                      <img
                        src={video.thumbnail_url ? buildApiUrl(API_CONFIG.ENDPOINTS.THUMBNAILS, video.thumbnail_url.split('/').pop()) : ''}
                        alt={video.title}
                        style={{
                          width: '100%',
                          height: '100%',
                          objectFit: 'cover',
                        }}
                        onError={(e) => {
                          const target = e.target as HTMLImageElement;
                          target.style.display = 'none'; // Hide the broken image
                          target.alt = ''; // Clear alt text
                          
                          // Create fallback content if it doesn't exist
                          const container = target.parentElement;
                          if (container && !container.querySelector('.fallback-content')) {
                            const fallback = document.createElement('div');
                            fallback.className = 'fallback-content';
                            fallback.style.cssText = `
                              position: absolute;
                              top: 0;
                              left: 0;
                              right: 0;
                              bottom: 0;
                              display: flex;
                              align-items: center;
                              justify-content: center;
                              background-color: #f5f5f5;
                              color: #9e9e9e;
                              font-size: 48px;
                              z-index: 1;
                            `;
                            fallback.innerHTML = '▶';
                            container.appendChild(fallback);
                          }
                        }}
                      />
                      
                      {/* Play Button Overlay */}
                      <Box sx={{
                        position: 'absolute',
                        top: 0,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        backgroundColor: 'rgba(0, 0, 0, 0)',
                        transition: 'background-color 0.2s ease-in-out',
                        '&:hover': {
                          backgroundColor: 'rgba(0, 0, 0, 0.3)',
                          '& .play-icon': {
                            opacity: 1,
                            transform: 'scale(1)',
                          },
                        },
                      }}>
                        <PlayArrowIcon 
                          className="play-icon"
                          sx={{
                            fontSize: 48,
                            color: 'white',
                            opacity: 0,
                            transform: 'scale(0.8)',
                            transition: 'all 0.2s ease-in-out',
                            filter: 'drop-shadow(0 2px 4px rgba(0,0,0,0.5))',
                          }}
                        />
                      </Box>
                      
                      {/* Duration Badge */}
                      <Box sx={{
                        position: 'absolute',
                        bottom: 8,
                        right: 8,
                        backgroundColor: 'rgba(0, 0, 0, 0.8)',
                        color: 'white',
                        px: 1,
                        py: 0.25,
                        borderRadius: 1,
                        fontSize: '0.75rem',
                        fontWeight: 500,
                        zIndex: 2,
                      }}>
                        {formatDuration(video.duration)}
                      </Box>
                    </Box>
                    
                    {/* Video Title */}
                    <Typography 
                      variant="body2" 
                      sx={{ 
                        fontWeight: 500,
                        lineHeight: 1.3,
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        display: '-webkit-box',
                        WebkitLineClamp: 2,
                        WebkitBoxOrient: 'vertical',
                        mb: 0.5,
                      }}
                    >
                      {video.title}
                    </Typography>
                    
                    {/* View Count */}
                    <Typography 
                      variant="caption" 
                      color="text.secondary"
                      sx={{ fontSize: '0.75rem' }}
                    >
                      {video.view_count?.toLocaleString() || 0} views
                    </Typography>
                  </Box>
                ))}
              </Box>
            )}
          </Box>
        </Box>
      </Container>
    </Box>
  );
};

export default Home;
