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

const Home: React.FC = () => {
  const [videos, setVideos] = useState<any[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategoryId, setSelectedCategoryId] = useState<number | null>(null);
  const [isFilteringByCategory, setIsFilteringByCategory] = useState(false);
  const [loading, setLoading] = useState(true);
  const navigate = useNavigate();

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
      
      <Container maxWidth="xl" sx={{ py: 3 }}>
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
                },
                gap: 3 
              }}>
                {videos.map((video) => (
                  <Card 
                    key={video.id}
                    sx={{ 
                      height: '100%', 
                      display: 'flex', 
                      flexDirection: 'column',
                      transition: 'transform 0.2s ease-in-out, box-shadow 0.2s ease-in-out',
                      '&:hover': {
                        transform: 'translateY(-4px)',
                        boxShadow: 4,
                      },
                    }}
                  >
                    <CardMedia
                      component="img"
                      height="200"
                      image={video.thumbnail_url ? buildApiUrl(API_CONFIG.ENDPOINTS.THUMBNAILS, video.thumbnail_url.split('/').pop()) : ''}
                      alt={video.title}
                      sx={{ 
                        objectFit: 'cover',
                        cursor: 'pointer',
                      }}
                      onClick={() => handleVideoClick(video.id)}
                    />
                    <CardContent sx={{ flexGrow: 1 }}>
                      <Typography 
                        variant="h6" 
                        component="h3" 
                        gutterBottom
                        sx={{ 
                          fontWeight: 'bold',
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                          display: '-webkit-box',
                          WebkitLineClamp: 2,
                          WebkitBoxOrient: 'vertical',
                        }}
                      >
                        {video.title}
                      </Typography>
                      <Typography 
                        variant="body2" 
                        color="text.secondary" 
                        sx={{ 
                          mb: 1,
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                          display: '-webkit-box',
                          WebkitLineClamp: 3,
                          WebkitBoxOrient: 'vertical',
                        }}
                      >
                        {video.description}
                      </Typography>
                      <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                        <VisibilityIcon sx={{ fontSize: 16, mr: 0.5 }} />
                        <Typography variant="caption" color="text.secondary">
                          {video.view_count} views
                        </Typography>
                      </Box>
                      {video.tags && video.tags.length > 0 && (
                        <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5, mb: 1 }}>
                          {video.tags.slice(0, 3).map((tag: string) => (
                            <Chip
                              key={tag}
                              label={tag}
                              size="small"
                              variant="outlined"
                              onClick={() => handleTagClick(tag)}
                              sx={{ 
                                fontSize: '0.75rem',
                                cursor: 'pointer',
                                '&:hover': {
                                  backgroundColor: 'primary.main',
                                  color: 'primary.contrastText',
                                },
                              }}
                            />
                          ))}
                          {video.tags.length > 3 && (
                            <Chip
                              label={`+${video.tags.length - 3}`}
                              size="small"
                              variant="outlined"
                              sx={{ fontSize: '0.75rem' }}
                            />
                          )}
                        </Box>
                      )}
                    </CardContent>
                    <CardActions>
                      <Button
                        fullWidth
                        variant="contained"
                        startIcon={<PlayArrowIcon />}
                        onClick={() => handleVideoClick(video.id)}
                        sx={{ m: 1 }}
                      >
                        Watch Now
                      </Button>
                    </CardActions>
                  </Card>
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
