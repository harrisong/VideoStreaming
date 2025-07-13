# Local Development with Terraform

Yes! You can and should run Terraform locally. This is the standard and recommended approach for infrastructure management.

## 🖥️ Running Terraform Locally

### Prerequisites
- **Your local machine** (macOS, Linux, or Windows)
- **Internet connection** (to communicate with cloud provider APIs)
- **Cloud provider API token** (stored as environment variable)

### How It Works
```
Your Local Machine → Cloud Provider API → Cloud Infrastructure
     (Terraform)         (HTTPS calls)        (Servers created)
```

## 🚀 Local Setup Guide

### 1. Install Terraform Locally

#### Option A: Automatic Installation (Recommended)
```bash
# The deployment script will auto-install Terraform
./terraform-deploy.sh init
```

#### Option B: Manual Installation

**macOS (using Homebrew):**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

**Linux (Ubuntu/Debian):**
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

**Windows (using Chocolatey):**
```powershell
choco install terraform
```

### 2. Configure Your Local Environment

#### Set Up API Credentials
```bash
# For Hetzner Cloud (recommended - cheapest)
export HCLOUD_TOKEN="your-hetzner-api-token"

# For DigitalOcean
export DIGITALOCEAN_TOKEN="your-digitalocean-token"

# For Vultr
export VULTR_API_KEY="your-vultr-api-key"

# For Linode
export LINODE_TOKEN="your-linode-token"

# Make them persistent (add to ~/.bashrc or ~/.zshrc)
echo 'export HCLOUD_TOKEN="your-token-here"' >> ~/.bashrc
```

#### Configure Terraform Variables
```bash
# Copy the example configuration
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Edit with your settings
nano terraform/terraform.tfvars
```

### 3. Deploy from Your Local Machine

#### Using the Deployment Script (Recommended)
```bash
# Initialize Terraform
./terraform-deploy.sh init

# Plan the deployment (see what will be created)
./terraform-deploy.sh plan

# Deploy infrastructure
./terraform-deploy.sh apply

# Check what was created
./terraform-deploy.sh output
```

#### Using Terraform Commands Directly
```bash
cd terraform

# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply

# Show outputs
terraform output
```

## 🏠 Local vs Cloud Execution

### Local Execution (Recommended)
```
✅ Your laptop/desktop runs Terraform
✅ Terraform state stored locally (or remote backend)
✅ You control when deployments happen
✅ Easy to version control and collaborate
✅ No additional costs
✅ Works offline for planning
```

### Cloud Execution (Alternative)
```
❓ CI/CD pipeline runs Terraform
❓ Requires setting up CI/CD infrastructure
❓ Additional complexity for simple deployments
❓ Good for team environments
```

## 📁 Local Project Structure

Your local development setup:
```
VideoStreaming/                    # Your project root
├── terraform/                     # Terraform configurations
│   ├── main.tf                   # Main configuration
│   ├── terraform.tfvars          # Your variables (local)
│   ├── terraform.tfstate         # State file (local)
│   └── modules/                  # Provider modules
├── terraform-deploy.sh           # Deployment script
├── docker-compose.prod.yml       # Production config
└── deploy.sh                     # Application deployment
```

## 🔄 Local Development Workflow

### 1. Develop Infrastructure Locally
```bash
# Make changes to terraform files
nano terraform/main.tf

# Test changes
./terraform-deploy.sh plan

# Apply when ready
./terraform-deploy.sh apply
```

### 2. Test Different Providers
```bash
# Test with Hetzner (cheapest)
./terraform-deploy.sh plan --provider hetzner

# Test with DigitalOcean
./terraform-deploy.sh plan --provider digitalocean

# Switch providers easily
./terraform-deploy.sh switch --provider vultr
```

### 3. Manage Multiple Environments
```bash
# Development environment
cp terraform.tfvars terraform-dev.tfvars
terraform workspace new dev
terraform apply -var-file="terraform-dev.tfvars"

# Production environment
cp terraform.tfvars terraform-prod.tfvars
terraform workspace new prod
terraform apply -var-file="terraform-prod.tfvars"
```

## 💻 Local Development Benefits

