// Configuration for API endpoints
// This allows the frontend to work with different domains while preserving ports

const getBaseUrl = (): string => {
  // In production, use the current domain
  // In development, fall back to localhost
  if (process.env.NODE_ENV === 'production') {
    return window.location.origin;
  }
  return 'http://localhost';
};

const getWebSocketUrl = (): string => {
  // In production, use the current domain with ws/wss protocol
  // In development, fall back to localhost
  if (process.env.NODE_ENV === 'production') {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    return `${protocol}//${window.location.hostname}`;
  }
  return 'ws://localhost';
};

export const API_CONFIG = {
  // HTTP API base URL (port 5050)
  API_BASE_URL: `${getBaseUrl()}:5050`,
  
  // WebSocket base URL (port 8080)
  WS_BASE_URL: `${getWebSocketUrl()}:8080`,
  
  // API endpoints
  ENDPOINTS: {
    // Auth endpoints
    LOGIN: '/api/auth/login',
    REGISTER: '/api/auth/register',
    LOGOUT: '/api/auth/logout',
    USERS: '/api/auth/users',
    
    // Video endpoints
    VIDEOS: '/api/videos',
    VIDEO_SEARCH: '/api/videos/search',
    VIDEO_BY_ID: '/api/videos',
    VIDEO_STREAM: '/api/videos',
    VIDEO_BY_TAG: '/api/videos/tag',
    
    // Thumbnail endpoint
    THUMBNAILS: '/api/thumbnails',
    
    // Comment endpoints
    COMMENTS: '/api/comments',
    
    // WebSocket endpoints
    WS_WATCHPARTY: '/api/ws/watchparty',
    WS_COMMENTS: '/api/ws/comments',
    
    // Watchparty endpoints
    WATCHPARTY_JOIN: '/api/watchparty'
  }
};

// Helper functions to build full URLs
export const buildApiUrl = (endpoint: string, ...params: string[]): string => {
  let url = `${API_CONFIG.API_BASE_URL}${endpoint}`;
  if (params.length > 0) {
    url += `/${params.join('/')}`;
  }
  return url;
};

export const buildWebSocketUrl = (endpoint: string, ...params: string[]): string => {
  let url = `${API_CONFIG.WS_BASE_URL}${endpoint}`;
  if (params.length > 0) {
    url += `/${params.join('/')}`;
  }
  return url;
};
