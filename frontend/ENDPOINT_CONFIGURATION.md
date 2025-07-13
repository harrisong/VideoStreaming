# Frontend Endpoint Configuration

## Overview

This document describes the changes made to remove hardcoded localhost endpoints from the frontend application, making it ready for deployment with custom domains while preserving the required ports (5050 and 8080).

## Changes Made

### 1. Created Configuration File (`src/config.ts`)

A centralized configuration file was created to manage all API endpoints:

- **Dynamic URL Generation**: Automatically detects production vs development environment
- **Port Preservation**: Maintains ports 5050 (HTTP API) and 8080 (WebSocket) as required
- **Protocol Detection**: Automatically switches between HTTP/HTTPS and WS/WSS based on the current domain
- **Helper Functions**: Provides `buildApiUrl()` and `buildWebSocketUrl()` for easy URL construction

### 2. Environment-Based URL Resolution

**Development Mode** (`NODE_ENV !== 'production'`):
- HTTP API: `http://localhost:5050`
- WebSocket: `ws://localhost:8080`

**Production Mode** (`NODE_ENV === 'production'`):
- HTTP API: `{current-domain}:5050` (e.g., `https://yourdomain.com:5050`)
- WebSocket: `{ws/wss}://{current-domain}:8080` (e.g., `wss://yourdomain.com:8080`)

### 3. Updated Components

The following components were updated to use the configuration:

1. **UserList.tsx** - User authentication endpoints
2. **VideoPlayer.tsx** - Video streaming, watchparty, and WebSocket endpoints
3. **Register.tsx** - User registration endpoint
4. **CommentSection.tsx** - Comment API and WebSocket endpoints
5. **Home.tsx** - Video listing, search, and thumbnail endpoints
6. **Login.tsx** - User authentication endpoint
7. **TagVideos.tsx** - Tag-based video filtering and thumbnail endpoints
8. **Navbar.tsx** - Logout endpoint

### 4. Endpoint Mapping

All endpoints are now centrally defined in the configuration:

```typescript
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
  
  // Other endpoints...
}
```

## Benefits

1. **Domain Flexibility**: Can be deployed on any domain without code changes
2. **Port Preservation**: Maintains required ports 5050 and 8080
3. **Environment Awareness**: Automatically adapts to development vs production
4. **Centralized Management**: All endpoints managed in one location
5. **Protocol Security**: Automatically uses HTTPS/WSS in production when available
6. **Easy Maintenance**: Changes to endpoints only need to be made in one file

## Deployment Notes

When deploying to a production domain:

1. Ensure your domain serves the frontend with `NODE_ENV=production`
2. Configure your server to handle requests on ports 5050 and 8080
3. Set up SSL certificates if using HTTPS (recommended)
4. The frontend will automatically detect the domain and construct appropriate URLs

## Example URLs

**Development**:
- API: `http://localhost:5050/api/videos`
- WebSocket: `ws://localhost:8080/api/ws/comments/123`

**Production** (example with `yourdomain.com`):
- API: `https://yourdomain.com:5050/api/videos`
- WebSocket: `wss://yourdomain.com:8080/api/ws/comments/123`

The configuration automatically handles the protocol selection and domain detection.
