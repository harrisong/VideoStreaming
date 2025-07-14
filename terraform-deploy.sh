#!/bin/bash

# Terraform Infrastructure Deployment Script for Video Streaming Service
# This script manages infrastructure deployment across multiple cloud providers

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Help function
show_help() {
    cat << EOF
Terraform Infrastructure Deployment Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    init        Initialize Terraform
    plan        Show deployment plan
    apply       Deploy infrastructure
    destroy     Destroy infrastructure
    output      Show infrastructure outputs
    switch      Switch cloud provider
    validate    Validate configuration
    help        Show this help message

Options:
    -p, --provider PROVIDER    Cloud provider (hetzner, digitalocean, vultr, linode)
    -e, --environment ENV      Environment (dev, staging, prod)
    -s, --size SIZE           Server size (small, medium, large)
    -c, --count COUNT         Number of servers
    -d, --domain DOMAIN       Domain name
    -f, --force               Force operation without confirmation
    -v, --verbose             Verbose output

Examples:
    $0 init
    $0 plan --provider hetzner --environment prod
    $0 apply --provider hetzner --domain example.com
    $0 switch --provider digitalocean
    $0 destroy --force

Environment Variables:
    HCLOUD_TOKEN              Hetzner Cloud API token
    DIGITALOCEAN_TOKEN        DigitalOcean API token
    VULTR_API_KEY            Vultr API key
    LINODE_TOKEN             Linode API token
    CLOUDFLARE_API_TOKEN     Cloudflare API token (optional)

EOF
}

# Check dependencies
check_dependencies() {
    local deps=("terraform" "curl" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "Required dependency '$dep' is not installed"
        fi
    done
}

# Install Terraform if not present
install_terraform() {
    if ! command -v terraform &> /dev/null; then
        log "Installing Terraform..."
        
        # Detect OS
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        ARCH=$(uname -m)
        
        case $ARCH in
            x86_64) ARCH="amd64" ;;
            arm64|aarch64) ARCH="arm64" ;;
            *) error "Unsupported architecture: $ARCH" ;;
        esac
        
        # Download and install Terraform
        TERRAFORM_VERSION="1.6.6"
        TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip"
        
        curl -fsSL "$TERRAFORM_URL" -o terraform.zip
        unzip terraform.zip
        sudo mv terraform /usr/local/bin/
        rm terraform.zip
        
        log "Terraform installed successfully"
    fi
}

# Validate configuration
validate_config() {
    if [ ! -f "terraform/terraform.tfvars" ]; then
        warn "terraform.tfvars not found. Creating from example..."
        cp terraform/terraform.tfvars.example terraform/terraform.tfvars
        error "Please edit terraform/terraform.tfvars with your configuration"
    fi
    
    # Check required variables
    local required_vars=("domain_name" "ssh_public_key")
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}.*=" terraform/terraform.tfvars; then
            error "Required variable '$var' not set in terraform.tfvars"
        fi
    done
}

# Check provider credentials
check_provider_credentials() {
    local provider=${1:-$(grep '^cloud_provider' terraform/terraform.tfvars | cut -d'"' -f2)}
    
    case $provider in
        aws)
            if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
                error "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables are required for AWS"
            fi
            ;;
        hetzner)
            if [ -z "$HCLOUD_TOKEN" ]; then
                error "HCLOUD_TOKEN environment variable is required for Hetzner Cloud"
            fi
            ;;
        digitalocean)
            if [ -z "$DIGITALOCEAN_TOKEN" ]; then
                error "DIGITALOCEAN_TOKEN environment variable is required for DigitalOcean"
            fi
            ;;
        vultr)
            if [ -z "$VULTR_API_KEY" ]; then
                error "VULTR_API_KEY environment variable is required for Vultr"
            fi
            ;;
        linode)
            if [ -z "$LINODE_TOKEN" ]; then
                error "LINODE_TOKEN environment variable is required for Linode"
            fi
            ;;
        *)
            error "Unsupported provider: $provider"
            ;;
    esac
}

# Initialize Terraform
terraform_init() {
    log "Initializing Terraform..."
    cd terraform
    terraform init
    cd ..
    log "Terraform initialized successfully"
}

# Plan deployment
terraform_plan() {
    log "Creating Terraform plan..."
    cd terraform
    terraform plan -out=tfplan
    cd ..
    log "Terraform plan created successfully"
}

# Apply deployment
terraform_apply() {
    local force=${1:-false}
    
    log "Applying Terraform configuration..."
    cd terraform
    
    if [ "$force" = true ]; then
        terraform apply -auto-approve
    else
        terraform apply
    fi
    
    cd ..
    log "Infrastructure deployed successfully"
    
    # Show outputs
    show_outputs
}

# Destroy infrastructure
terraform_destroy() {
    local force=${1:-false}
    
    warn "This will destroy all infrastructure!"
    
    if [ "$force" != true ]; then
        read -p "Are you sure you want to destroy the infrastructure? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log "Destruction cancelled"
            return 0
        fi
    fi
    
    log "Destroying infrastructure..."
    cd terraform
    terraform destroy -auto-approve
    cd ..
    log "Infrastructure destroyed successfully"
}

