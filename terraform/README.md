# Terraform Infrastructure for Video Streaming Service

This directory contains Terraform configurations for deploying your video streaming service across multiple cloud providers with complete vendor lock-in avoidance.

## 🚀 Supported Cloud Providers

- **Hetzner Cloud** (Recommended - Most Cost-Effective)
- **DigitalOcean** (Good Balance)
- **Vultr** (Alternative Option)
- **Linode** (Reliable Choice)

## 📋 Prerequisites

1. **Terraform** (>= 1.0) - Will be auto-installed by the deployment script
2. **Cloud Provider API Token**
3. **Domain Name** (for SSL certificates)
4. **SSH Public Key**

## 🛠️ Quick Setup

### 1. Configure Variables
```bash
# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your settings
nano terraform.tfvars
```

### 2. Set API Credentials
```bash
# For Hetzner Cloud (Recommended)
export HCLOUD_TOKEN="your-hetzner-token"

# For DigitalOcean
export DIGITALOCEAN_TOKEN="your-do-token"

# For Vultr
export VULTR_API_KEY="your-vultr-key"

# For Linode
export LINODE_TOKEN="your-linode-token"
```

### 3. Deploy Infrastructure
```bash
# Initialize and deploy (from project root)
./terraform-deploy.sh init
./terraform-deploy.sh plan
./terraform-deploy.sh apply
```

## 📊 Cost Comparison

| Provider | Small (2-3 vCPU, 4-8GB) | Medium (4 vCPU, 8GB) | Large (8 vCPU, 16GB) |
|----------|-------------------------|----------------------|----------------------|
| **Hetzner** | €8.21/month (~$9) | €12.90/month (~$14) | €25.20/month (~$28) |
| **DigitalOcean** | $24/month | $48/month | $96/month |
| **Vultr** | $20/month | $40/month | $80/month |
| **Linode** | $12/month | $24/month | $48/month |

## 🏗️ Architecture Options

### Single Server (Recommended for MVP)
```hcl
server_count = 1
server_size = "small"
enable_load_balancer = false
```
**Cost**: $9-24/month depending on provider

### Multi-Server with Load Balancer
```hcl
server_count = 2
server_size = "small"
enable_load_balancer = true
```
**Cost**: $25-60/month depending on provider

### High Availability Setup
```hcl
server_count = 3
server_size = "medium"
enable_load_balancer = true
enable_monitoring = true
```
**Cost**: $50-150/month depending on provider

## 🔧 Configuration Options

### terraform.tfvars Example
```hcl
# Cloud provider selection
cloud_provider = "hetzner"  # hetzner, digitalocean, vultr, linode

# Basic configuration
domain_name = "yourdomain.com"
environment = "prod"

# Server configuration
server_count = 1
server_size = "small"  # small, medium, large

# Features
enable_load_balancer = false
enable_monitoring = false

# SSH access
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC..."

# Backup settings
backup_retention_days = 7
```

## 🚀 Deployment Commands

### Using the Deployment Script (Recommended)
```bash
# Initialize Terraform
./terraform-deploy.sh init

# Plan deployment
./terraform-deploy.sh plan --provider hetzner

# Deploy infrastructure
./terraform-deploy.sh apply --provider hetzner --domain yourdomain.com

# Switch providers (maintains state)
./terraform-deploy.sh switch --provider digitalocean

# Show infrastructure outputs
./terraform-deploy.sh output

# Destroy infrastructure
./terraform-deploy.sh destroy --force
```

### Manual Terraform Commands
```bash
cd terraform

# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply

# Destroy
terraform destroy
```

## 📤 Outputs

After deployment, Terraform provides:

```bash
# Server IP addresses
server_ips = [
  "1.2.3.4",
  "5.6.7.8"
]

# Load balancer IP (if enabled)
load_balancer_ip = "9.10.11.12"

# SSH connection commands
ssh_connection_commands = [
  "ssh deploy@1.2.3.4",
  "ssh deploy@5.6.7.8"
]

# Next steps
deployment_info = {
  next_steps = [
    "1. Update DNS records to point yourdomain.com to the server IP(s)",
    "2. Run the deployment script: ./deploy.sh",
    "3. Access your application at https://yourdomain.com"
  ]
}
```

## 🔄 Provider Migration

### Switching Between Providers
```bash
# Current: Hetzner Cloud
./terraform-deploy.sh switch --provider digitalocean

# This will:
# 1. Update terraform.tfvars
# 2. Reinitialize Terraform
# 3. Plan migration
# 4. Apply changes
```

### Zero-Downtime Migration Process
1. **Deploy to new provider** (parallel infrastructure)
2. **Sync data** (database, object storage)
3. **Update DNS** (point to new infrastructure)
4. **Verify functionality**
5. **Destroy old infrastructure**

## 🏗️ Module Structure

