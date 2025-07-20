#!/bin/bash

# Database Migration Script for ECS
# This script runs the database migration task on AWS ECS

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="prod"
REGION="us-west-2"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -e|--environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    -r|--region)
      REGION="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  -e, --environment    Environment name (default: prod)"
      echo "  -r, --region         AWS region (default: us-west-2)"
      echo "  -h, --help          Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

echo -e "${YELLOW}Starting database migration for environment: ${ENVIRONMENT}${NC}"

# Get cluster name
CLUSTER_NAME="${ENVIRONMENT}-video-streaming"
echo -e "${YELLOW}Using ECS cluster: ${CLUSTER_NAME}${NC}"

# Check if cluster exists
if ! aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo -e "${RED}Error: ECS cluster '${CLUSTER_NAME}' not found in region '${REGION}'${NC}"
    echo "Please make sure your infrastructure is deployed and the cluster exists."
    exit 1
fi

# Get task definition ARN
TASK_DEF_FAMILY="${ENVIRONMENT}-video-streaming-db-migration"
echo -e "${YELLOW}Looking for task definition: ${TASK_DEF_FAMILY}${NC}"

TASK_DEF_ARN=$(aws ecs describe-task-definition --task-definition "$TASK_DEF_FAMILY" --region "$REGION" --query 'taskDefinition.taskDefinitionArn' --output text 2>/dev/null || echo "")

if [ -z "$TASK_DEF_ARN" ] || [ "$TASK_DEF_ARN" = "None" ]; then
    echo -e "${RED}Error: Task definition '${TASK_DEF_FAMILY}' not found${NC}"
    echo "Please make sure your terraform infrastructure is deployed."
    exit 1
fi

echo -e "${GREEN}Found task definition: ${TASK_DEF_ARN}${NC}"

# Get subnet IDs and security group
echo -e "${YELLOW}Getting network configuration...${NC}"

SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=${ENVIRONMENT}-video-streaming-private-*" \
    --region "$REGION" \
    --query 'Subnets[].SubnetId' \
    --output text | tr '\t' ',')

if [ -z "$SUBNETS" ]; then
    echo -e "${RED}Error: No private subnets found${NC}"
    exit 1
fi

SECURITY_GROUP=$(aws ec2 describe-security-groups \
    --filters "Name=tag:Name,Values=${ENVIRONMENT}-video-streaming-ecs-sg" \
    --region "$REGION" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

if [ -z "$SECURITY_GROUP" ] || [ "$SECURITY_GROUP" = "None" ]; then
    echo -e "${RED}Error: ECS security group not found${NC}"
    exit 1
fi

echo -e "${GREEN}Network configuration found:${NC}"
echo -e "  Subnets: ${SUBNETS}"
echo -e "  Security Group: ${SECURITY_GROUP}"

# Run the migration task
echo -e "${YELLOW}Starting database migration task...${NC}"

TASK_ARN=$(aws ecs run-task \
    --cluster "$CLUSTER_NAME" \
    --task-definition "$TASK_DEF_ARN" \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${SECURITY_GROUP}],assignPublicIp=DISABLED}" \
    --region "$REGION" \
    --query 'tasks[0].taskArn' \
    --output text)

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ]; then
    echo -e "${RED}Error: Failed to start migration task${NC}"
    exit 1
fi

echo -e "${GREEN}Migration task started successfully!${NC}"
echo -e "Task ARN: ${TASK_ARN}"

# Extract task ID from ARN
TASK_ID=$(echo "$TASK_ARN" | cut -d'/' -f3)
echo -e "Task ID: ${TASK_ID}"

# Wait for task to complete
echo -e "${YELLOW}Waiting for migration task to complete...${NC}"

while true; do
    TASK_STATUS=$(aws ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --region "$REGION" \
        --query 'tasks[0].lastStatus' \
        --output text)
    
    echo -e "Current status: ${TASK_STATUS}"
    
    if [ "$TASK_STATUS" = "STOPPED" ]; then
        break
    fi
    
    sleep 10
done

# Check exit code
EXIT_CODE=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ARN" \
    --region "$REGION" \
    --query 'tasks[0].containers[0].exitCode' \
    --output text)

STOP_REASON=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ARN" \
    --region "$REGION" \
    --query 'tasks[0].stoppedReason' \
    --output text)

echo -e "\n${YELLOW}Migration task completed${NC}"
echo -e "Exit code: ${EXIT_CODE}"
echo -e "Stop reason: ${STOP_REASON}"

if [ "$EXIT_CODE" = "0" ]; then
    echo -e "${GREEN}✅ Database migration completed successfully!${NC}"
else
    echo -e "${RED}❌ Database migration failed with exit code: ${EXIT_CODE}${NC}"
    echo -e "${YELLOW}Check the CloudWatch logs for more details:${NC}"
    echo -e "Log group: /ecs/${ENVIRONMENT}-video-streaming"
    echo -e "Log stream: db-migration/${TASK_ID}"
    echo -e "\nYou can view logs with:"
    echo -e "aws logs get-log-events --log-group-name '/ecs/${ENVIRONMENT}-video-streaming' --log-stream-name 'db-migration/${TASK_ID}' --region '${REGION}'"
    exit 1
fi

echo -e "\n${GREEN}Database migration completed successfully!${NC}"
echo -e "${YELLOW}You can view the migration logs with:${NC}"
echo -e "aws logs get-log-events --log-group-name '/ecs/${ENVIRONMENT}-video-streaming' --log-stream-name 'db-migration/${TASK_ID}' --region '${REGION}'"
