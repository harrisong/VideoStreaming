#!/bin/bash

# Simplified Build and Push Script for AWS ECR
# Uses existing Dockerfiles with platform specification

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="us-west-2"
AWS_ACCOUNT_ID="339131303757"
ENVIRONMENT="prod"
PROJECT_NAME="video-streaming"

# ECR Repository URLs
BACKEND_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ENVIRONMENT}-${PROJECT_NAME}-backend"
FRONTEND_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ENVIRONMENT}-${PROJECT_NAME}-frontend"

echo -e "${GREEN}🚀 Building and pushing Docker images for AWS Fargate${NC}"
echo -e "${YELLOW}Cleaning up Docker to free space...${NC}"

# Clean up Docker to free space
docker system prune -f
docker builder prune -f

echo -e "${YELLOW}🔐 Logging into AWS ECR...${NC}"
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build and push backend using existing Dockerfile
echo -e "${GREEN}🔨 Building backend image...${NC}"
cd rust-backend

# Use the existing Dockerfile but specify platform during build
docker build --platform linux/amd64 -t ${BACKEND_REPO}:latest .
docker push ${BACKEND_REPO}:latest

echo -e "${GREEN}✅ Backend image pushed successfully${NC}"

# Build and push frontend using existing Dockerfile
echo -e "${GREEN}🔨 Building frontend image...${NC}"
cd ../frontend

# Use the existing Dockerfile but specify platform during build
docker build --platform linux/amd64 -t ${FRONTEND_REPO}:latest .
docker push ${FRONTEND_REPO}:latest

echo -e "${GREEN}✅ Frontend image pushed successfully${NC}"

cd ..

echo ""
echo -e "${GREEN}🎉 All images built and pushed successfully!${NC}"
echo -e "${YELLOW}Backend: ${BACKEND_REPO}:latest${NC}"
echo -e "${YELLOW}Frontend: ${FRONTEND_REPO}:latest${NC}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
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
