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
  isDark?: boolean;
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
    plyrColor: '#ff0000',
    isDark: true
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
    plyrColor: '#ff9000',
    isDark: true
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
    plyrColor: '#1ab7ea',
    isDark: true
  },
  default: {
    name: 'Default Light',
    primary: '#4f46e5',
    secondary: '#3730a3',
    accent: '#6366f1',
    background: '#f9fafb',
    surface: '#ffffff',
    text: '#111827',
    textSecondary: '#6b7280',
    plyrColor: '#4f46e5',
    isDark: false
  },
  defaultDark: {
    name: 'Default Dark',
    primary: '#6366f1',
    secondary: '#4f46e5',
    accent: '#8b5cf6',
    background: '#0f0f23',
    surface: '#1e1e2e',
    text: '#ffffff',
    textSecondary: '#a1a1aa',
    plyrColor: '#6366f1',
    isDark: true
  },
  system: {
    name: 'System',
    primary: '#4f46e5',
    secondary: '#3730a3',
    accent: '#6366f1',
    background: '#f9fafb',
    surface: '#ffffff',
    text: '#111827',
    textSecondary: '#6b7280',
    plyrColor: '#4f46e5',
    isDark: false
  }
};

interface ThemeContextType {
  currentTheme: Theme;
  applyTheme: (theme: Theme | { name: string; isCustom?: boolean }) => void;
  loadUserTheme: () => Promise<void>;
  predefinedThemes: { [key: string]: Theme };
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
  const [systemPrefersDark, setSystemPrefersDark] = useState(false);

  // Detect system theme preference
  useEffect(() => {
    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
    setSystemPrefersDark(mediaQuery.matches);

    const handleChange = (e: MediaQueryListEvent) => {
      setSystemPrefersDark(e.matches);
      // If user is using system theme, update automatically
      const savedTheme = localStorage.getItem('selectedTheme');
      if (savedTheme === 'system') {
        applySystemTheme();
      }
    };

    mediaQuery.addEventListener('change', handleChange);
    return () => mediaQuery.removeEventListener('change', handleChange);
  }, []);

  const applySystemTheme = () => {
    const systemTheme = systemPrefersDark ? predefinedThemes.defaultDark : predefinedThemes.default;
    applyThemeInternal(systemTheme);
  };

  const applyThemeInternal = (themeToApply: Theme) => {
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

  const applyTheme = (theme: Theme | { name: string; isCustom?: boolean }) => {
    let themeToApply: Theme;
    
    if ('isCustom' in theme && theme.isCustom) {
      themeToApply = theme as Theme;
    } else {
      const themeName = theme.name;
      if (themeName === 'system') {
        themeToApply = systemPrefersDark ? predefinedThemes.defaultDark : predefinedThemes.default;
      } else {
        themeToApply = predefinedThemes[themeName] || predefinedThemes.default;
      }
    }

    applyThemeInternal(themeToApply);

    // Save theme preference to localStorage for non-logged-in users
    const token = localStorage.getItem('token');
    if (!token) {
      localStorage.setItem('selectedTheme', theme.name);
    }
  };

  const loadUserTheme = async () => {
    try {
      const token = localStorage.getItem('token');
      
      if (!token) {
        // For non-logged-in users, load from localStorage or use system default
        const savedTheme = localStorage.getItem('selectedTheme');
        if (savedTheme) {
          if (savedTheme === 'system') {
            applySystemTheme();
          } else {
            applyTheme({ name: savedTheme });
          }
        } else {
          // Default to system theme for new users
          localStorage.setItem('selectedTheme', 'system');
          applySystemTheme();
        }
        return;
      }

      // For logged-in users, load from server
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
          // Default to system theme if no user preference
          applySystemTheme();
        }
      } else {
        applySystemTheme();
      }
    } catch (error) {
      console.error('Error loading user theme:', error);
      applySystemTheme();
    }
  };

  useEffect(() => {
    loadUserTheme();
  }, [systemPrefersDark]);

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
    loadUserTheme,
    predefinedThemes
  };

  return (
    <ThemeContext.Provider value={value}>
      {children}
    </ThemeContext.Provider>
  );
};
