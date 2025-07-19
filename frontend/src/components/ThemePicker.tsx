import React, { useState, useEffect } from 'react';
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

interface ThemePickerProps {
  isOpen: boolean;
  onClose: () => void;
}

const ThemePicker: React.FC<ThemePickerProps> = ({ isOpen, onClose }) => {
  const { applyTheme } = useTheme();
  const [selectedTheme, setSelectedTheme] = useState<string>('default');
  const [customTheme, setCustomTheme] = useState<Theme>(predefinedThemes.default);
  const [isCustomMode, setIsCustomMode] = useState(false);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (isOpen) {
      loadUserSettings();
    }
  }, [isOpen]);

  const loadUserSettings = async () => {
    try {
      const token = localStorage.getItem('token');
      if (!token) return;

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
            setIsCustomMode(true);
            setCustomTheme(theme);
            setSelectedTheme('custom');
          } else {
            setSelectedTheme(theme.name || 'default');
            setIsCustomMode(false);
          }
          applyTheme(theme);
        }
      }
    } catch (error) {
      console.error('Error loading user settings:', error);
    }
  };


  const saveTheme = async () => {
    setLoading(true);
    try {
      const token = localStorage.getItem('token');
      if (!token) {
        alert('Please log in to save theme settings');
        return;
      }

      const themeData = isCustomMode ? { ...customTheme, isCustom: true } : { name: selectedTheme };

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
        alert('Failed to save theme settings');
      }
    } catch (error) {
      console.error('Error saving theme:', error);
      alert('Error saving theme settings');
    } finally {
      setLoading(false);
    }
  };

  const handleThemeSelect = (themeName: string) => {
    setSelectedTheme(themeName);
    setIsCustomMode(false);
    applyTheme(predefinedThemes[themeName]);
  };

  const handleCustomThemeChange = (field: keyof Theme, value: string) => {
    const updatedTheme = { ...customTheme, [field]: value };
    setCustomTheme(updatedTheme);
    applyTheme(updatedTheme);
  };

  const switchToCustomMode = () => {
    setIsCustomMode(true);
    setSelectedTheme('custom');
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg p-6 max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto">
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-2xl font-bold text-gray-900">Theme Settings</h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600"
          >
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {!isCustomMode ? (
          <div>
            <h3 className="text-lg font-semibold mb-4">Predefined Themes</h3>
            <div className="grid grid-cols-2 gap-4 mb-6">
              {Object.entries(predefinedThemes).map(([key, theme]) => (
                <button
                  key={key}
                  onClick={() => handleThemeSelect(key)}
                  className={`p-4 rounded-lg border-2 transition-all ${
                    selectedTheme === key
                      ? 'border-blue-500 bg-blue-50'
                      : 'border-gray-200 hover:border-gray-300'
                  }`}
                >
                  <div className="flex items-center space-x-3">
                    <div
                      className="w-8 h-8 rounded-full"
                      style={{ backgroundColor: theme.primary }}
                    />
                    <span className="font-medium">{theme.name}</span>
                  </div>
                  <div className="flex space-x-1 mt-2">
                    <div className="w-4 h-4 rounded" style={{ backgroundColor: theme.primary }} />
                    <div className="w-4 h-4 rounded" style={{ backgroundColor: theme.secondary }} />
                    <div className="w-4 h-4 rounded" style={{ backgroundColor: theme.accent }} />
                    <div className="w-4 h-4 rounded" style={{ backgroundColor: theme.surface }} />
                  </div>
                </button>
              ))}
            </div>

            <button
              onClick={switchToCustomMode}
              className="w-full p-3 border-2 border-dashed border-gray-300 rounded-lg text-gray-600 hover:border-gray-400 hover:text-gray-800 transition-colors"
            >
              + Create Custom Theme
            </button>
          </div>
        ) : (
          <div>
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-lg font-semibold">Custom Theme</h3>
              <button
                onClick={() => setIsCustomMode(false)}
                className="text-blue-600 hover:text-blue-800"
              >
                ← Back to Presets
              </button>
            </div>

            <div className="grid grid-cols-2 gap-4">
              {Object.entries(customTheme).map(([key, value]) => {
                if (key === 'name') return null;
                return (
                  <div key={key}>
                    <label className="block text-sm font-medium text-gray-700 mb-1 capitalize">
                      {key.replace(/([A-Z])/g, ' $1').trim()}
                    </label>
                    <div className="flex space-x-2">
                      <input
                        type="color"
                        value={value}
                        onChange={(e) => handleCustomThemeChange(key as keyof Theme, e.target.value)}
                        className="w-12 h-10 rounded border border-gray-300"
                      />
                      <input
                        type="text"
                        value={value}
                        onChange={(e) => handleCustomThemeChange(key as keyof Theme, e.target.value)}
                        className="flex-1 px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        <div className="flex justify-end space-x-3 mt-6">
          <button
            onClick={onClose}
            className="px-4 py-2 text-gray-600 hover:text-gray-800"
          >
            Cancel
          </button>
          <button
            onClick={saveTheme}
            disabled={loading}
            className="px-6 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:opacity-50"
          >
            {loading ? 'Saving...' : 'Save Theme'}
          </button>
        </div>
      </div>
    </div>
  );
};

export default ThemePicker;
