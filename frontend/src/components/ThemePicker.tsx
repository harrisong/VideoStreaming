import React, { useState, useEffect } from 'react';
import {
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  Grid,
  Card,
  CardContent,
  Typography,
  Box,
  TextField,
  IconButton,
  Chip,
  Alert,
  Tabs,
  Tab,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
} from '@mui/material';
import {
  Close as CloseIcon,
  Palette as PaletteIcon,
  Computer as ComputerIcon,
  LightMode as LightModeIcon,
  DarkMode as DarkModeIcon,
  YouTube as YouTubeIcon,
  VideoLibrary as VideoLibraryIcon,
} from '@mui/icons-material';
import { buildApiUrl, API_CONFIG } from '../config';
import { useTheme } from '../contexts/ThemeContext';

interface Theme {
  name: string;
  primary: string;
  secondary: string;
  accent: string;
  background: string;
  surface: string;
  text: string;
  textSecondary: string;
  plyrColor: string;
  isCustom?: boolean;
  isDark?: boolean;
}

interface ThemePickerProps {
  isOpen: boolean;
  onClose: () => void;
}

const ThemePicker: React.FC<ThemePickerProps> = ({ isOpen, onClose }) => {
  const { applyTheme, predefinedThemes, currentTheme } = useTheme();
  const [selectedTheme, setSelectedTheme] = useState<string>('system');
  const [customTheme, setCustomTheme] = useState<Theme>({
    name: 'Custom',
    primary: '#4f46e5',
    secondary: '#3730a3',
    accent: '#6366f1',
    background: '#f9fafb',
    surface: '#ffffff',
    text: '#111827',
    textSecondary: '#6b7280',
    plyrColor: '#4f46e5',
    isCustom: true
  });
  const [tabValue, setTabValue] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (isOpen) {
      loadUserSettings();
    }
  }, [isOpen]);

  const loadUserSettings = async () => {
    try {
      const token = localStorage.getItem('token');
      
      if (!token) {
        // For non-logged-in users, load from localStorage
        const savedTheme = localStorage.getItem('selectedTheme') || 'system';
        setSelectedTheme(savedTheme);
        return;
      }

      const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.USER_SETTINGS), {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });

      if (response.ok) {
        const data = await response.json();
        const theme = data.settings?.theme;
        if (theme) {
          if (theme.isCustom) {
            setTabValue(1);
            setCustomTheme(theme);
            setSelectedTheme('custom');
          } else {
            setSelectedTheme(theme.name || 'system');
          }
        }
      }
    } catch (error) {
      console.error('Error loading user settings:', error);
      setError('Failed to load theme settings');
    }
  };

  const saveTheme = async () => {
    setLoading(true);
    setError('');
    
    try {
      const token = localStorage.getItem('token');
      const themeData = tabValue === 1 ? { ...customTheme, isCustom: true } : { name: selectedTheme };

      if (!token) {
        // For non-logged-in users, save to localStorage
        localStorage.setItem('selectedTheme', selectedTheme);
        applyTheme(themeData);
        onClose();
        return;
      }

      const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.USER_SETTINGS), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({ theme: themeData })
      });

      if (response.ok) {
        applyTheme(themeData);
        onClose();
      } else {
        setError('Failed to save theme settings');
      }
    } catch (error) {
      console.error('Error saving theme:', error);
      setError('Error saving theme settings');
    } finally {
      setLoading(false);
    }
  };

  const handleThemeSelect = (themeName: string) => {
    setSelectedTheme(themeName);
    applyTheme({ name: themeName });
  };

  const handleCustomThemeChange = (field: keyof Theme, value: string) => {
    const updatedTheme = { ...customTheme, [field]: value };
    setCustomTheme(updatedTheme);
    applyTheme(updatedTheme);
  };

  const getThemeIcon = (themeName: string) => {
    switch (themeName) {
      case 'system':
        return <ComputerIcon />;
      case 'default':
        return <LightModeIcon />;
      case 'defaultDark':
        return <DarkModeIcon />;
      case 'youtube':
        return <YouTubeIcon />;
      case 'vimeo':
        return <VideoLibraryIcon />;
      default:
        return <PaletteIcon />;
    }
  };

  const getThemeDescription = (themeName: string) => {
    switch (themeName) {
      case 'system':
        return 'Automatically matches your system preference';
      case 'default':
        return 'Clean light theme for daytime use';
      case 'defaultDark':
        return 'Dark theme for comfortable viewing';
      default:
        return predefinedThemes[themeName]?.name || themeName;
    }
  };

  return (
    <Dialog 
      open={isOpen} 
      onClose={onClose} 
      maxWidth="md" 
      fullWidth
      PaperProps={{
        sx: { minHeight: '500px' }
      }}
    >
      <DialogTitle sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <PaletteIcon />
          <Typography variant="h6">Theme Settings</Typography>
        </Box>
        <IconButton onClick={onClose} size="small">
          <CloseIcon />
        </IconButton>
      </DialogTitle>

      <DialogContent>
        {error && (
          <Alert severity="error" sx={{ mb: 2 }}>
            {error}
          </Alert>
        )}

        <Tabs value={tabValue} onChange={(_, newValue) => setTabValue(newValue)} sx={{ mb: 3 }}>
          <Tab label="Predefined Themes" />
          <Tab label="Custom Theme" />
        </Tabs>

        {tabValue === 0 && (
          <Box sx={{ 
            display: 'grid', 
            gridTemplateColumns: {
              xs: '1fr',
              sm: 'repeat(2, 1fr)',
              md: 'repeat(3, 1fr)',
            },
            gap: 2 
          }}>
            {Object.entries(predefinedThemes).map(([key, theme]) => (
              <Card
                key={key}
                sx={{
                  cursor: 'pointer',
                  border: selectedTheme === key ? 2 : 1,
                  borderColor: selectedTheme === key ? 'primary.main' : 'divider',
                  '&:hover': {
                    boxShadow: 2,
                  },
                }}
                onClick={() => handleThemeSelect(key)}
              >
                <CardContent>
                  <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                    {getThemeIcon(key)}
                    <Typography variant="h6" sx={{ ml: 1 }}>
                      {theme.name}
                    </Typography>
                  </Box>
                  
                  <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                    {getThemeDescription(key)}
                  </Typography>

                  <Box sx={{ display: 'flex', gap: 0.5, mb: 1 }}>
                    {[theme.primary, theme.secondary, theme.accent, theme.surface].map((color, index) => (
                      <Box
                        key={index}
                        sx={{
                          width: 20,
                          height: 20,
                          backgroundColor: color,
                          borderRadius: 0.5,
                          border: '1px solid',
                          borderColor: 'divider',
                        }}
                      />
                    ))}
                  </Box>

                  {theme.isDark !== undefined && (
                    <Chip
                      label={theme.isDark ? 'Dark' : 'Light'}
                      size="small"
                      variant="outlined"
                      sx={{ mt: 1 }}
                    />
                  )}
                </CardContent>
              </Card>
            ))}
          </Box>
        )}

        {tabValue === 1 && (
          <Box>
            <Typography variant="h6" gutterBottom>
              Customize Your Theme
            </Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
              Create your own unique theme by adjusting the colors below. Changes are applied in real-time.
            </Typography>

            <Box sx={{ 
              display: 'grid', 
              gridTemplateColumns: {
                xs: '1fr',
                sm: 'repeat(2, 1fr)',
              },
              gap: 3 
            }}>
              {Object.entries(customTheme).map(([key, value]) => {
                if (key === 'name' || key === 'isCustom' || key === 'isDark') return null;
                return (
                  <Box key={key} sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                    <input
                      type="color"
                      value={value}
                      onChange={(e) => handleCustomThemeChange(key as keyof Theme, e.target.value)}
                      style={{
                        width: 50,
                        height: 40,
                        border: 'none',
                        borderRadius: 4,
                        cursor: 'pointer',
                      }}
                    />
                    <TextField
                      fullWidth
                      label={key.replace(/([A-Z])/g, ' $1').replace(/^./, str => str.toUpperCase())}
                      value={value}
                      onChange={(e) => handleCustomThemeChange(key as keyof Theme, e.target.value)}
                      size="small"
                    />
                  </Box>
                );
              })}
            </Box>
          </Box>
        )}
      </DialogContent>

      <DialogActions sx={{ px: 3, pb: 2 }}>
        <Button onClick={onClose} disabled={loading}>
          Cancel
        </Button>
        <Button 
          onClick={saveTheme} 
          variant="contained" 
          disabled={loading}
          startIcon={loading ? undefined : <PaletteIcon />}
        >
          {loading ? 'Saving...' : 'Apply Theme'}
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export default ThemePicker;
