#!/bin/bash

# Fix security group rules for EKS to access RDS and Redis
# This script applies the Terraform changes to allow EKS pods to connect to the database

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔧 Fixing security group rules for EKS database access...${NC}"

# Check if we're in the right directory
if [ ! -f "terraform/main.tf" ]; then
    echo -e "${RED}❌ Please run this script from the project root directory${NC}"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not configured or credentials invalid${NC}"
    echo "Please set your AWS credentials:"
    echo "export AWS_ACCESS_KEY_ID=your_access_key"
    echo "export AWS_SECRET_ACCESS_KEY=your_secret_key"
    echo "export AWS_DEFAULT_REGION=us-west-2"
    exit 1
fi

echo -e "${YELLOW}Applying Terraform changes to fix security groups...${NC}"

cd terraform

# Initialize Terraform (in case it's not initialized)
terraform init

# Plan the changes
echo -e "${YELLOW}Planning security group changes...${NC}"
terraform plan \
    -var="domain_name=${DOMAIN_NAME:-stream.harrisonng.dev}" \
    -var="environment=${ENVIRONMENT:-prod}" \
    -var="server_count=${SERVER_COUNT:-2}" \
    -var="instance_type=${INSTANCE_TYPE:-medium}" \
    -target="aws_security_group_rule.rds_from_eks" \
    -target="aws_security_group_rule.redis_from_eks" \
    -out=security-group-fix.tfplan

echo -e "${YELLOW}Applying security group fixes...${NC}"
terraform apply security-group-fix.tfplan

echo -e "${GREEN}✅ Security group rules updated successfully!${NC}"

# Clean up
rm -f security-group-fix.tfplan

cd ..

echo -e "${GREEN}🎉 EKS pods can now access RDS and Redis!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Restart the EKS deployment to pick up the network changes:"
echo "   kubectl rollout restart deployment/video-streaming-app -n video-streaming"
echo ""
echo "2. Wait for pods to restart:"
echo "   kubectl rollout status deployment/video-streaming-app -n video-streaming"
echo ""
echo "3. Check if the backend container starts successfully:"
echo "   kubectl logs deployment/video-streaming-app -n video-streaming -c backend"
echo ""
echo "4. Test the nginx health endpoint:"
echo "   kubectl exec -it deployment/video-streaming-app -n video-streaming -c nginx -- curl localhost:80/nginx-health"
