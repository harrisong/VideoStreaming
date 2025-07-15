#!/bin/bash

# Optimized Build and Push Script for AWS ECR
# Uses Docker layer caching to avoid rebuilding unchanged dependencies

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="us-west-2"
AWS_ACCOUNT_ID="339131303757"
ENVIRONMENT="prod"
PROJECT_NAME="video-streaming"

# ECR Repository URLs
BACKEND_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ENVIRONMENT}-${PROJECT_NAME}-backend"
FRONTEND_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ENVIRONMENT}-${PROJECT_NAME}-frontend"

# Function to check if file has changed since last build
check_changes() {
    local service=$1
    local dockerfile_path=$2
    local context_path=$3
    
    # Create cache directory if it doesn't exist
    mkdir -p .build-cache
    
    # Generate hash of relevant files
    local current_hash=""
    if [ "$service" = "backend" ]; then
        # For Rust backend: hash Cargo.toml, Cargo.lock, src/, migrations/, and Dockerfile
        current_hash=$(find "$context_path" -name "Cargo.toml" -o -name "Cargo.lock" -o -name "Dockerfile" | sort | xargs cat 2>/dev/null | md5sum | cut -d' ' -f1)
        src_hash=$(find "$context_path/src" -name "*.rs" 2>/dev/null | sort | xargs cat 2>/dev/null | md5sum | cut -d' ' -f1)
        migrations_hash=$(find "$context_path/migrations" -name "*.sql" 2>/dev/null | sort | xargs cat 2>/dev/null | md5sum | cut -d' ' -f1)
        current_hash=$(echo "${current_hash}${src_hash}${migrations_hash}" | md5sum | cut -d' ' -f1)
    elif [ "$service" = "frontend" ]; then
        # For React frontend: hash package.json, package-lock.json, src/, public/, and Dockerfile
        current_hash=$(find "$context_path" -name "package*.json" -o -name "Dockerfile" -o -name "*.config.js" -o -name "tsconfig.json" | sort | xargs cat 2>/dev/null | md5sum | cut -d' ' -f1)
        src_hash=$(find "$context_path/src" -name "*.tsx" -o -name "*.ts" -o -name "*.css" 2>/dev/null | sort | xargs cat 2>/dev/null | md5sum | cut -d' ' -f1)
        public_hash=$(find "$context_path/public" -type f 2>/dev/null | sort | xargs cat 2>/dev/null | md5sum | cut -d' ' -f1)
        current_hash=$(echo "${current_hash}${src_hash}${public_hash}" | md5sum | cut -d' ' -f1)
    fi
    
    local cache_file=".build-cache/${service}_hash"
    local previous_hash=""
    
    if [ -f "$cache_file" ]; then
        previous_hash=$(cat "$cache_file")
    fi
    
    # Store current hash
    echo "$current_hash" > "$cache_file"
    
    # Return 0 if changed, 1 if unchanged
    if [ "$current_hash" != "$previous_hash" ]; then
        return 0  # Changed
    else
        return 1  # Unchanged
    fi
}

# Function to build and push with caching
build_and_push() {
    local service=$1
    local repo=$2
    local context_path=$3
    local force_build=${4:-false}
    
    echo -e "${BLUE}🔍 Checking if $service needs rebuilding...${NC}"
    
    if [ "$force_build" = "true" ] || check_changes "$service" "$context_path/Dockerfile" "$context_path"; then
        echo -e "${GREEN}🔨 Building $service image (changes detected)...${NC}"
        
        cd "$context_path"
        
        # Build with cache-from to reuse layers from previous builds
        docker build \
            --platform linux/amd64 \
            --cache-from ${repo}:latest \
            --cache-from ${repo}:cache \
            -t ${repo}:latest \
            -t ${repo}:cache \
            .
        
        # Push both tags
        docker push ${repo}:latest
        docker push ${repo}:cache
        
        echo -e "${GREEN}✅ $service image built and pushed successfully${NC}"
        cd - > /dev/null
        return 0
    else
        echo -e "${YELLOW}⏭️  Skipping $service build (no changes detected)${NC}"
        
        # Still need to ensure the latest tag exists in ECR
        # Try to pull and re-tag if needed
        if docker pull ${repo}:latest 2>/dev/null; then
            echo -e "${BLUE}ℹ️  Using existing $service image from registry${NC}"
        else
            echo -e "${YELLOW}⚠️  No existing image found, forcing rebuild...${NC}"
            build_and_push "$service" "$repo" "$context_path" "true"
        fi
        return 1
    fi
}

# Function to clean only dangling images and containers
selective_cleanup() {
    echo -e "${YELLOW}🧹 Performing selective cleanup...${NC}"
    
    # Remove only dangling images (untagged)
    docker image prune -f
    
    # Remove stopped containers
    docker container prune -f
    
    # Remove unused networks
    docker network prune -f
    
    # Remove unused volumes (be careful with this)
    docker volume prune -f
    
    # Don't remove build cache - this is key for faster builds!
    echo -e "${GREEN}✅ Selective cleanup completed (build cache preserved)${NC}"
}

echo -e "${GREEN}🚀 Optimized Build and Push for AWS Fargate${NC}"

# Perform selective cleanup instead of full system prune
selective_cleanup

echo -e "${YELLOW}🔐 Logging into AWS ECR...${NC}"
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Try to pull existing cache images for better layer reuse
echo -e "${BLUE}📥 Pulling existing images for cache...${NC}"
docker pull ${BACKEND_REPO}:cache 2>/dev/null || echo "No backend cache image found"
docker pull ${FRONTEND_REPO}:cache 2>/dev/null || echo "No frontend cache image found"

# Build and push services
backend_built=$(build_and_push "backend" "$BACKEND_REPO" "rust-backend" && echo "true" || echo "false")
frontend_built=$(build_and_push "frontend" "$FRONTEND_REPO" "frontend" && echo "true" || echo "false")

echo ""
echo -e "${GREEN}🎉 Build process completed!${NC}"
echo -e "${YELLOW}Backend: ${BACKEND_REPO}:latest $([ "$backend_built" = "true" ] && echo "(rebuilt)" || echo "(cached)")${NC}"
echo -e "${YELLOW}Frontend: ${FRONTEND_REPO}:latest $([ "$frontend_built" = "true" ] && echo "(rebuilt)" || echo "(cached)")${NC}"

# Only suggest ECS update if something was actually built
if [ "$backend_built" = "true" ] || [ "$frontend_built" = "true" ]; then
    echo ""
    echo -e "${GREEN}Next steps (new deployment needed):${NC}"
    echo "1. Update ECS service:"
    echo "   aws ecs update-service --cluster ${ENVIRONMENT}-${PROJECT_NAME} --service ${ENVIRONMENT}-${PROJECT_NAME} --force-new-deployment --region ${AWS_REGION}"
    echo ""
    echo "2. Monitor deployment:"
    echo "   aws ecs describe-services --cluster ${ENVIRONMENT}-${PROJECT_NAME} --services ${ENVIRONMENT}-${PROJECT_NAME} --region ${AWS_REGION}"
    echo ""
    echo "3. Check logs:"
    echo "   aws logs tail /ecs/${ENVIRONMENT}-${PROJECT_NAME} --follow --region ${AWS_REGION}"
    echo ""
    echo "4. Test your application:"
    echo "   curl -I https://stream.harrisonng.dev"
else
    echo ""
    echo -e "${BLUE}ℹ️  No changes detected - no deployment needed${NC}"
    echo "Your application is already up to date!"
fi

echo ""
echo -e "${GREEN}💡 Pro tip: This script preserves Docker build cache for faster subsequent builds!${NC}"