```
terraform/
├── main.tf                    # Main configuration
├── terraform.tfvars.example  # Configuration template
├── modules/
│   ├── hetzner/              # Hetzner Cloud module
│   │   ├── main.tf
│   │   └── cloud-init.yml
│   ├── digitalocean/         # DigitalOcean module (planned)
│   ├── vultr/               # Vultr module (planned)
│   └── linode/              # Linode module (planned)
└── README.md
```

## 🔒 Security Features

### Automatic Security Hardening
- **Firewall**: UFW configured with minimal open ports
- **Fail2ban**: Automatic IP blocking for failed SSH attempts
- **SSH**: Key-based authentication only
- **Updates**: Automatic security updates
- **User**: Non-root deployment user with sudo access

### Network Security
- **Private Networks**: Internal communication via private IPs
- **Security Groups**: Restrictive firewall rules
- **SSL/TLS**: Automatic Let's Encrypt certificates
- **HSTS**: HTTP Strict Transport Security headers

## 📊 Monitoring and Logging

### Built-in Health Checks
- **HTTP Health Endpoint**: `:8000/health`
- **Container Health**: Docker container status monitoring
- **System Resources**: CPU, memory, disk monitoring
- **Log Rotation**: Automatic log cleanup

### Optional Monitoring Stack
```hcl
enable_monitoring = true
```
Includes:
- **Prometheus**: Metrics collection
- **Grafana**: Visualization dashboards
- **AlertManager**: Alert notifications

## 💾 Backup Strategy

### Automated Backups
- **Database**: Daily PostgreSQL dumps
- **Object Storage**: MinIO data synchronization
- **Configuration**: Infrastructure state backups
- **Retention**: Configurable retention period

### Backup Locations
- **Local**: On-server backup directory
- **Remote**: Optional cloud storage integration
- **Cross-Region**: Multi-region backup replication

## 🔧 Customization

### Adding New Providers
1. Create new module in `modules/provider-name/`
2. Add provider configuration to `main.tf`
3. Update deployment script with provider support
4. Test deployment and document costs

### Custom Server Configurations
```hcl
# Custom server sizes
locals {
  server_sizes = {
    custom_provider = {
      micro  = "custom-micro-plan"
      small  = "custom-small-plan"
      medium = "custom-medium-plan"
      large  = "custom-large-plan"
    }
  }
}
```

## 🚨 Troubleshooting

### Common Issues

#### 1. API Token Issues
```bash
# Check token is set
echo $HCLOUD_TOKEN

# Test API access
curl -H "Authorization: Bearer $HCLOUD_TOKEN" \
  https://api.hetzner-cloud.com/v1/servers
```

#### 2. SSH Key Problems
```bash
# Generate new SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa

# Update terraform.tfvars
ssh_public_key = "$(cat ~/.ssh/id_rsa.pub)"
```

#### 3. Domain DNS Issues
```bash
# Check DNS propagation
dig yourdomain.com
nslookup yourdomain.com
```

#### 4. Terraform State Issues
```bash
# Refresh state
terraform refresh

# Import existing resources
terraform import hcloud_server.app 12345
```

### Getting Help

1. **Check Logs**: `terraform-deploy.sh output`
2. **Validate Config**: `terraform-deploy.sh validate`
3. **Plan Changes**: `terraform-deploy.sh plan`
4. **Provider Docs**: Check cloud provider documentation
5. **Terraform Docs**: [terraform.io](https://terraform.io)

## 📈 Scaling Strategies

### Vertical Scaling
```bash
# Upgrade server size
./terraform-deploy.sh plan --size medium
./terraform-deploy.sh apply
```

### Horizontal Scaling
```bash
# Add more servers
./terraform-deploy.sh plan --count 3 --enable-load-balancer
./terraform-deploy.sh apply
```

### Multi-Region Deployment
```hcl
# Deploy to multiple regions
module "us_east" {
  source = "./modules/hetzner"
  region = "ash"  # Ashburn
  # ... other config
}

module "eu_central" {
  source = "./modules/hetzner"
  region = "nbg1"  # Nuremberg
  # ... other config
}
```

## 🎯 Best Practices

### 1. State Management
- Use remote state storage (S3, GCS, etc.)
- Enable state locking
- Regular state backups

### 2. Environment Separation
- Separate Terraform workspaces for dev/staging/prod
- Different variable files per environment
- Isolated state files

### 3. Security
- Never commit API tokens to version control
- Use environment variables for secrets
- Regular security updates

### 4. Cost Optimization
- Start with small instances
- Monitor resource usage
- Scale based on actual demand
- Use reserved instances for long-term deployments

## 🔄 CI/CD Integration

### GitHub Actions Example
```yaml
name: Deploy Infrastructure
on:
  push:
    branches: [main]
    paths: ['terraform/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
      - name: Deploy
        env:
          HCLOUD_TOKEN: ${{ secrets.HCLOUD_TOKEN }}
        run: |
          ./terraform-deploy.sh init
          ./terraform-deploy.sh apply --force
```

This Terraform setup provides complete infrastructure automation with maximum flexibility and vendor lock-in avoidance for your video streaming service.
