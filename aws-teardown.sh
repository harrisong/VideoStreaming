#!/bin/bash

# Complete AWS Infrastructure Teardown Script
# This script removes ALL resources created for the video streaming service

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ENVIRONMENT=${1:-prod}
REGION=${2:-us-west-2}

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Confirmation prompt
confirm_destruction() {
    echo -e "${RED}"
    echo "⚠️  WARNING: This will permanently delete ALL AWS resources!"
    echo "   - ECS clusters and containers"
    echo "   - RDS database and all data"
    echo "   - S3 buckets and all videos/files"
    echo "   - Load balancers and networking"
    echo "   - Container images in ECR"
    echo "   - SSL certificates"
    echo "   - All monitoring data"
    echo -e "${NC}"
    
    read -p "Are you absolutely sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log "Teardown cancelled by user"
        exit 0
    fi
}

# Check if AWS CLI is configured
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    log "AWS CLI configured successfully"
}

# Stop ECS services
stop_ecs_services() {
    log "Stopping ECS services..."
    
    # Get cluster name
    CLUSTER_NAME="${ENVIRONMENT}-video-streaming"
    
    # Check if cluster exists
    if aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
        # Stop service
        aws ecs update-service \
            --cluster "$CLUSTER_NAME" \
            --service "$CLUSTER_NAME" \
            --desired-count 0 \
            --region "$REGION" || warn "Failed to stop ECS service"
        
        # Wait for tasks to stop
        log "Waiting for ECS tasks to stop..."
        aws ecs wait services-stable \
            --cluster "$CLUSTER_NAME" \
            --services "$CLUSTER_NAME" \
            --region "$REGION" || warn "Timeout waiting for ECS tasks to stop"
    else
        info "ECS cluster not found or already deleted"
    fi
}

