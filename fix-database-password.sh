#!/bin/bash

# Fix database password for EKS migration
# This script resets the RDS database password and updates Terraform state

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔧 Fixing database password for EKS migration...${NC}"

# Configuration
ENVIRONMENT=${ENVIRONMENT:-prod}
REGION=${AWS_DEFAULT_REGION:-us-west-2}
DB_IDENTIFIER="${ENVIRONMENT}-video-streaming-db"

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not configured or credentials invalid${NC}"
    echo "Please set your AWS credentials:"
    echo "export AWS_ACCESS_KEY_ID=your_access_key"
    echo "export AWS_SECRET_ACCESS_KEY=your_secret_key"
    echo "export AWS_DEFAULT_REGION=us-west-2"
    exit 1
fi

echo -e "${YELLOW}Generating new database password...${NC}"
NEW_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

echo -e "${YELLOW}Updating RDS database password...${NC}"
aws rds modify-db-instance \
    --db-instance-identifier "$DB_IDENTIFIER" \
    --master-user-password "$NEW_PASSWORD" \
    --apply-immediately \
    --region "$REGION"

echo -e "${YELLOW}Waiting for database modification to complete...${NC}"
aws rds wait db-instance-available \
    --db-instance-identifier "$DB_IDENTIFIER" \
    --region "$REGION"

echo -e "${GREEN}✅ Database password updated successfully!${NC}"
echo ""
echo "New database password: $NEW_PASSWORD"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Export the new password:"
echo "   export DATABASE_PASSWORD='$NEW_PASSWORD'"
echo ""
echo "2. Update your Terraform state (optional):"
echo "   cd terraform"
echo "   terraform import random_password.db_password $NEW_PASSWORD"
echo ""
echo "3. Continue with EKS deployment:"
echo "   ./eks-deploy.sh"
echo ""
echo -e "${YELLOW}Note: Save this password securely as it will be needed for the application configuration.${NC}"
