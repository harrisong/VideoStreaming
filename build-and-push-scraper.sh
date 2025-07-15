#!/bin/bash

# Build and Push Scraper Image to ECR
# This script builds the YouTube scraper Docker image and pushes it to AWS ECR

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
REGION="us-west-2"
ENVIRONMENT="prod"
IMAGE_NAME="video-streaming-scraper"

echo -e "${GREEN}🚀 Building and pushing YouTube scraper to ECR...${NC}"

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Failed to get AWS account ID. Make sure AWS CLI is configured.${NC}"
    exit 1
fi

# ECR repository URL
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ENVIRONMENT}-${IMAGE_NAME}"

echo -e "${YELLOW}📋 Configuration:${NC}"
echo "  Account ID: $ACCOUNT_ID"
echo "  Region: $REGION"
echo "  Environment: $ENVIRONMENT"
echo "  ECR Repository: $ECR_REPO"
echo ""

# Check if ECR repository exists
echo -e "${YELLOW}🔍 Checking if ECR repository exists...${NC}"
if ! aws ecr describe-repositories --repository-names "${ENVIRONMENT}-${IMAGE_NAME}" --region $REGION >/dev/null 2>&1; then
    echo -e "${RED}❌ ECR repository '${ENVIRONMENT}-${IMAGE_NAME}' not found.${NC}"
    echo -e "${YELLOW}💡 Make sure you've deployed the Terraform infrastructure first:${NC}"
    echo "  cd terraform && terraform apply"
    exit 1
fi

# Login to ECR
echo -e "${YELLOW}🔐 Logging in to ECR...${NC}"
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO

# Build the scraper image
echo -e "${YELLOW}🔨 Building scraper Docker image...${NC}"
cd youtube-scraper
docker build --platform linux/amd64 -t $IMAGE_NAME .

# Tag the image for ECR
echo -e "${YELLOW}🏷️  Tagging image for ECR...${NC}"
docker tag $IMAGE_NAME:latest $ECR_REPO:latest

# Push to ECR
echo -e "${YELLOW}📤 Pushing image to ECR...${NC}"
docker push $ECR_REPO:latest

# Verify the push
echo -e "${YELLOW}✅ Verifying image in ECR...${NC}"
aws ecr describe-images --repository-name "${ENVIRONMENT}-${IMAGE_NAME}" --region $REGION --query 'imageDetails[0].imageTags' --output table

echo -e "${GREEN}🎉 Successfully built and pushed scraper image!${NC}"
echo ""
echo -e "${YELLOW}📝 Next steps:${NC}"
echo "  1. Test the scraper API:"
echo "     curl -X POST https://YOUR_API_GATEWAY_URL/prod/scrape \\"
echo "       -H \"Content-Type: application/json\" \\"
echo "       -d '{\"youtube_url\":\"https://www.youtube.com/watch?v=dQw4w9WgXcQ\",\"user_id\":1}'"
echo ""
echo "  2. Monitor scraper logs:"
echo "     aws logs tail /ecs/${ENVIRONMENT}-video-streaming-scraper --follow"
echo ""
echo "  3. Check running tasks:"
echo "     aws ecs list-tasks --cluster ${ENVIRONMENT}-video-streaming"

cd ..