# Show outputs
show_outputs() {
    log "Infrastructure outputs:"
    cd terraform
    terraform output -json | jq -r '
        .server_ips.value[] as $ip |
        "Server IP: \($ip)"
    '
    
    if terraform output -json | jq -e '.load_balancer_ip.value' > /dev/null 2>&1; then
        terraform output -json | jq -r '
            "Load Balancer IP: \(.load_balancer_ip.value)"
        '
    fi
    
    terraform output -json | jq -r '
        .deployment_info.value.next_steps[] as $step |
        "Next Step: \($step)"
    '
    cd ..
}

# Switch provider
switch_provider() {
    local new_provider=$1
    
    if [ -z "$new_provider" ]; then
        error "Provider not specified"
    fi
    
    log "Switching to provider: $new_provider"
    
    # Update terraform.tfvars
    sed -i.bak "s/^cloud_provider = .*/cloud_provider = \"$new_provider\"/" terraform/terraform.tfvars
    
    # Reinitialize Terraform
    terraform_init
    
    log "Switched to $new_provider successfully"
}

# Validate Terraform configuration
validate_terraform() {
    log "Validating Terraform configuration..."
    cd terraform
    terraform validate
    cd ..
    log "Terraform configuration is valid"
}

# Generate SSH key if needed
generate_ssh_key() {
    if [ ! -f ~/.ssh/id_rsa.pub ]; then
        log "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        log "SSH key generated at ~/.ssh/id_rsa.pub"
    fi
    
    # Update terraform.tfvars with SSH key
    local ssh_key=$(cat ~/.ssh/id_rsa.pub)
    sed -i.bak "s|^ssh_public_key = .*|ssh_public_key = \"$ssh_key\"|" terraform/terraform.tfvars
}

# Cost estimation
estimate_costs() {
    local provider=${1:-$(grep '^cloud_provider' terraform/terraform.tfvars | cut -d'"' -f2)}
    local server_size=${2:-$(grep '^server_size' terraform/terraform.tfvars | cut -d'"' -f2)}
    local server_count=${3:-$(grep '^server_count' terraform/terraform.tfvars | cut -d'=' -f2 | tr -d ' ')}
    
    info "Cost estimation for $provider:"
    
    case $provider in
        hetzner)
            case $server_size in
                small) cost=8.21 ;;
                medium) cost=12.90 ;;
                large) cost=25.20 ;;
            esac
            ;;
        digitalocean)
            case $server_size in
                small) cost=24.00 ;;
                medium) cost=48.00 ;;
                large) cost=96.00 ;;
            esac
            ;;
        vultr)
            case $server_size in
                small) cost=20.00 ;;
                medium) cost=40.00 ;;
                large) cost=80.00 ;;
            esac
            ;;
        linode)
            case $server_size in
                small) cost=12.00 ;;
                medium) cost=24.00 ;;
                large) cost=48.00 ;;
            esac
            ;;
    esac
    
    local total_cost=$(echo "$cost * $server_count" | bc -l)
    info "Estimated monthly cost: \$${total_cost} USD (${server_count}x ${server_size} servers)"
}

# Main script logic
main() {
    local command=""
    local provider=""
    local environment=""
    local server_size=""
    local server_count=""
    local domain=""
    local force=false
    local verbose=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            init|plan|apply|destroy|output|switch|validate|help)
                command=$1
                shift
                ;;
            -p|--provider)
                provider="$2"
                shift 2
                ;;
            -e|--environment)
                environment="$2"
                shift 2
                ;;
            -s|--size)
                server_size="$2"
                shift 2
                ;;
            -c|--count)
                server_count="$2"
                shift 2
                ;;
            -d|--domain)
                domain="$2"
                shift 2
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    # Show help if no command
    if [ -z "$command" ]; then
        show_help
        exit 0
    fi
    
    # Set verbose mode
    if [ "$verbose" = true ]; then
        set -x
    fi
    
    # Check dependencies
    check_dependencies
    
    # Install Terraform if needed
    install_terraform
    
    # Execute command
    case $command in
        init)
            terraform_init
            ;;
        plan)
            validate_config
            check_provider_credentials "$provider"
            terraform_plan
            ;;
        apply)
            validate_config
            check_provider_credentials "$provider"
            estimate_costs "$provider" "$server_size" "$server_count"
            terraform_apply "$force"
            ;;
        destroy)
            terraform_destroy "$force"
            ;;
        output)
            show_outputs
            ;;
        switch)
            if [ -z "$provider" ]; then
                error "Provider required for switch command"
            fi
            switch_provider "$provider"
            ;;
        validate)
            validate_terraform
            ;;
        help)
            show_help
            ;;
        *)
            error "Unknown command: $command"
            ;;
    esac
}

# Run main function
main "$@"