### Cost-Effective Testing
```bash
# Plan without applying (free)
terraform plan

# Test with smallest instances
server_size = "small"
server_count = 1

# Destroy when done testing
terraform destroy
```

### Rapid Iteration
```bash
# Make changes locally
# Test immediately
# Deploy when ready
# No waiting for CI/CD pipelines
```

### Full Control
```bash
# You decide when to deploy
# You can pause/resume deployments
# Easy rollbacks
# Direct access to all Terraform features
```

## 🔒 Security for Local Development

### Protect Your API Tokens
```bash
# Never commit tokens to git
echo "terraform.tfvars" >> .gitignore
echo "*.tfstate*" >> .gitignore

# Use environment variables
export HCLOUD_TOKEN="your-token"

# Or use a secrets manager
# aws secretsmanager get-secret-value --secret-id terraform-tokens
```

### State File Security
```bash
# Local state (simple)
# State stored in terraform/terraform.tfstate

# Remote state (recommended for teams)
terraform {
  backend "s3" {
    bucket = "your-terraform-state"
    key    = "video-streaming/terraform.tfstate"
    region = "us-west-2"
  }
}
```

## 🚀 Quick Local Setup Commands

### Complete Local Setup (5 minutes)
```bash
# 1. Clone your project
git clone https://github.com/yourusername/VideoStreaming.git
cd VideoStreaming

# 2. Get API token from Hetzner Cloud Console
# https://console.hetzner-cloud.com/

# 3. Set environment variable
export HCLOUD_TOKEN="your-hetzner-token-here"

# 4. Configure Terraform
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your domain and SSH key

# 5. Deploy infrastructure
./terraform-deploy.sh init
./terraform-deploy.sh apply

# 6. Get server IP and deploy application
./terraform-deploy.sh output
# SSH to server and run ./deploy.sh
```

## 🌐 Local to Cloud Communication

### How Terraform Communicates
```
Local Machine                    Cloud Provider
┌─────────────┐                 ┌──────────────┐
│  Terraform  │ ──── HTTPS ──→  │  Hetzner API │
│   (Your PC) │                 │              │
└─────────────┘                 └──────────────┘
                                        │
                                        ▼
                                ┌──────────────┐
                                │   Servers    │
                                │   Created    │
                                └──────────────┘
```

### What Gets Created in the Cloud
- **Servers**: Virtual machines running your application
- **Networks**: Private networks for security
- **Firewalls**: Security rules
- **Load Balancers**: Traffic distribution (optional)
- **Storage**: Persistent volumes for data

### What Stays Local
- **Terraform code**: Your infrastructure definitions
- **State file**: Current infrastructure state
- **Configuration**: Your settings and variables
- **Control**: You manage everything from your machine

## 🎯 Best Practices for Local Development

### 1. Version Control
```bash
# Track infrastructure changes
git add terraform/
git commit -m "Add load balancer configuration"
git push
```

### 2. Environment Separation
```bash
# Use Terraform workspaces
terraform workspace new development
terraform workspace new production
terraform workspace select production
```

### 3. Cost Management
```bash
# Always plan before applying
terraform plan

# Use small instances for testing
server_size = "small"

# Destroy test environments
terraform destroy
```

### 4. Backup State Files
```bash
# Backup your state file
cp terraform.tfstate terraform.tfstate.backup

# Or use remote state storage
# (S3, Google Cloud Storage, etc.)
```

## 🔧 Troubleshooting Local Setup

### Common Issues

#### 1. Terraform Not Found
```bash
# Check if installed
terraform version

# Install if missing
./terraform-deploy.sh init  # Auto-installs
```

#### 2. API Token Issues
```bash
# Check token is set
echo $HCLOUD_TOKEN

# Test API access
curl -H "Authorization: Bearer $HCLOUD_TOKEN" \
  https://api.hetzner-cloud.com/v1/servers
```

#### 3. Permission Issues
```bash
# Make scripts executable
chmod +x terraform-deploy.sh
chmod +x deploy.sh
```

#### 4. State File Conflicts
```bash
# If state gets corrupted
terraform refresh
# Or restore from backup
cp terraform.tfstate.backup terraform.tfstate
```

Running Terraform locally is not only possible but is the standard and recommended approach. It gives you full control, costs nothing extra, and allows for rapid development and testing of your infrastructure.
