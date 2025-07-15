#!/bin/bash

# ECR Image Cleanup Script
# This script removes old images from ECR repositories, keeping only the latest tagged images

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="us-west-2"
ENVIRONMENT="prod"
PROJECT_NAME="video-streaming"

# Repository names
REPOSITORIES=(
    "${ENVIRONMENT}-${PROJECT_NAME}-backend"
    "${ENVIRONMENT}-${PROJECT_NAME}-frontend"
    "${ENVIRONMENT}-${PROJECT_NAME}-scraper"
)

echo -e "${GREEN}🧹 ECR Image Cleanup Tool${NC}"
echo -e "${YELLOW}This will remove old images from ECR repositories, keeping only 'latest' and 'cache' tagged images${NC}"
echo ""

# Function to list images in a repository
list_images() {
    local repo_name=$1
    echo -e "${BLUE}📋 Images in repository: ${repo_name}${NC}"
    
    if aws ecr describe-images --repository-name "$repo_name" --region "$AWS_REGION" >/dev/null 2>&1; then
        aws ecr describe-images \
            --repository-name "$repo_name" \
            --region "$AWS_REGION" \
            --query 'imageDetails[*].[imageTags[0],imageDigest,imagePushedAt,imageSizeInBytes]' \
            --output table
    else
        echo -e "${YELLOW}⚠️  Repository $repo_name not found or empty${NC}"
    fi
    echo ""
}

# Function to get images to delete (not tagged as latest or cache)
get_images_to_delete() {
    local repo_name=$1
    
    # Get all image digests that are NOT tagged as 'latest' or 'cache' or are untagged
    aws ecr describe-images \
        --repository-name "$repo_name" \
        --region "$AWS_REGION" \
        --query 'imageDetails[?(!imageTags || (imageTags && !contains(imageTags, `latest`) && !contains(imageTags, `cache`)))].imageDigest' \
        --output text 2>/dev/null || echo ""
}

# Function to delete old images
cleanup_repository() {
    local repo_name=$1
    echo -e "${YELLOW}🔍 Checking repository: ${repo_name}${NC}"
    
    if ! aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Repository $repo_name not found, skipping...${NC}"
        echo ""
        return
    fi
    
    # Get images to delete
    local images_to_delete=$(get_images_to_delete "$repo_name")
    
    if [ -z "$images_to_delete" ] || [ "$images_to_delete" = "None" ]; then
        echo -e "${GREEN}✅ No old images to delete in $repo_name${NC}"
        echo ""
        return
    fi
    
    # Count images to delete
    local image_count=$(echo "$images_to_delete" | wc -w)
    echo -e "${YELLOW}📦 Found $image_count old images to delete${NC}"
    
    # Show what will be deleted
    echo -e "${BLUE}Images to be deleted:${NC}"
    for digest in $images_to_delete; do
        echo "  - $digest"
    done
    echo ""
    
    # Ask for confirmation
    read -p "Delete these images from $repo_name? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}🗑️  Deleting old images...${NC}"
        
        # Delete images in batches (ECR has a limit of 100 images per batch)
        local batch_size=10
        local deleted_count=0
        
        for digest in $images_to_delete; do
            if aws ecr batch-delete-image \
                --repository-name "$repo_name" \
                --region "$AWS_REGION" \
                --image-ids imageDigest="$digest" >/dev/null 2>&1; then
                deleted_count=$((deleted_count + 1))
                echo -e "${GREEN}✅ Deleted image: ${digest:0:12}...${NC}"
            else
                echo -e "${RED}❌ Failed to delete image: ${digest:0:12}...${NC}"
            fi
        done
        
        echo -e "${GREEN}🎉 Successfully deleted $deleted_count images from $repo_name${NC}"
    else
        echo -e "${YELLOW}⏭️  Skipped deletion for $repo_name${NC}"
    fi
    echo ""
}

# Function to show repository sizes
show_repository_sizes() {
    echo -e "${BLUE}📊 Repository sizes:${NC}"
    for repo in "${REPOSITORIES[@]}"; do
        if aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" >/dev/null 2>&1; then
            local size=$(aws ecr describe-images \
                --repository-name "$repo" \
                --region "$AWS_REGION" \
                --query 'sum(imageDetails[].imageSizeInBytes)' \
                --output text 2>/dev/null || echo "0")
            
            if [ "$size" != "None" ] && [ "$size" != "0" ]; then
                local size_mb=$((size / 1024 / 1024))
                echo "  $repo: ${size_mb} MB"
            else
                echo "  $repo: 0 MB (empty)"
            fi
        else
            echo "  $repo: Not found"
        fi
    done
    echo ""
}

# Main execution
echo -e "${YELLOW}🔐 Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${RED}❌ AWS credentials not configured. Please run 'aws configure' first.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ AWS credentials OK${NC}"
echo ""

# Show current repository sizes
show_repository_sizes

# Option to list all images first
read -p "Do you want to see all images in each repository first? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    for repo in "${REPOSITORIES[@]}"; do
        list_images "$repo"
    done
fi

# Clean up each repository
for repo in "${REPOSITORIES[@]}"; do
    cleanup_repository "$repo"
done

# Show final repository sizes
echo -e "${GREEN}🏁 Cleanup completed!${NC}"
echo ""
show_repository_sizes

echo -e "${BLUE}💡 Tips:${NC}"
echo "  - Only 'latest' and 'cache' tagged images are preserved"
echo "  - Untagged images are removed"
echo "  - You can run this script regularly to keep ECR storage costs low"
echo "  - Consider setting up ECR lifecycle policies for automatic cleanup"
