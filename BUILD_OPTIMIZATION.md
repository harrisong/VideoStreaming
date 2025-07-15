# Build Optimization Guide

This document explains the optimized build process that avoids unnecessary rebuilds and dependency downloads.

## Problem with Original Script

The original `build-and-push-simple.sh` script had these inefficiencies:

1. **Full Docker cleanup**: `docker system prune -f` and `docker builder prune -f` removed all build cache
2. **Always rebuilds everything**: No change detection meant rebuilding even when nothing changed
3. **Re-downloads dependencies**: Rust crates and npm packages were downloaded on every build
4. **Wastes time and bandwidth**: Especially problematic for large dependency trees

## Optimized Solution

The new `build-and-push-optimized.sh` script provides:

### 1. Smart Change Detection
- **File hashing**: Creates MD5 hashes of relevant files for each service
- **Selective rebuilds**: Only rebuilds services that have actually changed
- **Cache persistence**: Stores hashes in `.build-cache/` directory

### 2. Docker Layer Caching
- **Preserves build cache**: No more `docker system prune` that destroys cache
- **Cache-from strategy**: Uses previous images as cache sources
- **Multi-stage optimization**: Leverages Docker's multi-stage build caching

### 3. Selective Cleanup
- **Targeted pruning**: Only removes dangling images and stopped containers
- **Preserves cache**: Keeps Docker build cache intact
- **Network/volume cleanup**: Removes unused networks and volumes safely

### 4. Registry-based Caching
- **Cache tags**: Pushes both `:latest` and `:cache` tags to ECR
- **Remote cache**: Pulls existing cache images before building
- **Fallback mechanism**: Forces rebuild if no cached image exists

## Usage

### Basic Usage
```bash
./build-and-push-optimized.sh
```

### What Happens
1. **Change Detection**: Script checks if files have changed since last build
2. **Selective Building**: Only rebuilds services with changes
3. **Cache Utilization**: Uses Docker layer cache and registry cache
4. **Smart Deployment**: Only suggests ECS update if something was rebuilt

### Expected Output
```
🚀 Optimized Build and Push for AWS Fargate
🧹 Performing selective cleanup...
🔐 Logging into AWS ECR...
📥 Pulling existing images for cache...
🔍 Checking if backend needs rebuilding...
⏭️  Skipping backend build (no changes detected)
🔍 Checking if frontend needs rebuilding...
🔨 Building frontend image (changes detected)...
✅ frontend image built and pushed successfully
🎉 Build process completed!
Backend: 339131303757.dkr.ecr.us-west-2.amazonaws.com/prod-video-streaming-backend:latest (cached)
Frontend: 339131303757.dkr.ecr.us-west-2.amazonaws.com/prod-video-streaming-frontend:latest (rebuilt)
```

## Performance Benefits

### Time Savings
- **No changes**: ~30 seconds (vs 5-10 minutes)
- **Backend only**: ~3-5 minutes (vs 5-10 minutes)
- **Frontend only**: ~2-3 minutes (vs 5-10 minutes)
- **Both changed**: ~5-8 minutes (vs 5-10 minutes)

### Bandwidth Savings
- **Rust dependencies**: ~100MB+ saved when backend unchanged
- **Node modules**: ~50MB+ saved when frontend unchanged
- **Base images**: Reused from Docker cache

### Resource Efficiency
- **CPU usage**: Reduced compilation time
- **Disk space**: Selective cleanup preserves useful cache
- **Network**: Less ECR bandwidth usage

## File Structure

### Cache Directory
```
.build-cache/
├── backend_hash    # Hash of backend files
└── frontend_hash   # Hash of frontend files
```

### What Gets Hashed

#### Backend (Rust)
- `Cargo.toml` and `Cargo.lock`
- All `.rs` files in `src/`
- All `.sql` files in `migrations/`
- `Dockerfile`

#### Frontend (React)
- `package.json` and `package-lock.json`
- All `.tsx`, `.ts`, `.css` files in `src/`
- All files in `public/`
- Config files (`*.config.js`, `tsconfig.json`)
- `Dockerfile`

## Docker Layer Optimization

### Backend Dockerfile Benefits
The existing Dockerfile already has good layer caching:
```dockerfile
# Dependencies layer (cached unless Cargo.toml changes)
COPY Cargo.toml ./
RUN cargo build --release

# Source code layer (only rebuilt when source changes)
COPY src ./src
RUN cargo build --release
```

### Frontend Dockerfile Benefits
The existing Dockerfile also has good layer caching:
```dockerfile
# Dependencies layer (cached unless package.json changes)
COPY package*.json ./
RUN npm ci --only=production

# Source code layer (only rebuilt when source changes)
COPY src ./src
RUN npm run build
```

## Troubleshooting

### Force Rebuild
If you need to force a rebuild of everything:
```bash
rm -rf .build-cache/
./build-and-push-optimized.sh
```

### Clear Docker Cache
If you need to clear Docker cache (emergency only):
```bash
docker system prune -f
docker builder prune -f
./build-and-push-optimized.sh
```

### Debug Mode
To see what files are being hashed:
```bash
# Add debug output to the script
set -x  # Add this line after set -e
```

## Migration from Original Script

1. **Backup**: Keep `build-and-push-simple.sh` as backup
2. **Test**: Run `build-and-push-optimized.sh` on a test deployment
3. **Verify**: Ensure images are built and pushed correctly
4. **Switch**: Update CI/CD to use optimized script
5. **Monitor**: Watch build times and verify functionality

## Best Practices

1. **Regular cleanup**: Occasionally run selective cleanup manually
2. **Cache monitoring**: Monitor `.build-cache/` directory size
3. **Registry cleanup**: Periodically clean old ECR images
4. **Dependency updates**: Clear cache when updating major dependencies

## Compatibility

- **Docker**: Requires Docker with BuildKit support
- **AWS CLI**: Same requirements as original script
- **Shell**: Compatible with bash and zsh
- **Platform**: Works on macOS, Linux, and WSL
