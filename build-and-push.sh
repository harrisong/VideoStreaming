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

# Create ECR repositories if they don't exist (matching Terraform naming)
echo "Creating ECR repositories if they don't exist..."
ENVIRONMENT=${ENVIRONMENT:-prod}

aws ecr describe-repositories --repository-names "${ENVIRONMENT}-video-streaming-nginx-sidecar" --region $AWS_REGION --output text >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "${ENVIRONMENT}-video-streaming-nginx-sidecar" --region $AWS_REGION --output text >/dev/null

aws ecr describe-repositories --repository-names "${ENVIRONMENT}-video-streaming-frontend-sidecar" --region $AWS_REGION --output text >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "${ENVIRONMENT}-video-streaming-frontend-sidecar" --region $AWS_REGION --output text >/dev/null

aws ecr describe-repositories --repository-names "${ENVIRONMENT}-video-streaming-backend" --region $AWS_REGION --output text >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "${ENVIRONMENT}-video-streaming-backend" --region $AWS_REGION --output text >/dev/null

# Build and push nginx sidecar (ECS version with localhost)
echo "Building nginx sidecar container for ECS..."
docker build --platform linux/amd64 -f ./nginx-sidecar/Dockerfile -t nginx-sidecar:latest ./nginx-sidecar/
docker tag nginx-sidecar:latest $ECR_REGISTRY/${ENVIRONMENT}-video-streaming-nginx-sidecar:latest
echo "Pushing nginx sidecar container..."
docker push $ECR_REGISTRY/${ENVIRONMENT}-video-streaming-nginx-sidecar:latest

# Build and push frontend sidecar
echo "Building frontend sidecar container..."
docker build --platform linux/amd64 -f ./frontend/Dockerfile -t frontend-sidecar:latest ./frontend/
docker tag frontend-sidecar:latest $ECR_REGISTRY/${ENVIRONMENT}-video-streaming-frontend-sidecar:latest
echo "Pushing frontend sidecar container..."
docker push $ECR_REGISTRY/${ENVIRONMENT}-video-streaming-frontend-sidecar:latest

# Build and push backend
echo "Building backend container..."
docker build --platform linux/amd64 -t rust-backend:latest ./rust-backend/
docker tag rust-backend:latest $ECR_REGISTRY/${ENVIRONMENT}-video-streaming-backend:latest
echo "Pushing backend container..."
docker push $ECR_REGISTRY/${ENVIRONMENT}-video-streaming-backend:latest

echo "All containers built and pushed successfully!"
echo ""
echo "Next steps:"
echo "1. Use './terraform-deploy.sh' to deploy to AWS with Terraform"
echo "2. Or manually deploy using the Terraform configurations in ./terraform/"
echo "3. For local testing, use 'docker-compose up'"
