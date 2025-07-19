import React from 'react';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import { useTheme } from './ThemeContext';

interface MuiThemeProviderProps {
  children: React.ReactNode;
}

export const MuiThemeProvider: React.FC<MuiThemeProviderProps> = ({ children }) => {
  const { currentTheme } = useTheme();

  const muiTheme = createTheme({
    palette: {
      mode: currentTheme.background === '#f9fafb' ? 'light' : 'dark',
      primary: {
        main: currentTheme.primary,
        dark: currentTheme.secondary,
        light: currentTheme.accent,
      },
      secondary: {
        main: currentTheme.accent,
      },
      background: {
        default: currentTheme.background,
        paper: currentTheme.surface,
      },
      text: {
        primary: currentTheme.text,
        secondary: currentTheme.textSecondary,
      },
    },
    typography: {
      fontFamily: '"Satoshi", -apple-system, BlinkMacSystemFont, "Segoe UI", "Roboto", "Oxygen", "Ubuntu", "Cantarell", sans-serif',
      h1: {
        color: currentTheme.text,
        fontWeight: 700,
        letterSpacing: '-0.025em',
      },
      h2: {
        color: currentTheme.text,
        fontWeight: 700,
        letterSpacing: '-0.025em',
      },
      h3: {
        color: currentTheme.text,
        fontWeight: 600,
        letterSpacing: '-0.02em',
      },
      h4: {
        color: currentTheme.text,
        fontWeight: 600,
        letterSpacing: '-0.02em',
      },
      h5: {
        color: currentTheme.text,
        fontWeight: 600,
        letterSpacing: '-0.01em',
      },
      h6: {
        color: currentTheme.text,
        fontWeight: 600,
        letterSpacing: '-0.01em',
      },
      body1: {
        color: currentTheme.text,
        fontWeight: 400,
        lineHeight: 1.6,
      },
      body2: {
        color: currentTheme.textSecondary,
        fontWeight: 400,
        lineHeight: 1.5,
      },
      button: {
        fontWeight: 500,
        letterSpacing: '0.01em',
        textTransform: 'none',
      },
      caption: {
        fontWeight: 400,
        letterSpacing: '0.01em',
      },
    },
    components: {
      MuiCssBaseline: {
        styleOverrides: {
          body: {
            backgroundColor: currentTheme.background,
            color: currentTheme.text,
          },
        },
      },
      MuiAppBar: {
        styleOverrides: {
          root: {
            backgroundColor: `${currentTheme.surface}E6`, // 90% opacity
            backdropFilter: 'blur(15px)',
            border: `1px solid ${currentTheme.text}20`,
            boxShadow: '0 4px 20px rgba(0, 0, 0, 0.1)',
            color: currentTheme.text,
          },
        },
      },
      MuiCard: {
        styleOverrides: {
          root: {
            backgroundColor: `${currentTheme.surface}CC`, // 80% opacity
            backdropFilter: 'blur(10px)',
            border: `1px solid ${currentTheme.text}20`, // 12% opacity border
            color: currentTheme.text,
            boxShadow: '0 8px 32px rgba(0, 0, 0, 0.1)',
          },
        },
      },
      MuiPaper: {
        styleOverrides: {
          root: {
            backgroundColor: `${currentTheme.surface}CC`, // 80% opacity
            backdropFilter: 'blur(10px)',
            border: `1px solid ${currentTheme.text}20`, // 12% opacity border
            color: currentTheme.text,
            boxShadow: '0 8px 32px rgba(0, 0, 0, 0.1)',
          },
        },
      },
      MuiDialog: {
        styleOverrides: {
          paper: {
            backgroundColor: `${currentTheme.surface}F0`, // 94% opacity
            backdropFilter: 'blur(20px)',
            border: `1px solid ${currentTheme.text}30`, // 18% opacity border
          },
        },
      },
      MuiButton: {
        styleOverrides: {
          root: {
            textTransform: 'none',
          },
        },
      },
    },
  });

  return (
    <ThemeProvider theme={muiTheme}>
      <CssBaseline />
      {children}
    </ThemeProvider>
  );
};
