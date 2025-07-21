#!/bin/bash

# Build and push sidecar containers for ECS Fargate deployment
# Make sure to set these environment variables:
# - AWS_ACCOUNT_ID: Your AWS account ID
# - AWS_REGION: Your AWS region (e.g., us-west-2)
# - ECR_REGISTRY: Your ECR registry URL

set -e

# Check required environment variables
if [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_REGION" ] || [ -z "$ECR_REGISTRY" ]; then
    echo "Error: Please set AWS_ACCOUNT_ID, AWS_REGION, and ECR_REGISTRY environment variables"
    echo "Example:"
    echo "export AWS_ACCOUNT_ID=123456789012"
    echo "export AWS_REGION=us-west-2"
    echo "export ECR_REGISTRY=123456789012.dkr.ecr.us-west-2.amazonaws.com"
    exit 1
fi

echo "Building and pushing sidecar containers..."

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# Create ECR repositories if they don't exist (only for active deployment)
echo "Creating ECR repositories if they don't exist..."
ENVIRONMENT=${ENVIRONMENT:-prod}

# Only create repositories that are actually used (no sidecar repos for EKS)
aws ecr describe-repositories --repository-names "${ENVIRONMENT}-video-streaming-backend" --region $AWS_REGION --output text >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "${ENVIRONMENT}-video-streaming-backend" --region $AWS_REGION --output text >/dev/null

aws ecr describe-repositories --repository-names "${ENVIRONMENT}-video-streaming-frontend" --region $AWS_REGION --output text >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "${ENVIRONMENT}-video-streaming-frontend" --region $AWS_REGION --output text >/dev/null

aws ecr describe-repositories --repository-names "${ENVIRONMENT}-video-streaming-scraper" --region $AWS_REGION --output text >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "${ENVIRONMENT}-video-streaming-scraper" --region $AWS_REGION --output text >/dev/null

# Build and push backend
echo "Building backend container..."
docker build --platform linux/amd64 -t rust-backend:latest ./rust-backend/
docker tag rust-backend:latest $ECR_REGISTRY/${ENVIRONMENT}-video-streaming-backend:latest
echo "Pushing backend container..."
docker push $ECR_REGISTRY/${ENVIRONMENT}-video-streaming-backend:latest

# Build and push frontend (standalone, not sidecar)
echo "Building frontend container..."
docker build --platform linux/amd64 -f ./frontend/Dockerfile -t frontend:latest ./frontend/
docker tag frontend:latest $ECR_REGISTRY/${ENVIRONMENT}-video-streaming-frontend:latest
echo "Pushing frontend container..."
docker push $ECR_REGISTRY/${ENVIRONMENT}-video-streaming-frontend:latest

# Build and push scraper
echo "Building scraper container..."
docker build --platform linux/amd64 -t youtube-scraper:latest ./youtube-scraper/
docker tag youtube-scraper:latest $ECR_REGISTRY/${ENVIRONMENT}-video-streaming-scraper:latest
echo "Pushing scraper container..."
docker push $ECR_REGISTRY/${ENVIRONMENT}-video-streaming-scraper:latest

echo "All containers built and pushed successfully!"
echo ""
echo "Next steps:"
echo "1. Use './terraform-deploy.sh' to deploy to AWS with Terraform"
echo "2. Or manually deploy using the Terraform configurations in ./terraform/"
echo "3. For local testing, use 'docker-compose up'"
