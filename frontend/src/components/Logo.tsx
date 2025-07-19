import React from 'react';
import { Box, Typography, keyframes } from '@mui/material';
import { PlayArrow } from '@mui/icons-material';
import { useTheme } from '../contexts/ThemeContext';

// Streaming animation keyframes
const streamingPulse = keyframes`
  0%, 100% {
    opacity: 0.4;
    transform: scale(0.8);
  }
  50% {
    opacity: 1;
    transform: scale(1.2);
  }
`;

const flowAnimation = keyframes`
  0% {
    opacity: 0.3;
  }
  33% {
    opacity: 1;
  }
  66% {
    opacity: 0.6;
  }
  100% {
    opacity: 0.3;
  }
`;

const textGlow = keyframes`
  0%, 100% {
    text-shadow: 0 0 5px transparent;
  }
  50% {
    text-shadow: 0 0 8px rgba(255, 255, 255, 0.2);
  }
`;

const Logo: React.FC<{ className?: string }> = ({ className = '' }) => {
  const { currentTheme } = useTheme();

  return (
    <Box 
      className={className}
      sx={{ 
        display: 'flex', 
        alignItems: 'center', 
        gap: 0.75,
        height: '36px'
      }}
    >
      {/* Subtle creative icon */}
      <Box
        sx={{
          width: 20,
          height: 20,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          flexShrink: 0,
          position: 'relative',
        }}
      >
        {/* Three animated dots representing streaming/flow */}
        <Box
          className="dots-container"
          sx={{
            display: 'flex',
            gap: 0.25,
            alignItems: 'center',
          }}
        >
          <Box
            sx={{
              width: 3,
              height: 3,
              borderRadius: '50%',
              background: `linear-gradient(45deg, ${currentTheme.primary}60, ${currentTheme.accent}40)`,
              animation: `${flowAnimation} 2s ease-in-out infinite`,
              animationDelay: '0s',
            }}
          />
          <Box
            sx={{
              width: 4,
              height: 4,
              borderRadius: '50%',
              background: `linear-gradient(45deg, ${currentTheme.primary}70, ${currentTheme.accent}50)`,
              animation: `${streamingPulse} 2s ease-in-out infinite`,
              animationDelay: '0.3s',
            }}
          />
          <Box
            sx={{
              width: 3,
              height: 3,
              borderRadius: '50%',
              background: `linear-gradient(45deg, ${currentTheme.primary}60, ${currentTheme.accent}40)`,
              animation: `${flowAnimation} 2s ease-in-out infinite`,
              animationDelay: '0.6s',
            }}
          />
        </Box>
      </Box>
      
      {/* Logo text with hover animation */}
      <Box 
        sx={{ 
          display: 'flex', 
          alignItems: 'baseline',
          cursor: 'pointer',
          transition: 'all 0.3s ease',
          '&:hover': {
            transform: 'translateY(-1px)',
            '& .logo-text': {
              animation: `${textGlow} 2s ease-in-out infinite`,
            },
            '& .dots-container': {
              '& > div': {
                animationDuration: '1s !important',
              }
            }
          }
        }}
      >
        <Typography
          variant="h6"
          component="span"
          className="logo-text"
          sx={{
            fontFamily: '"Satoshi", system-ui, -apple-system, sans-serif',
            fontWeight: 600,
            fontSize: '1.25rem',
            letterSpacing: '-0.02em',
            color: currentTheme.primary,
            lineHeight: 1,
            transition: 'all 0.3s ease',
          }}
        >
          Vibe
        </Typography>
        <Typography
          variant="h6"
          component="span"
          className="logo-text"
          sx={{
            fontFamily: '"Satoshi", system-ui, -apple-system, sans-serif',
            fontWeight: 600,
            fontSize: '1.25rem',
            letterSpacing: '-0.02em',
            color: currentTheme.accent,
            lineHeight: 1,
            transition: 'all 0.3s ease',
          }}
        >
          Stream
        </Typography>
      </Box>
    </Box>
  );
};

export default Logo;
