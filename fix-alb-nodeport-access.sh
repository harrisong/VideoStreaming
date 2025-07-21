#!/bin/bash

# Fix ALB to EKS NodePort access
# This script applies the security group rule to allow ALB to reach EKS nodes on port 30080

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔧 Fixing ALB to EKS NodePort access...${NC}"

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

echo -e "${YELLOW}Applying security group rule for ALB → EKS NodePort access...${NC}"

cd terraform

# Initialize Terraform (in case it's not initialized)
terraform init

# Apply the specific security group rule
terraform apply \
    -target="module.aws.aws_security_group_rule.eks_nodeport_from_alb" \
    -var="domain_name=${DOMAIN_NAME:-stream.harrisonng.dev}" \
    -var="environment=${ENVIRONMENT:-prod}" \
    -var="server_count=${SERVER_COUNT:-2}" \
    -var="instance_type=${INSTANCE_TYPE:-medium}" \
    -auto-approve

echo -e "${GREEN}✅ Security group rule applied successfully!${NC}"

cd ..

echo -e "${YELLOW}Verifying the security group rule...${NC}"

# Check if the rule was applied
EKS_SG_ID=$(aws eks describe-cluster --name prod-video-streaming-eks --region us-west-2 --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

echo "Checking security group rules for EKS security group: $EKS_SG_ID"

aws ec2 describe-security-groups \
    --group-ids "$EKS_SG_ID" \
    --region us-west-2 \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`30080`].[IpProtocol,FromPort,ToPort,UserIdGroupPairs[*].GroupId]' \
    --output table

echo ""
echo -e "${GREEN}🎉 ALB can now reach EKS NodePort service!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Wait 2-3 minutes for the ALB health checks to detect the change"
echo "2. Check ALB target group health:"
echo "   aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:us-west-2:339131303757:targetgroup/prod-video-streaming-eks-tg/0e2fd475f1b9d1d2 --region us-west-2"
echo ""
echo "3. Once targets are healthy, test the application:"
echo "   curl -I https://stream.harrisonng.dev"
echo ""
echo -e "${BLUE}The ALB health checks should now pass and your EKS migration will be complete! 🚀${NC}"
