import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Container,
  Paper,
  TextField,
  Button,
  Typography,
  Box,
  Alert,
  FormControlLabel,
  Checkbox,
  Link,
  Divider,
} from '@mui/material';
import {
  Login as LoginIcon,
  PersonAdd as PersonAddIcon,
} from '@mui/icons-material';
import Navbar from './Navbar';
import { buildApiUrl, API_CONFIG } from '../config';

const Login: React.FC = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [rememberMe, setRememberMe] = useState(false);
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    
    try {
      const response = await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.LOGIN), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        credentials: 'include',
        body: JSON.stringify({ username: email, password }),
      });
      const data = await response.json();
      
      if (response.ok) {
        // Check if token is provided, if not, it's session-based auth
        if (data.token) {
          localStorage.setItem('token', data.token);
        }
        localStorage.setItem('user', JSON.stringify(data.user));
        // Force a storage event to update Navbar
        window.dispatchEvent(new Event('storage'));
        navigate('/home');
      } else {
        setError(data.error || 'Login failed');
      }
    } catch (err) {
      setError('An error occurred. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box sx={{ minHeight: '100vh', backgroundColor: 'background.default' }}>
      <Navbar />
      <Container component="main" maxWidth="sm" sx={{ py: 8 }}>
        <Paper
          elevation={3}
          sx={{
            p: 4,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
          }}
        >
          <Box sx={{ display: 'flex', alignItems: 'center', mb: 3 }}>
            <LoginIcon sx={{ mr: 1, fontSize: 32 }} color="primary" />
            <Typography component="h1" variant="h4" fontWeight="bold">
              Sign In
            </Typography>
          </Box>

          <Typography variant="body1" color="text.secondary" sx={{ mb: 3, textAlign: 'center' }}>
            Welcome back! Please sign in to your account.
          </Typography>

          {error && (
            <Alert severity="error" sx={{ width: '100%', mb: 2 }}>
              {error}
            </Alert>
          )}

          <Box component="form" onSubmit={handleSubmit} sx={{ width: '100%' }}>
            <TextField
              margin="normal"
              required
              fullWidth
              id="email"
              label="Email Address"
              name="email"
              autoComplete="email"
              autoFocus
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              disabled={loading}
            />
            <TextField
              margin="normal"
              required
              fullWidth
              name="password"
              label="Password"
              type="password"
              id="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              disabled={loading}
            />
            
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mt: 2, mb: 2 }}>
              <FormControlLabel
                control={
                  <Checkbox
                    value="remember"
                    color="primary"
                    checked={rememberMe}
                    onChange={(e) => setRememberMe(e.target.checked)}
                    disabled={loading}
                  />
                }
                label="Remember me"
              />
              <Link
                component="button"
                type="button"
                variant="body2"
                onClick={() => {
                  // TODO: Implement forgot password functionality
                  console.log('Forgot password clicked');
                }}
                sx={{ textDecoration: 'none' }}
              >
                Forgot password?
              </Link>
            </Box>

            <Button
              type="submit"
              fullWidth
              variant="contained"
              size="large"
              disabled={loading}
              sx={{ mt: 2, mb: 2, py: 1.5 }}
            >
              {loading ? 'Signing In...' : 'Sign In'}
            </Button>

            <Divider sx={{ my: 3 }}>
              <Typography variant="body2" color="text.secondary">
                OR
              </Typography>
            </Divider>

            <Box sx={{ textAlign: 'center' }}>
              <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
                Don't have an account?
              </Typography>
              <Button
                variant="outlined"
                startIcon={<PersonAddIcon />}
                onClick={() => navigate('/register')}
                disabled={loading}
                sx={{ textTransform: 'none' }}
              >
                Create Account
              </Button>
            </Box>
          </Box>
        </Paper>
      </Container>
    </Box>
  );
};

export default Login;