# Clean up ECR repositories
cleanup_ecr() {
    log "Cleaning up ECR repositories..."
    
    # List repositories
    REPOS=$(aws ecr describe-repositories \
        --query "repositories[?contains(repositoryName, '${ENVIRONMENT}-video-streaming')].repositoryName" \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
    
    if [ -n "$REPOS" ]; then
        for repo in $REPOS; do
            log "Deleting images in repository: $repo"
            
            # Get all image digests
            IMAGES=$(aws ecr list-images \
                --repository-name "$repo" \
                --query 'imageIds[*]' \
                --output json \
                --region "$REGION" 2>/dev/null || echo "[]")
            
            if [ "$IMAGES" != "[]" ] && [ "$IMAGES" != "" ]; then
                # Delete all images
                echo "$IMAGES" | aws ecr batch-delete-image \
                    --repository-name "$repo" \
                    --image-ids file:///dev/stdin \
                    --region "$REGION" || warn "Failed to delete images in $repo"
            fi
        done
    else
        info "No ECR repositories found"
    fi
}

# Clean up S3 buckets
cleanup_s3() {
    log "Cleaning up S3 buckets..."
    
    # Find video streaming buckets
    BUCKETS=$(aws s3 ls | grep "${ENVIRONMENT}-video-streaming" | awk '{print $3}' || echo "")
    
    if [ -n "$BUCKETS" ]; then
        for bucket in $BUCKETS; do
            log "Emptying S3 bucket: $bucket"
            
            # Empty bucket
            aws s3 rm "s3://$bucket" --recursive || warn "Failed to empty bucket $bucket"
            
            # Delete versioned objects if versioning is enabled
            aws s3api list-object-versions \
                --bucket "$bucket" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output json 2>/dev/null | \
            jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' | \
            while read -r args; do
                aws s3api delete-object --bucket "$bucket" $args || true
            done 2>/dev/null || true
            
            # Delete delete markers
            aws s3api list-object-versions \
                --bucket "$bucket" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output json 2>/dev/null | \
            jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' | \
            while read -r args; do
                aws s3api delete-object --bucket "$bucket" $args || true
            done 2>/dev/null || true
        done
    else
        info "No S3 buckets found"
    fi
}

# Create final database backup
backup_database() {
    log "Creating final database backup..."
    
    DB_IDENTIFIER="${ENVIRONMENT}-video-streaming-db"
    SNAPSHOT_ID="final-backup-$(date +%Y%m%d-%H%M%S)"
    
    # Check if database exists
    if aws rds describe-db-instances \
        --db-instance-identifier "$DB_IDENTIFIER" \
        --region "$REGION" &>/dev/null; then
        
        read -p "Create final database backup before deletion? (y/N): " create_backup
        
        if [[ $create_backup =~ ^[Yy]$ ]]; then
            aws rds create-db-snapshot \
                --db-instance-identifier "$DB_IDENTIFIER" \
                --db-snapshot-identifier "$SNAPSHOT_ID" \
                --region "$REGION" || warn "Failed to create database backup"
            
            log "Database backup created: $SNAPSHOT_ID"
        fi
    else
        info "Database not found"
    fi
}

# Run Terraform destroy
terraform_destroy() {
    log "Running Terraform destroy..."
    
    if [ -f "terraform/terraform.tfstate" ] || [ -f "terraform/.terraform/terraform.tfstate" ]; then
        cd terraform
        
        # Initialize if needed
        if [ ! -d ".terraform" ]; then
            terraform init
        fi
        
        # Destroy infrastructure
        terraform destroy -auto-approve || error "Terraform destroy failed"
        
        cd ..
        log "Terraform destroy completed"
    else
        warn "No Terraform state found, skipping Terraform destroy"
    fi
}

# Clean up remaining resources
cleanup_remaining() {
    log "Cleaning up any remaining resources..."
    
    # Delete CloudWatch log groups
    aws logs describe-log-groups \
        --log-group-name-prefix "/ecs/${ENVIRONMENT}-video-streaming" \
        --region "$REGION" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null | \
    xargs -I {} aws logs delete-log-group --log-group-name {} --region "$REGION" 2>/dev/null || true
    
    # Clean up any remaining NAT Gateways
    aws ec2 describe-nat-gateways \
        --filter "Name=tag:Name,Values=*${ENVIRONMENT}-video-streaming*" \
        --region "$REGION" \
        --query 'NatGateways[?State==`available`].NatGatewayId' \
        --output text 2>/dev/null | \
    xargs -I {} aws ec2 delete-nat-gateway --nat-gateway-id {} --region "$REGION" 2>/dev/null || true
    
    # Release any remaining Elastic IPs
    sleep 30  # Wait for NAT Gateways to release EIPs
    aws ec2 describe-addresses \
        --filters "Name=tag:Name,Values=*${ENVIRONMENT}-video-streaming*" \
        --region "$REGION" \
        --query 'Addresses[].AllocationId' \
        --output text 2>/dev/null | \
    xargs -I {} aws ec2 release-address --allocation-id {} --region "$REGION" 2>/dev/null || true
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check for remaining resources
    REMAINING_RESOURCES=0
    
    # Check ECS
    if aws ecs describe-clusters --clusters "${ENVIRONMENT}-video-streaming" --region "$REGION" &>/dev/null; then
        warn "ECS cluster still exists"
        ((REMAINING_RESOURCES++))
    fi
    
    # Check RDS
    if aws rds describe-db-instances --db-instance-identifier "${ENVIRONMENT}-video-streaming-db" --region "$REGION" &>/dev/null; then
        warn "RDS instance still exists"
        ((REMAINING_RESOURCES++))
    fi
    
    # Check S3
    S3_COUNT=$(aws s3 ls | grep "${ENVIRONMENT}-video-streaming" | wc -l || echo 0)
    if [ "$S3_COUNT" -gt 0 ]; then
        warn "$S3_COUNT S3 buckets still exist"
        ((REMAINING_RESOURCES++))
    fi
    
    # Check ECR
    ECR_COUNT=$(aws ecr describe-repositories --query "repositories[?contains(repositoryName, '${ENVIRONMENT}-video-streaming')]" --output text --region "$REGION" 2>/dev/null | wc -l || echo 0)
    if [ "$ECR_COUNT" -gt 0 ]; then
        warn "$ECR_COUNT ECR repositories still exist"
        ((REMAINING_RESOURCES++))
    fi
    
    if [ "$REMAINING_RESOURCES" -eq 0 ]; then
        log "✅ All resources have been successfully deleted!"
        log "💰 No ongoing AWS costs for this project"
    else
        warn "⚠️  $REMAINING_RESOURCES resource types may still exist"
        warn "Please check the AWS console for any remaining resources"
    fi
}

# Main execution
main() {
    log "Starting complete AWS infrastructure teardown..."
    log "Environment: $ENVIRONMENT"
    log "Region: $REGION"
    
    check_aws_cli
    confirm_destruction
    backup_database
    stop_ecs_services
    cleanup_ecr
    cleanup_s3
    terraform_destroy
    cleanup_remaining
    verify_cleanup
    
    log "🎉 Teardown process completed!"
    log "Please check your AWS billing dashboard to confirm no ongoing charges"
}

# Run main function
main "$@"
