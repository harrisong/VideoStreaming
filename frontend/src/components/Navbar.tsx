import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  AppBar,
  Toolbar,
  Typography,
  Button,
  IconButton,
  Menu,
  MenuItem,
  TextField,
  InputAdornment,
  Box,
  Avatar,
  Divider,
  ListItemIcon,
  ListItemText,
  Container,
} from '@mui/material';
import {
  Search as SearchIcon,
  Category as CategoryIcon,
  Palette as PaletteIcon,
  AccountCircle as AccountCircleIcon,
  Logout as LogoutIcon,
  Login as LoginIcon,
  Group as GroupIcon,
} from '@mui/icons-material';
import { buildApiUrl, API_CONFIG } from '../config';
import ThemePicker from './ThemePicker';
import Logo from './Logo';

const Navbar: React.FC<{ 
  onWatchPartyToggle?: () => void; 
  isWatchParty?: boolean; 
  onSearch?: (query: string) => void 
}> = ({ onWatchPartyToggle, isWatchParty, onSearch }) => {
  const navigate = useNavigate();
  const [user, setUser] = useState<any>(null);
  const [anchorEl, setAnchorEl] = useState<null | HTMLElement>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [isThemePickerOpen, setIsThemePickerOpen] = useState(false);
  const [isMobileSearchOpen, setIsMobileSearchOpen] = useState(false);

  const isMenuOpen = Boolean(anchorEl);

  useEffect(() => {
    // Load user data from localStorage if token exists
    const token = localStorage.getItem('token');
    const storedUser = localStorage.getItem('user');
    if (token && storedUser) {
      setUser(JSON.parse(storedUser));
    } else {
      setUser(null);
    }

    // Listen for changes in localStorage to update user state
    const handleStorageChange = () => {
      const updatedToken = localStorage.getItem('token');
      const updatedUser = localStorage.getItem('user');
      if (updatedToken && updatedUser) {
        setUser(JSON.parse(updatedUser));
      } else {
        setUser(null);
      }
    };

    window.addEventListener('storage', handleStorageChange);
    return () => window.removeEventListener('storage', handleStorageChange);
  }, []);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    if (onSearch && searchQuery.trim()) {
      onSearch(searchQuery.trim());
    }
  };

  const handleMenuOpen = (event: React.MouseEvent<HTMLElement>) => {
    setAnchorEl(event.currentTarget);
  };

  const handleMenuClose = () => {
    setAnchorEl(null);
  };

  const handleLogout = async () => {
    try {
      await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.LOGOUT), {
        method: 'POST',
        credentials: 'include'
      });
      localStorage.removeItem('user');
      localStorage.removeItem('token');
      setUser(null);
      navigate('/login');
    } catch (error) {
      console.error('Error during logout:', error);
    }
    handleMenuClose();
  };

  return (
    <>
      <AppBar position="static" elevation={1}>
        <Container maxWidth="xl" sx={{ px: { xs: 1, sm: 2 } }}>
          <Toolbar sx={{ 
            justifyContent: 'space-between',
            minHeight: { xs: 56, sm: 64 },
            px: '0 !important'
          }}>
            {/* Logo */}
            <IconButton
              color="inherit"
              onClick={() => navigate('/home')}
              sx={{ 
                p: 1,
                borderRadius: 1,
                '&:hover': {
                  backgroundColor: 'rgba(255, 255, 255, 0.08)',
                },
              }}
              disableRipple={false}
              TouchRippleProps={{
                style: {
                  borderRadius: '4px',
                },
              }}
            >
              <Logo />
            </IconButton>

            {/* Desktop Search Bar */}
            {onSearch && (
              <Box
                component="form"
                onSubmit={handleSearch}
                sx={{ 
                  flexGrow: 1, 
                  maxWidth: 600, 
                  mx: 3,
                  display: { xs: 'none', md: 'block' }
                }}
              >
                <TextField
                  fullWidth
                  size="small"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder="Search videos..."
                  InputProps={{
                    endAdornment: (
                      <InputAdornment position="end">
                        <IconButton type="submit" edge="end">
                          <SearchIcon />
                        </IconButton>
                      </InputAdornment>
                    ),
                  }}
                  sx={{
                    '& .MuiOutlinedInput-root': {
                      backgroundColor: 'rgba(255, 255, 255, 0.1)',
                      '& fieldset': {
                        borderColor: 'rgba(255, 255, 255, 0.3)',
                      },
                      '&:hover fieldset': {
                        borderColor: 'rgba(255, 255, 255, 0.5)',
                      },
                      '&.Mui-focused fieldset': {
                        borderColor: 'primary.main',
                      },
                    },
                    '& .MuiInputBase-input': {
                      color: 'inherit',
                      '&::placeholder': {
                        color: 'rgba(255, 255, 255, 0.7)',
                        opacity: 1,
                      },
                    },
                  }}
                />
              </Box>
            )}

            {/* Action Buttons */}
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            {/* Mobile Search Button */}
            {onSearch && (
              <IconButton
                color="inherit"
                onClick={() => setIsMobileSearchOpen(!isMobileSearchOpen)}
                sx={{ display: { xs: 'flex', md: 'none' } }}
                title="Search"
              >
                <SearchIcon />
              </IconButton>
            )}

            {/* Categories Button */}
            <Button
              color="inherit"
              startIcon={<CategoryIcon />}
              onClick={() => navigate('/categories')}
              sx={{ display: { xs: 'none', sm: 'flex' } }}
            >
              Categories
            </Button>

            {/* Categories Icon for mobile */}
            <IconButton
              color="inherit"
              onClick={() => navigate('/categories')}
              sx={{ display: { xs: 'flex', sm: 'none' } }}
              title="Categories"
            >
              <CategoryIcon />
            </IconButton>

            {/* Watch Party Button */}
            {onWatchPartyToggle && (
              <Button
                variant={isWatchParty ? "contained" : "outlined"}
                color={isWatchParty ? "success" : "primary"}
                startIcon={<GroupIcon />}
                onClick={onWatchPartyToggle}
                sx={{ display: { xs: 'none', md: 'flex' } }}
              >
                {isWatchParty ? 'In Watch Party' : 'Start Watch Party'}
              </Button>
            )}

            {/* User Menu */}
            {user ? (
              <>
                <Button
                  color="inherit"
                  onClick={handleMenuOpen}
                  startIcon={<Avatar sx={{ width: 24, height: 24 }}>{user.username[0].toUpperCase()}</Avatar>}
                  sx={{ display: { xs: 'none', sm: 'flex' } }}
                >
                  {user.username}
                </Button>
                <IconButton
                  color="inherit"
                  onClick={handleMenuOpen}
                  sx={{ display: { xs: 'flex', sm: 'none' } }}
                >
                  <Avatar sx={{ width: 32, height: 32 }}>{user.username[0].toUpperCase()}</Avatar>
                </IconButton>
              </>
            ) : (
              <Button
                color="inherit"
                startIcon={<LoginIcon />}
                onClick={() => navigate('/login')}
              >
                Login
              </Button>
            )}
          </Box>
          </Toolbar>
        </Container>
      </AppBar>

      {/* Mobile Search Bar */}
      {onSearch && isMobileSearchOpen && (
        <Box
          sx={{
            display: { xs: 'block', md: 'none' },
            backgroundColor: 'primary.main',
            borderBottom: '1px solid rgba(255, 255, 255, 0.1)',
          }}
        >
          <Container maxWidth="xl">
            <Box
              component="form"
              onSubmit={handleSearch}
              sx={{ p: 2 }}
            >
              <TextField
                fullWidth
                size="small"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search videos..."
                autoFocus
                InputProps={{
                  endAdornment: (
                    <InputAdornment position="end">
                      <IconButton type="submit" edge="end">
                        <SearchIcon />
                      </IconButton>
                    </InputAdornment>
                  ),
                }}
                sx={{
                  '& .MuiOutlinedInput-root': {
                    backgroundColor: 'rgba(255, 255, 255, 0.1)',
                    '& fieldset': {
                      borderColor: 'rgba(255, 255, 255, 0.3)',
                    },
                    '&:hover fieldset': {
                      borderColor: 'rgba(255, 255, 255, 0.5)',
                    },
                    '&.Mui-focused fieldset': {
                      borderColor: 'rgba(255, 255, 255, 0.8)',
                    },
                  },
                  '& .MuiInputBase-input': {
                    color: 'inherit',
                    '&::placeholder': {
                      color: 'rgba(255, 255, 255, 0.7)',
                      opacity: 1,
                    },
                  },
                }}
              />
            </Box>
          </Container>
        </Box>
      )}

      {/* User Menu */}
      <Menu
        anchorEl={anchorEl}
        open={isMenuOpen}
        onClose={handleMenuClose}
        onClick={handleMenuClose}
        PaperProps={{
          elevation: 3,
          sx: {
            mt: 1.5,
            minWidth: 200,
            '& .MuiAvatar-root': {
              width: 32,
              height: 32,
              ml: -0.5,
              mr: 1,
            },
          },
        }}
        transformOrigin={{ horizontal: 'right', vertical: 'top' }}
        anchorOrigin={{ horizontal: 'right', vertical: 'bottom' }}
      >
        {user && (
          <>
            <MenuItem disabled>
              <ListItemIcon>
                <Avatar sx={{ width: 24, height: 24 }}>{user.username[0].toUpperCase()}</Avatar>
              </ListItemIcon>
              <Box>
                <Typography variant="body2" fontWeight="bold">
                  {user.username}
                </Typography>
                <Typography variant="caption" color="text.secondary">
                  {user.email}
                </Typography>
              </Box>
            </MenuItem>
            <Divider />
            <MenuItem onClick={() => setIsThemePickerOpen(true)}>
              <ListItemIcon>
                <PaletteIcon fontSize="small" />
              </ListItemIcon>
              <ListItemText>Theme Settings</ListItemText>
            </MenuItem>
            <MenuItem onClick={handleLogout}>
              <ListItemIcon>
                <LogoutIcon fontSize="small" />
              </ListItemIcon>
              <ListItemText>Logout</ListItemText>
            </MenuItem>
          </>
        )}
      </Menu>

      {/* Theme Picker Modal */}
      <ThemePicker 
        isOpen={isThemePickerOpen} 
        onClose={() => setIsThemePickerOpen(false)} 
      />
    </>
  );
};

export default Navbar;
