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
      fontFamily: '"Roboto", "Helvetica", "Arial", sans-serif',
      h1: {
        color: currentTheme.text,
      },
      h2: {
        color: currentTheme.text,
      },
      h3: {
        color: currentTheme.text,
      },
      h4: {
        color: currentTheme.text,
      },
      h5: {
        color: currentTheme.text,
      },
      h6: {
        color: currentTheme.text,
      },
      body1: {
        color: currentTheme.text,
      },
      body2: {
        color: currentTheme.textSecondary,
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
            backgroundColor: currentTheme.surface,
            color: currentTheme.text,
          },
        },
      },
      MuiCard: {
        styleOverrides: {
          root: {
            backgroundColor: currentTheme.surface,
            color: currentTheme.text,
          },
        },
      },
      MuiPaper: {
        styleOverrides: {
          root: {
            backgroundColor: currentTheme.surface,
            color: currentTheme.text,
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
