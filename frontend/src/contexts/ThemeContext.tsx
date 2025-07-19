import React, { createContext, useContext, useEffect, useState } from 'react';
import { buildApiUrl, API_CONFIG } from '../config';

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
}

const predefinedThemes: { [key: string]: Theme } = {
  youtube: {
    name: 'YouTube',
    primary: '#ff0000',
    secondary: '#cc0000',
    accent: '#ff4444',
    background: '#0f0f0f',
    surface: '#212121',
    text: '#ffffff',
    textSecondary: '#aaaaaa',
    plyrColor: '#ff0000'
  },
  pornhub: {
    name: 'Pornhub',
    primary: '#ff9000',
    secondary: '#e67e00',
    accent: '#ffb84d',
    background: '#000000',
    surface: '#1a1a1a',
    text: '#ffffff',
    textSecondary: '#cccccc',
    plyrColor: '#ff9000'
  },
  vimeo: {
    name: 'Vimeo',
    primary: '#1ab7ea',
    secondary: '#0099cc',
    accent: '#4dc8f0',
    background: '#1a1a1a',
    surface: '#2d2d2d',
    text: '#ffffff',
    textSecondary: '#b3b3b3',
    plyrColor: '#1ab7ea'
  },
  default: {
    name: 'Default',
    primary: '#4f46e5',
    secondary: '#3730a3',
    accent: '#6366f1',
    background: '#f9fafb',
    surface: '#ffffff',
    text: '#111827',
    textSecondary: '#6b7280',
    plyrColor: '#4f46e5'
  }
};

interface ThemeContextType {
  currentTheme: Theme;
  applyTheme: (theme: Theme | { name: string; isCustom?: boolean }) => void;
  loadUserTheme: () => Promise<void>;
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined);

export const useTheme = () => {
  const context = useContext(ThemeContext);
  if (!context) {
    throw new Error('useTheme must be used within a ThemeProvider');
  }
  return context;
};

interface ThemeProviderProps {
  children: React.ReactNode;
}

export const ThemeProvider: React.FC<ThemeProviderProps> = ({ children }) => {
  const [currentTheme, setCurrentTheme] = useState<Theme>(predefinedThemes.default);

  const applyTheme = (theme: Theme | { name: string; isCustom?: boolean }) => {
    const themeToApply = 'isCustom' in theme && theme.isCustom ? theme as Theme : predefinedThemes[theme.name] || predefinedThemes.default;
    
    const root = document.documentElement;
    root.style.setProperty('--theme-primary', themeToApply.primary);
    root.style.setProperty('--theme-secondary', themeToApply.secondary);
    root.style.setProperty('--theme-accent', themeToApply.accent);
    root.style.setProperty('--theme-background', themeToApply.background);
    root.style.setProperty('--theme-surface', themeToApply.surface);
    root.style.setProperty('--theme-text', themeToApply.text);
    root.style.setProperty('--theme-text-secondary', themeToApply.textSecondary);
    root.style.setProperty('--plyr-color-main', themeToApply.plyrColor);

    // Update body background
    document.body.style.backgroundColor = themeToApply.background;
    document.body.style.color = themeToApply.text;

    setCurrentTheme(themeToApply);
  };

  const loadUserTheme = async () => {
    try {
      const token = localStorage.getItem('token');
      if (!token) {
        applyTheme(predefinedThemes.default);
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
          applyTheme(theme);
        } else {
          applyTheme(predefinedThemes.default);
        }
      } else {
        applyTheme(predefinedThemes.default);
      }
    } catch (error) {
      console.error('Error loading user theme:', error);
      applyTheme(predefinedThemes.default);
    }
  };

  useEffect(() => {
    loadUserTheme();
  }, []);

  // Listen for login/logout events to reload theme
  useEffect(() => {
    const handleStorageChange = () => {
      loadUserTheme();
    };

    window.addEventListener('storage', handleStorageChange);
    return () => window.removeEventListener('storage', handleStorageChange);
  }, []);

  const value: ThemeContextType = {
    currentTheme,
    applyTheme,
    loadUserTheme
  };

  return (
    <ThemeContext.Provider value={value}>
      {children}
    </ThemeContext.Provider>
  );
};
