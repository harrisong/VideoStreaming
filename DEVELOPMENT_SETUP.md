# Development Setup

This document explains the development setup for the VideoStreaming application, specifically the frontend React development server configuration.

## Frontend Development Server

The docker-compose.yml has been configured to use the React development server instead of nginx for development purposes. This enables:

- **Hot Reload**: Changes to React components are automatically reflected in the browser
- **Fast Development**: No need to rebuild the entire Docker image for frontend changes
- **Live Debugging**: Better error messages and debugging capabilities

## Key Changes Made

### 1. Development Dockerfile (`frontend/Dockerfile.dev`)
- Uses Node.js Alpine image
- Installs all dependencies (including dev dependencies)
- Runs `npm start` to start the React development server
- Exposes port 3000 (React dev server default)

### 2. Docker Compose Configuration
- **Build Context**: Uses `frontend/Dockerfile.dev` instead of the production Dockerfile
- **Port Mapping**: Changed from `3000:80` to `3000:3000` to match React dev server
- **Volume Mounting**: Mounts source code directories for live reload:
  - `./frontend/src:/app/src` - React source code
  - `./frontend/public:/app/public` - Public assets
  - Configuration files (package.json, tsconfig.json, etc.)
- **Environment Variables**: Added polling options for file watching in Docker:
  - `CHOKIDAR_USEPOLLING=true`
  - `WATCHPACK_POLLING=true`

## Usage

### Starting the Development Environment

```bash
# Start all services including frontend with React dev server
docker-compose up

# Or start only the frontend service
docker-compose up frontend
```

### Accessing the Application

- **Frontend**: http://localhost:3000 (React development server)
- **Backend API**: http://localhost:5050
- **WebSocket**: http://localhost:8080

### Making Changes

1. Edit any file in `frontend/src/` or `frontend/public/`
2. Changes will be automatically detected and the browser will reload
3. No need to restart the Docker container

### Production vs Development

- **Development** (current setup): Uses React dev server with hot reload
- **Production** (`docker-compose.prod.yml`): Should use the original nginx-based setup

## File Structure

```
frontend/
├── Dockerfile          # Production build (nginx-based)
├── Dockerfile.dev      # Development build (React dev server)
├── nginx.conf          # Production nginx config
├── nginx.dev.conf      # Development nginx config (not used in dev mode)
├── package.json        # Dependencies and scripts
└── src/               # React source code (mounted as volume)
```

## Troubleshooting

### Hot Reload Not Working
If hot reload isn't working, ensure:
1. The volume mounts are correctly configured in docker-compose.yml
2. The polling environment variables are set
3. File permissions allow Docker to watch for changes

### Port Conflicts
If port 3000 is already in use:
1. Stop other services using port 3000
2. Or modify the port mapping in docker-compose.yml

### Performance Issues
The polling-based file watching may consume more CPU. This is normal for Docker-based development on some systems.
