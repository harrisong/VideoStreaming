import React from 'react';
import { Box, Typography } from '@mui/material';
import { PlayArrow } from '@mui/icons-material';
import { useTheme } from '../contexts/ThemeContext';

const Logo: React.FC<{ className?: string }> = ({ className = '' }) => {
  const { currentTheme } = useTheme();

  return (
    <Box 
      className={className}
      sx={{ 
        display: 'flex', 
        alignItems: 'center', 
        gap: 1.5,
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
        {/* Three subtle dots representing streaming/flow */}
        <Box
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
              opacity: 0.7,
            }}
          />
          <Box
            sx={{
              width: 4,
              height: 4,
              borderRadius: '50%',
              background: `linear-gradient(45deg, ${currentTheme.primary}70, ${currentTheme.accent}50)`,
              opacity: 0.8,
            }}
          />
          <Box
            sx={{
              width: 3,
              height: 3,
              borderRadius: '50%',
              background: `linear-gradient(45deg, ${currentTheme.primary}60, ${currentTheme.accent}40)`,
              opacity: 0.7,
            }}
          />
        </Box>
      </Box>
      
      {/* Logo text */}
      <Box sx={{ display: 'flex', alignItems: 'baseline' }}>
        <Typography
          variant="h6"
          component="span"
          sx={{
            fontFamily: '"Satoshi", system-ui, -apple-system, sans-serif',
            fontWeight: 600,
            fontSize: '1.25rem',
            letterSpacing: '-0.02em',
            color: currentTheme.primary,
            lineHeight: 1,
          }}
        >
          Vibe
        </Typography>
        <Typography
          variant="h6"
          component="span"
          sx={{
            fontFamily: '"Satoshi", system-ui, -apple-system, sans-serif',
            fontWeight: 600,
            fontSize: '1.25rem',
            letterSpacing: '-0.02em',
            color: currentTheme.accent,
            lineHeight: 1,
          }}
        >
          Stream
        </Typography>
      </Box>
    </Box>
  );
};

export default Logo;
