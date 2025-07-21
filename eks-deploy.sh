#!/bin/bash

# EKS deployment script for Video Streaming Service
# This script deploys the video streaming application to Amazon EKS

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
    
    local missing_tools=()
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws")
    fi
    
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "The following tools are missing:"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        print_error "Please install the missing tools and try again."
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
    
    # Run the build script
    if [ -f "./build-and-push.sh" ]; then
        print_status "Running container build script..."
        ./build-and-push.sh
    else
        print_error "build-and-push.sh not found. Please ensure it exists in the current directory."
        exit 1
    fi
    
    print_success "Docker images built and pushed successfully."
}

# Deploy EKS infrastructure with Terraform
deploy_eks_infrastructure() {
    print_status "Deploying EKS infrastructure with Terraform..."
    
    cd terraform
    
    # Initialize Terraform
    print_status "Initializing Terraform..."
    terraform init
    
    # Plan deployment
    print_status "Planning Terraform deployment..."
    terraform plan \
        -var="domain_name=$DOMAIN_NAME" \
        -var="environment=$ENVIRONMENT" \
        -var="server_count=${SERVER_COUNT:-2}" \
        -var="instance_type=${INSTANCE_TYPE:-medium}" \
        -out=tfplan
    
    # Ask for confirmation
    echo ""
    print_warning "Review the Terraform plan above."
    echo -n "Do you want to proceed with the EKS infrastructure deployment? (y/N): "
    read -r CONFIRM
    
    if [[ $CONFIRM =~ ^[Yy]$ ]]; then
        print_status "Applying Terraform deployment..."
        terraform apply tfplan
        print_success "EKS infrastructure deployed successfully."
    else
        print_status "Infrastructure deployment cancelled."
        cd ..
        exit 0
    fi
    
    cd ..
}

# Configure kubectl for EKS
configure_kubectl() {
    print_status "Configuring kubectl for EKS cluster..."
    
    local cluster_name="${ENVIRONMENT}-video-streaming-eks"
    
    # Update kubeconfig
    aws eks update-kubeconfig \
        --region "$AWS_REGION" \
        --name "$cluster_name"
    
    # Test connection
    if kubectl cluster-info &> /dev/null; then
        print_success "kubectl configured successfully for EKS cluster: $cluster_name"
    else
        print_error "Failed to configure kubectl. Please check your EKS cluster status."
        exit 1
    fi
}

# Get Terraform outputs
get_terraform_outputs() {
    print_status "Getting Terraform outputs..."
    
    cd terraform
    
    # Refresh Terraform state to ensure outputs are available
    print_status "Refreshing Terraform state..."
    terraform refresh \
        -var="domain_name=$DOMAIN_NAME" \
        -var="environment=$ENVIRONMENT" \
        -var="server_count=${SERVER_COUNT:-2}" \
        -var="instance_type=${INSTANCE_TYPE:-medium}"
    
    # Get database and Redis endpoints with error handling
    if ! DATABASE_ENDPOINT=$(terraform output -raw database_endpoint 2>/dev/null); then
        print_error "Failed to get database endpoint from Terraform outputs"
        exit 1
    fi
    
    # Try to get database password, if not available, generate a new one
    if ! DATABASE_PASSWORD=$(terraform output -raw database_password 2>/dev/null); then
        print_warning "Database password not found in Terraform outputs, using temporary password..."
        DATABASE_PASSWORD="temp_password_$(openssl rand -hex 8)"
        print_warning "Using temporary database password. You may need to reset the RDS password manually."
        print_warning "Run ./fix-database-password.sh to set a proper password."
    fi
    
    # Try to get Redis endpoint from multiple possible outputs
    if ! REDIS_ENDPOINT=$(terraform output -raw redis_endpoint 2>/dev/null); then
        print_warning "Redis endpoint not found in redis_endpoint output, checking aws_resources..."
        if ! REDIS_ENDPOINT=$(terraform output -json aws_resources 2>/dev/null | jq -r '.redis // empty'); then
            print_error "Failed to get Redis endpoint from Terraform outputs"
            exit 1
        fi
    fi
    
    if ! S3_BUCKET=$(terraform output -json s3_buckets 2>/dev/null | jq -r '.videos'); then
        print_error "Failed to get S3 bucket from Terraform outputs"
        exit 1
    fi
    
    # Generate JWT secret
    JWT_SECRET=$(openssl rand -base64 32)
    
    # Construct connection strings
    DATABASE_URL="postgres://postgres:${DATABASE_PASSWORD}@${DATABASE_ENDPOINT}/video_streaming_db"
    REDIS_URL="rediss://${REDIS_ENDPOINT}:6379"
    
    cd ..
    
    print_success "Retrieved infrastructure configuration."
}

