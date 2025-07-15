#!/bin/bash

# Automated ECR Image Cleanup Script
# This script automatically removes old images from ECR repositories without prompts
# Keeps only 'latest' and 'cache' tagged images, plus the most recent 3 images

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
KEEP_RECENT_COUNT=3  # Keep this many recent images even if untagged

# Repository names
REPOSITORIES=(
    "${ENVIRONMENT}-${PROJECT_NAME}-backend"
    "${ENVIRONMENT}-${PROJECT_NAME}-frontend"
    "${ENVIRONMENT}-${PROJECT_NAME}-scraper"
)

echo -e "${GREEN}🧹 Automated ECR Image Cleanup${NC}"
echo -e "${YELLOW}Removing old images while preserving 'latest', 'cache', and ${KEEP_RECENT_COUNT} most recent images${NC}"
echo ""

# Function to get images to delete (keeping latest, cache, and recent images)
get_images_to_delete() {
    local repo_name=$1
    
    # Get all images sorted by push date (newest first)
    local all_images=$(aws ecr describe-images \
        --repository-name "$repo_name" \
        --region "$AWS_REGION" \
        --query 'sort_by(imageDetails, &imagePushedAt) | reverse(@)' \
        --output json 2>/dev/null || echo "[]")
    
    # Use Python to process the JSON and determine which images to delete
    python3 -c "
import json
import sys

try:
    images = json.loads('$all_images')
    images_to_delete = []
    kept_count = 0
    
    for image in images:
        image_tags = image.get('imageTags', [])
        image_digest = image.get('imageDigest', '')
        
        # Keep images tagged as 'latest' or 'cache'
        if 'latest' in image_tags or 'cache' in image_tags:
            continue
            
        # Keep the first $KEEP_RECENT_COUNT recent images (even if untagged)
        if kept_count < $KEEP_RECENT_COUNT:
            kept_count += 1
            continue
            
        # Mark for deletion
        if image_digest:
            images_to_delete.append(image_digest)
    
    # Output digests to delete, one per line
    for digest in images_to_delete:
        print(digest)
        
except Exception as e:
    print(f'Error processing images: {e}', file=sys.stderr)
    sys.exit(1)
"
}

# Function to delete images in batches
delete_images_batch() {
    local repo_name=$1
    local digests=("${@:2}")
    
    if [ ${#digests[@]} -eq 0 ]; then
        return 0
    fi
    
    # ECR batch delete can handle up to 100 images at once
    local batch_size=10
    local total_deleted=0
    
    for ((i=0; i<${#digests[@]}; i+=batch_size)); do
        local batch=("${digests[@]:i:batch_size}")
        local image_ids=""
        
        # Build image IDs for batch delete
        for digest in "${batch[@]}"; do
            if [ -n "$image_ids" ]; then
                image_ids="$image_ids,"
            fi
            image_ids="${image_ids}imageDigest=$digest"
        done
        
        # Perform batch delete
        if aws ecr batch-delete-image \
            --repository-name "$repo_name" \
            --region "$AWS_REGION" \
            --image-ids $image_ids >/dev/null 2>&1; then
            total_deleted=$((total_deleted + ${#batch[@]}))
            echo -e "${GREEN}✅ Deleted batch of ${#batch[@]} images${NC}"
        else
            echo -e "${RED}❌ Failed to delete batch of ${#batch[@]} images${NC}"
        fi
    done
    
    return $total_deleted
}

# Function to cleanup a repository
cleanup_repository() {
    local repo_name=$1
    echo -e "${YELLOW}🔍 Processing repository: ${repo_name}${NC}"
    
    # Check if repository exists
    if ! aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Repository $repo_name not found, skipping...${NC}"
        echo ""
        return
    fi
    
    # Get total image count before cleanup
    local total_images=$(aws ecr describe-images \
        --repository-name "$repo_name" \
        --region "$AWS_REGION" \
        --query 'length(imageDetails)' \
        --output text 2>/dev/null || echo "0")
    
    echo -e "${BLUE}📊 Total images in repository: $total_images${NC}"
    
    # Get images to delete
    local images_to_delete=($(get_images_to_delete "$repo_name"))
    
    if [ ${#images_to_delete[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ No old images to delete in $repo_name${NC}"
        echo ""
        return
    fi
    
    echo -e "${YELLOW}🗑️  Found ${#images_to_delete[@]} images to delete${NC}"
    
    # Delete images
    delete_images_batch "$repo_name" "${images_to_delete[@]}"
    local deleted_count=$?
    
    # Get final image count
    local final_images=$(aws ecr describe-images \
        --repository-name "$repo_name" \
        --region "$AWS_REGION" \
        --query 'length(imageDetails)' \
        --output text 2>/dev/null || echo "0")
    
    echo -e "${GREEN}🎉 Cleanup completed for $repo_name${NC}"
    echo -e "${BLUE}📊 Images: $total_images → $final_images (deleted: $deleted_count)${NC}"
    echo ""
}

# Function to show repository sizes and savings
show_repository_summary() {
    echo -e "${BLUE}📊 Repository Summary:${NC}"
    local total_size=0
    
    for repo in "${REPOSITORIES[@]}"; do
        if aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" >/dev/null 2>&1; then
            local size=$(aws ecr describe-images \
                --repository-name "$repo" \
                --region "$AWS_REGION" \
                --query 'sum(imageDetails[].imageSizeInBytes)' \
                --output text 2>/dev/null || echo "0")
            
            local image_count=$(aws ecr describe-images \
                --repository-name "$repo" \
                --region "$AWS_REGION" \
                --query 'length(imageDetails)' \
                --output text 2>/dev/null || echo "0")
            
            if [ "$size" != "None" ] && [ "$size" != "0" ]; then
                local size_mb=$((size / 1024 / 1024))
                total_size=$((total_size + size_mb))
                echo "  $repo: ${image_count} images, ${size_mb} MB"
            else
                echo "  $repo: 0 images, 0 MB"
            fi
        else
            echo "  $repo: Not found"
        fi
    done
    
    echo "  Total storage: ${total_size} MB"
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

# Check if Python3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python3 is required but not installed.${NC}"
    exit 1
fi

# Show initial state
echo -e "${BLUE}📊 Initial State:${NC}"
show_repository_summary

# Clean up each repository
for repo in "${REPOSITORIES[@]}"; do
    cleanup_repository "$repo"
done

# Show final state
echo -e "${GREEN}🏁 Cleanup completed!${NC}"
echo ""
echo -e "${BLUE}📊 Final State:${NC}"
show_repository_summary

echo -e "${BLUE}💡 Cleanup Policy:${NC}"
echo "  ✅ Preserved: 'latest' and 'cache' tagged images"
echo "  ✅ Preserved: ${KEEP_RECENT_COUNT} most recent images per repository"
echo "  🗑️  Deleted: All other older images"
echo ""
echo -e "${GREEN}💰 This cleanup helps reduce ECR storage costs!${NC}"
