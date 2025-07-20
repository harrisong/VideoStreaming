#!/bin/bash

# Terraform deployment script for sidecar architecture
# This script deploys the video streaming application with nginx sidecar pattern

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_dependencies() {
    print_status "Checking dependencies..."
    
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform first."
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    print_success "All dependencies are installed."
}

# Check AWS credentials
check_aws_credentials() {
    print_status "Checking AWS credentials..."
    
    # Check for AWS credentials in environment variables
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        print_warning "AWS credentials not found in environment variables."
        print_status "Checking AWS CLI configuration..."
        
        # Fallback to AWS CLI configuration
        if ! timeout 30 aws sts get-caller-identity &> /dev/null; then
            print_error "AWS credentials are not configured. Please set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables or run 'aws configure'."
            print_status "Example:"
            print_status "export AWS_ACCESS_KEY_ID=your_access_key"
            print_status "export AWS_SECRET_ACCESS_KEY=your_secret_key"
            print_status "export AWS_DEFAULT_REGION=us-west-2"
            exit 1
        fi
    fi
    
    # Get AWS account ID and region
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    
    # Check for region in environment variable first, then AWS CLI config
    if [ -n "$AWS_DEFAULT_REGION" ]; then
        AWS_REGION="$AWS_DEFAULT_REGION"
    elif [ -n "$AWS_REGION" ]; then
        AWS_REGION="$AWS_REGION"
    else
        AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
    fi
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        print_error "Failed to get AWS account ID. Please check your AWS credentials."
        exit 1
    fi
    
    if [ -z "$AWS_REGION" ]; then
        print_warning "AWS region not set. Using us-west-2 as default."
        AWS_REGION="us-west-2"
        export AWS_DEFAULT_REGION="$AWS_REGION"
    fi
    
    print_success "AWS credentials configured. Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION"
}

# Get domain name from user
get_domain_name() {
    if [ -z "$DOMAIN_NAME" ]; then
        echo -n "Enter your domain name (e.g., example.com): "
        read DOMAIN_NAME
    fi
    
    if [ -z "$DOMAIN_NAME" ]; then
        print_error "Domain name is required."
        exit 1
    fi
    
    print_status "Using domain: $DOMAIN_NAME"
}

# Get environment name
get_environment() {
    if [ -z "$ENVIRONMENT" ]; then
        echo -n "Enter environment name (default: prod): "
        read ENVIRONMENT
        ENVIRONMENT=${ENVIRONMENT:-prod}
    fi
    
    print_status "Using environment: $ENVIRONMENT"
}

# Build and push Docker images
build_and_push_images() {
    print_status "Building and pushing Docker images..."
    
    export AWS_ACCOUNT_ID
    export AWS_REGION
    export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    export ENVIRONMENT
    
    # Run the sidecar build script
    if [ -f "./build-and-push.sh" ]; then
        print_status "Running sidecar container build script..."
        ./build-and-push.sh
    else
        print_error "build-and-push.sh not found. Please ensure it exists in the current directory."
        exit 1
    fi
    
    print_success "Docker images built and pushed successfully."
}

# Initialize Terraform
init_terraform() {
    print_status "Initializing Terraform..."
    
    cd terraform
    terraform init
    
    print_success "Terraform initialized."
}

# Plan Terraform deployment
plan_terraform() {
    print_status "Planning Terraform deployment..."
    
    terraform plan \
        -var="domain_name=$DOMAIN_NAME" \
        -var="environment=$ENVIRONMENT" \
        -var="server_count=${SERVER_COUNT:-2}" \
        -var="server_size=${SERVER_SIZE:-medium}" \
        -out=tfplan
    
    print_success "Terraform plan created."
}

# Apply Terraform deployment
apply_terraform() {
    print_status "Applying Terraform deployment..."
    
    terraform apply tfplan
    
    print_success "Terraform deployment completed."
}

# Get deployment outputs
get_outputs() {
    print_status "Getting deployment outputs..."
    
    echo ""
    print_success "=== DEPLOYMENT COMPLETED ==="
    echo ""
    
    echo "Load Balancer DNS: $(terraform output -raw load_balancer_ip)"
    echo "CloudFront Domain: $(terraform output -raw cloudfront_domain)"
    echo "Database Endpoint: $(terraform output -raw database_endpoint)"
    echo "Redis Endpoint: $(terraform output -raw redis_endpoint)"
    echo ""
    
    print_status "ECR Repositories:"
    terraform output -json ecr_repositories | jq -r 'to_entries[] | "  \(.key): \(.value)"'
    
    echo ""
    print_status "S3 Buckets:"
    terraform output -json s3_buckets | jq -r 'to_entries[] | "  \(.key): \(.value)"'
    
    echo ""
    print_status "Scraper API URL:"
    echo "  $(terraform output -raw scraper_api_url)"
    
    echo ""
    print_warning "Next Steps:"
    echo "1. Update your DNS records to point $DOMAIN_NAME to the Load Balancer DNS"
    echo "2. Wait for SSL certificate validation (may take a few minutes)"
    echo "3. Access your application at https://$DOMAIN_NAME"
    echo "4. Use the scraper API to add videos to your platform"
    
    cd ..
}

# Cleanup function
cleanup() {
    if [ -f "terraform/tfplan" ]; then
        rm terraform/tfplan
    fi
}

# Main deployment function
main() {
    print_status "Starting sidecar deployment for Video Streaming Service..."
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Check dependencies and credentials
    check_dependencies
    check_aws_credentials
    
    # Get user input
    get_domain_name
    get_environment
    
    # Build and push images
    build_and_push_images
    
    # Deploy with Terraform
    init_terraform
    plan_terraform
    
    # Ask for confirmation
    echo ""
    print_warning "Review the Terraform plan above."
    echo -n "Do you want to proceed with the deployment? (y/N): "
    read -r CONFIRM
    
    if [[ $CONFIRM =~ ^[Yy]$ ]]; then
        apply_terraform
        get_outputs
    else
        print_status "Deployment cancelled."
        exit 0
    fi
    
    print_success "Sidecar deployment completed successfully!"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Deploy Video Streaming Service with nginx sidecar pattern to AWS"
        echo ""
        echo "Environment Variables:"
        echo "  DOMAIN_NAME           - Your domain name (e.g., example.com)"
        echo "  ENVIRONMENT           - Environment name (default: prod)"
        echo "  SERVER_COUNT          - Number of ECS tasks (default: 2)"
        echo "  SERVER_SIZE           - ECS task size: small, medium, large (default: medium)"
        echo "  AWS_ACCESS_KEY_ID     - AWS access key ID"
        echo "  AWS_SECRET_ACCESS_KEY - AWS secret access key"
        echo "  AWS_DEFAULT_REGION    - AWS region (default: us-west-2)"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --destroy      Destroy the infrastructure"
        echo ""
        echo "Examples:"
        echo "  $0"
        echo "  DOMAIN_NAME=myapp.com ENVIRONMENT=staging $0"
        echo "  $0 --destroy"
        exit 0
        ;;
    --destroy)
        print_warning "This will destroy all infrastructure!"
        echo -n "Are you sure? Type 'yes' to confirm: "
        read -r CONFIRM
        
        if [ "$CONFIRM" = "yes" ]; then
            print_status "Destroying infrastructure..."
            cd terraform
            terraform destroy \
                -var="domain_name=${DOMAIN_NAME:-example.com}" \
                -var="environment=${ENVIRONMENT:-prod}"
            cd ..
            print_success "Infrastructure destroyed."
        else
            print_status "Destruction cancelled."
        fi
        exit 0
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use --help for usage information."
        exit 1
        ;;
esac