# Update Kubernetes manifests with actual values
update_k8s_manifests() {
    print_status "Updating Kubernetes manifests with actual values..."
    
    local ecr_registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    local api_url="https://${DOMAIN_NAME}/api"
    local cors_origins="https://${DOMAIN_NAME},http://localhost:3000"
    
    # Create temporary directory for processed manifests
    mkdir -p k8s/processed
    
    # Process each manifest file
    for file in k8s/manifests/*.yaml; do
        local filename=$(basename "$file")
        local processed_file="k8s/processed/$filename"
        
        # Replace placeholders in the file
        sed -e "s|PLACEHOLDER_ECR_REGISTRY|$ecr_registry|g" \
            -e "s|PLACEHOLDER_ENVIRONMENT|$ENVIRONMENT|g" \
            -e "s|PLACEHOLDER_DATABASE_URL|$DATABASE_URL|g" \
            -e "s|PLACEHOLDER_REDIS_URL|$REDIS_URL|g" \
            -e "s|PLACEHOLDER_JWT_SECRET|$JWT_SECRET|g" \
            -e "s|PLACEHOLDER_S3_BUCKET|$S3_BUCKET|g" \
            -e "s|PLACEHOLDER_AWS_REGION|$AWS_REGION|g" \
            -e "s|PLACEHOLDER_DOMAIN|https://$DOMAIN_NAME|g" \
            -e "s|PLACEHOLDER_API_URL|$api_url|g" \
            -e "s|PLACEHOLDER_IAM_ROLE_ARN|arn:aws:iam::$AWS_ACCOUNT_ID:role/${ENVIRONMENT}-video-streaming-eks-node-group-role|g" \
            "$file" > "$processed_file"
    done
    
    print_success "Kubernetes manifests updated with actual values."
}

# Deploy to Kubernetes
deploy_to_kubernetes() {
    print_status "Deploying application to Kubernetes..."
    
    # Apply manifests in order
    kubectl apply -f k8s/processed/namespace.yaml
    kubectl apply -f k8s/processed/secrets.yaml
    kubectl apply -f k8s/processed/serviceaccount.yaml
    kubectl apply -f k8s/processed/configmap.yaml
    kubectl apply -f k8s/processed/service.yaml
    kubectl apply -f k8s/processed/deployment.yaml
    
    print_success "Application deployed to Kubernetes."
    
    # Run database migration
    print_status "Running database migration..."
    kubectl apply -f k8s/processed/jobs.yaml
    
    # Wait for migration to complete
    print_status "Waiting for database migration to complete..."
    kubectl wait --for=condition=complete job/video-streaming-db-migration -n video-streaming --timeout=300s
    
    if [ $? -eq 0 ]; then
        print_success "Database migration completed successfully."
    else
        print_warning "Database migration may have failed. Check the job logs:"
        print_status "kubectl logs job/video-streaming-db-migration -n video-streaming"
    fi
}

# Wait for deployment to be ready
wait_for_deployment() {
    print_status "Waiting for deployment to be ready..."
    
    kubectl rollout status deployment/video-streaming-app -n video-streaming --timeout=600s
    
    if [ $? -eq 0 ]; then
        print_success "Deployment is ready!"
    else
        print_warning "Deployment may not be fully ready. Check pod status:"
        print_status "kubectl get pods -n video-streaming"
    fi
}

# Get deployment outputs
get_deployment_outputs() {
    print_status "Getting deployment information..."
    
    cd terraform
    
    echo ""
    print_success "=== EKS DEPLOYMENT COMPLETED ==="
    echo ""
    
    echo "EKS Cluster: $(terraform output -raw eks_cluster_name)"
    echo "Load Balancer DNS: $(terraform output -raw load_balancer_dns)"
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
    print_status "Kubernetes Resources:"
    echo "  Namespace: video-streaming"
    echo "  Deployment: video-streaming-app"
    echo "  Service: video-streaming-service (NodePort 30080)"
    
    echo ""
    print_status "Useful kubectl commands:"
    echo "  kubectl get pods -n video-streaming"
    echo "  kubectl get services -n video-streaming"
    echo "  kubectl logs -f deployment/video-streaming-app -n video-streaming -c backend"
    echo "  kubectl exec -it deployment/video-streaming-app -n video-streaming -c backend -- /bin/bash"
    
    echo ""
    print_warning "Next Steps:"
    echo "1. Update your DNS records to point $DOMAIN_NAME to the Load Balancer DNS"
    echo "2. Wait for SSL certificate validation (may take a few minutes)"
    echo "3. Access your application at https://$DOMAIN_NAME"
    echo "4. Monitor your pods: kubectl get pods -n video-streaming -w"
    
    cd ..
}

# Cleanup function
cleanup() {
    if [ -f "terraform/tfplan" ]; then
        rm terraform/tfplan
    fi
    if [ -d "k8s/processed" ]; then
        rm -rf k8s/processed
    fi
}

# Main deployment function
main() {
    print_status "Starting EKS deployment for Video Streaming Service..."
    
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
    
    # Deploy EKS infrastructure
    deploy_eks_infrastructure
    
    # Configure kubectl
    configure_kubectl
    
    # Get infrastructure outputs
    get_terraform_outputs
    
    # Update K8s manifests
    update_k8s_manifests
    
    # Deploy to Kubernetes
    deploy_to_kubernetes
    
    # Wait for deployment
    wait_for_deployment
    
    # Show outputs
    get_deployment_outputs
    
    print_success "EKS deployment completed successfully!"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Deploy Video Streaming Service to Amazon EKS"
        echo ""
        echo "Environment Variables:"
        echo "  DOMAIN_NAME           - Your domain name (e.g., example.com)"
        echo "  ENVIRONMENT           - Environment name (default: prod)"
        echo "  SERVER_COUNT          - Number of replicas (default: 2)"
        echo "  INSTANCE_TYPE         - Node instance type: small, medium, large (default: medium)"
        echo "  AWS_ACCESS_KEY_ID     - AWS access key ID"
        echo "  AWS_SECRET_ACCESS_KEY - AWS secret access key"
        echo "  AWS_DEFAULT_REGION    - AWS region (default: us-west-2)"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --destroy      Destroy the infrastructure"
        echo "  --k8s-only     Deploy only Kubernetes resources (skip Terraform)"
        echo ""
        echo "Examples:"
        echo "  $0"
        echo "  DOMAIN_NAME=myapp.com ENVIRONMENT=staging $0"
        echo "  $0 --destroy"
        echo "  $0 --k8s-only"
        exit 0
        ;;
    --destroy)
        print_warning "This will destroy all EKS infrastructure!"
        echo -n "Are you sure? Type 'yes' to confirm: "
        read -r CONFIRM
        
        if [ "$CONFIRM" = "yes" ]; then
            print_status "Destroying Kubernetes resources..."
            if kubectl get namespace video-streaming &> /dev/null; then
                kubectl delete namespace video-streaming
            fi
            
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
    --k8s-only)
        print_status "Deploying only Kubernetes resources..."
        check_dependencies
        check_aws_credentials
        get_domain_name
        get_environment
        configure_kubectl
        get_terraform_outputs
        update_k8s_manifests
        deploy_to_kubernetes
        wait_for_deployment
        print_success "Kubernetes deployment completed!"
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
