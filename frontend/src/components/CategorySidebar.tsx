import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Box,
  Typography,
  List,
  ListItem,
  ListItemButton,
  ListItemText,
  Button,
  Skeleton,
  Divider,
  Paper,
} from '@mui/material';
import {
  Category as CategoryIcon,
  ArrowForward as ArrowForwardIcon,
} from '@mui/icons-material';
import { buildApiUrl, API_CONFIG } from '../config';

interface Category {
  id: number;
  name: string;
  description: string;
  created_at: string;
}

interface CategorySidebarProps {
  onCategorySelect: (categoryId: number | null) => void;
  selectedCategoryId: number | null;
}

const CategorySidebar: React.FC<CategorySidebarProps> = ({ onCategorySelect, selectedCategoryId }) => {
  const [categories, setCategories] = useState<Category[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const navigate = useNavigate();

  useEffect(() => {
    fetchCategories();
  }, []);

  const fetchCategories = async () => {
    try {
      const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.CATEGORIES), {
        credentials: 'include'
      });
      const data = await response.json();
      setCategories(data);
    } catch (error) {
      console.error('Error fetching categories:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleCategoryClick = (categoryId: number | null) => {
    onCategorySelect(categoryId);
  };

  const handleViewAllCategories = () => {
    navigate('/categories');
  };

  if (isLoading) {
    return (
      <Paper sx={{ p: 2, height: 'fit-content' }}>
        <Skeleton variant="text" width="60%" height={32} sx={{ mb: 2 }} />
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
          {[...Array(6)].map((_, i) => (
            <Skeleton key={i} variant="rectangular" height={40} sx={{ borderRadius: 1 }} />
          ))}
        </Box>
      </Paper>
    );
  }

  return (
    <Paper sx={{ p: 2, height: 'fit-content', position: 'sticky', top: 16 }}>
      <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
        <CategoryIcon sx={{ mr: 1 }} />
        <Typography variant="h6" component="h2">
          Categories
        </Typography>
      </Box>
      
      <List sx={{ p: 0 }}>
        {/* All Videos Option */}
        <ListItem sx={{ p: 0, mb: 1 }}>
          <ListItemButton
            onClick={() => handleCategoryClick(null)}
            selected={selectedCategoryId === null}
            sx={{
              borderRadius: 1,
              '&.Mui-selected': {
                backgroundColor: 'primary.main',
                color: 'primary.contrastText',
                '&:hover': {
                  backgroundColor: 'primary.dark',
                },
              },
            }}
          >
            <ListItemText 
              primary="All Videos" 
              primaryTypographyProps={{ 
                fontWeight: selectedCategoryId === null ? 'bold' : 'normal' 
              }}
            />
          </ListItemButton>
        </ListItem>

        {/* Category List */}
        {categories.slice(0, 8).map((category) => (
          <ListItem key={category.id} sx={{ p: 0, mb: 0.5 }}>
            <ListItemButton
              onClick={() => handleCategoryClick(category.id)}
              selected={selectedCategoryId === category.id}
              sx={{
                borderRadius: 1,
                '&.Mui-selected': {
                  backgroundColor: 'primary.main',
                  color: 'primary.contrastText',
                  '&:hover': {
                    backgroundColor: 'primary.dark',
                  },
                },
              }}
            >
              <ListItemText 
                primary={category.name}
                primaryTypographyProps={{ 
                  fontSize: '0.875rem',
                  fontWeight: selectedCategoryId === category.id ? 'bold' : 'normal' 
                }}
                title={category.description}
              />
            </ListItemButton>
          </ListItem>
        ))}
      </List>

      {/* View All Categories Button */}
      {categories.length > 8 && (
        <>
          <Divider sx={{ my: 2 }} />
          <Button
            fullWidth
            variant="outlined"
            size="small"
            endIcon={<ArrowForwardIcon />}
            onClick={handleViewAllCategories}
            sx={{ 
              justifyContent: 'space-between',
              textTransform: 'none',
            }}
          >
            View All Categories
          </Button>
        </>
      )}

      {/* Category Count */}
      <Divider sx={{ my: 2 }} />
      <Typography variant="caption" color="text.secondary" sx={{ display: 'block', textAlign: 'center' }}>
        {categories.length} categories available
      </Typography>
    </Paper>
  );
};

export default CategorySidebar;
