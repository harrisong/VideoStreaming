#!/bin/bash

# Rebuild and push the scraper image with cookies support

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔨 Rebuilding scraper image with cookies support...${NC}"

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not configured or credentials invalid${NC}"
    echo "Please set your AWS credentials"
    exit 1
fi

# Get ECR registry URL
ECR_REGISTRY=$(aws ecr describe-repositories --repository-names prod-video-streaming-scraper --region us-west-2 --query 'repositories[0].repositoryUri' --output text 2>/dev/null | cut -d'/' -f1)

if [ -z "$ECR_REGISTRY" ]; then
    echo -e "${RED}❌ Could not get ECR registry URL${NC}"
    exit 1
fi

echo -e "${YELLOW}ECR Registry: $ECR_REGISTRY${NC}"

# Login to ECR
echo -e "${YELLOW}Logging into ECR...${NC}"
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin "$ECR_REGISTRY"

# Build the scraper image
echo -e "${YELLOW}Building scraper image for AMD64 platform...${NC}"
cd youtube-scraper
docker build --platform linux/amd64 -t "${ECR_REGISTRY}/prod-video-streaming-scraper:latest" .

# Push the image
echo -e "${YELLOW}Pushing scraper image to ECR...${NC}"
docker push "${ECR_REGISTRY}/prod-video-streaming-scraper:latest"

cd ..

echo -e "${GREEN}✅ Scraper image rebuilt and pushed successfully!${NC}"
echo ""
echo -e "${BLUE}🎬 You can now use the scraper with cookies:${NC}"
echo "./scrape-video-eks.sh 'https://www.youtube.com/watch?v=YOUR_VIDEO_ID'"
echo ""
echo -e "${YELLOW}The scraper now supports:${NC}"
echo "✅ Cookie extraction from Chrome, Firefox, Safari, Edge"
echo "✅ Automatic cookie passing to yt-dlp in EKS"
echo "✅ Secure cookie handling via Kubernetes ConfigMaps"
echo "✅ Automatic cleanup after job completion"
