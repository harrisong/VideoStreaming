#!/bin/bash

# Cleanup ECS resources before EKS deployment
# This script removes conflicting ECS resources to allow clean EKS deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${ENVIRONMENT:-prod}
REGION=${AWS_DEFAULT_REGION:-us-west-2}

echo -e "${YELLOW}🧹 Cleaning up ECS resources for EKS migration...${NC}"

# Function to check if AWS CLI is configured
check_aws_cli() {
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}❌ AWS CLI not configured or credentials invalid${NC}"
        echo "Please set your AWS credentials:"
        echo "export AWS_ACCESS_KEY_ID=your_access_key"
        echo "export AWS_SECRET_ACCESS_KEY=your_secret_key"
        echo "export AWS_DEFAULT_REGION=us-west-2"
        exit 1
    fi
}

# Function to clean up ECR images
cleanup_ecr_images() {
    local repo_name=$1
    echo -e "${YELLOW}Cleaning up ECR repository: ${repo_name}${NC}"
    
    # Check if repository exists
    if aws ecr describe-repositories --repository-names "$repo_name" --region "$REGION" &> /dev/null; then
        # First, try to delete all images (including manifest lists)
        local images=$(aws ecr list-images --repository-name "$repo_name" --region "$REGION" --query 'imageIds[*]' --output json)
        
        if [ "$images" != "[]" ] && [ "$images" != "null" ]; then
            echo "Deleting all images from $repo_name..."
            aws ecr batch-delete-image --repository-name "$repo_name" --region "$REGION" --image-ids "$images" || true
            
            # Wait a moment for AWS to process
            sleep 5
            
            # Check if there are still images left and try again
            local remaining_images=$(aws ecr list-images --repository-name "$repo_name" --region "$REGION" --query 'imageIds[*]' --output json)
            if [ "$remaining_images" != "[]" ] && [ "$remaining_images" != "null" ]; then
                echo "Retrying deletion of remaining images..."
                aws ecr batch-delete-image --repository-name "$repo_name" --region "$REGION" --image-ids "$remaining_images" || true
            fi
        fi
        
        echo -e "${GREEN}✅ Cleaned up ECR repository: ${repo_name}${NC}"
    else
        echo "Repository $repo_name does not exist, skipping..."
    fi
}

# Function to stop ECS services
stop_ecs_services() {
    local cluster_name="${ENVIRONMENT}-video-streaming"
    
    echo -e "${YELLOW}Stopping ECS services in cluster: ${cluster_name}${NC}"
    
    # Check if cluster exists
    if aws ecs describe-clusters --clusters "$cluster_name" --region "$REGION" --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
        # List and stop all services
        local services=$(aws ecs list-services --cluster "$cluster_name" --region "$REGION" --query 'serviceArns[*]' --output text)
        
        for service in $services; do
            if [ -n "$service" ]; then
                local service_name=$(basename "$service")
                echo "Stopping service: $service_name"
                aws ecs update-service --cluster "$cluster_name" --service "$service_name" --desired-count 0 --region "$REGION" || true
                
                # Wait for service to stop
                echo "Waiting for service $service_name to stop..."
                aws ecs wait services-stable --cluster "$cluster_name" --services "$service_name" --region "$REGION" || true
            fi
        done
        
        echo -e "${GREEN}✅ Stopped ECS services${NC}"
    else
        echo "ECS cluster $cluster_name does not exist or is not active, skipping..."
    fi
}

# Function to update ALB listener to use placeholder target group
update_alb_listener() {
    echo -e "${YELLOW}Updating ALB listener to use placeholder target group...${NC}"
    
    local alb_name="${ENVIRONMENT}-video-streaming-alb"
    local placeholder_tg_name="${ENVIRONMENT}-video-streaming-tg"
    
    # Get ALB ARN
    local alb_arn=$(aws elbv2 describe-load-balancers --names "$alb_name" --region "$REGION" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
    
    if [ "$alb_arn" != "None" ] && [ -n "$alb_arn" ]; then
        # Get placeholder target group ARN
        local placeholder_tg_arn=$(aws elbv2 describe-target-groups --names "$placeholder_tg_name" --region "$REGION" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
        
        if [ "$placeholder_tg_arn" != "None" ] && [ -n "$placeholder_tg_arn" ]; then
            # Get HTTPS listener ARN
            local listener_arn=$(aws elbv2 describe-listeners --load-balancer-arn "$alb_arn" --region "$REGION" --query 'Listeners[?Port==`443`].ListenerArn' --output text)
            
            if [ -n "$listener_arn" ]; then
                echo "Updating HTTPS listener to use placeholder target group..."
                aws elbv2 modify-listener \
                    --listener-arn "$listener_arn" \
                    --default-actions Type=forward,TargetGroupArn="$placeholder_tg_arn" \
                    --region "$REGION" || true
                
                echo -e "${GREEN}✅ Updated ALB listener${NC}"
            else
                echo "HTTPS listener not found, skipping..."
            fi
        else
            echo "Placeholder target group not found, skipping..."
        fi
    else
        echo "ALB not found, skipping..."
    fi
}

# Main cleanup process
main() {
    echo -e "${YELLOW}Starting ECS to EKS migration cleanup...${NC}"
    
    # Check prerequisites
    check_aws_cli
    
    # Stop ECS services first
    stop_ecs_services
    
    # Update ALB listener to use placeholder target group
    update_alb_listener
    
    # Clean up ECR repositories that have force_delete issues
    cleanup_ecr_images "${ENVIRONMENT}-video-streaming-frontend-sidecar"
    cleanup_ecr_images "${ENVIRONMENT}-video-streaming-nginx-sidecar"
    
    # Wait a bit for AWS to process the changes
    echo -e "${YELLOW}Waiting 30 seconds for AWS to process changes...${NC}"
    sleep 30
    
    echo -e "${GREEN}🎉 Cleanup completed successfully!${NC}"
    echo -e "${YELLOW}You can now run: ./eks-deploy.sh${NC}"
}

# Run main function
main "$@"
