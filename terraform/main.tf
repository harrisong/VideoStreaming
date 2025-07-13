# Video Streaming Service - Multi-Cloud Terraform Configuration
# Supports Hetzner Cloud, DigitalOcean, Vultr, and Linode

terraform {
  required_version = ">= 1.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.34"
    }
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.17"
    }
    linode = {
      source  = "linode/linode"
      version = "~> 2.9"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.20"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# Variables
variable "cloud_provider" {
  description = "Cloud provider to use (hetzner, digitalocean, vultr, linode)"
  type        = string
  default     = "hetzner"
  
  validation {
    condition     = contains(["hetzner", "digitalocean", "vultr", "linode"], var.cloud_provider)
    error_message = "Cloud provider must be one of: hetzner, digitalocean, vultr, linode."
  }
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "server_count" {
  description = "Number of application servers"
  type        = number
  default     = 1
}

variable "server_size" {
  description = "Server size/type"
  type        = string
  default     = "small"
  
  validation {
    condition     = contains(["small", "medium", "large"], var.server_size)
    error_message = "Server size must be one of: small, medium, large."
  }
}

variable "enable_load_balancer" {
  description = "Enable load balancer for multiple servers"
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  description = "Enable monitoring stack (Prometheus/Grafana)"
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = "SSH public key for server access"
  type        = string
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

# Local values for provider-specific configurations
locals {
  # Server size mappings
  server_sizes = {
    hetzner = {
      small  = "cpx21"   # 3 vCPU, 8GB RAM
      medium = "cpx31"   # 4 vCPU, 8GB RAM
      large  = "cpx41"   # 8 vCPU, 16GB RAM
    }
    digitalocean = {
      small  = "s-2vcpu-4gb"    # 2 vCPU, 4GB RAM
      medium = "s-4vcpu-8gb"    # 4 vCPU, 8GB RAM
      large  = "s-8vcpu-16gb"   # 8 vCPU, 16GB RAM
    }
    vultr = {
      small  = "vc2-2c-4gb"     # 2 vCPU, 4GB RAM
      medium = "vc2-4c-8gb"     # 4 vCPU, 8GB RAM
      large  = "vc2-8c-16gb"    # 8 vCPU, 16GB RAM
    }
    linode = {
      small  = "g6-standard-2"  # 2 vCPU, 4GB RAM
      medium = "g6-standard-4"  # 4 vCPU, 8GB RAM
      large  = "g6-standard-8"  # 8 vCPU, 16GB RAM
    }
  }
  
  # Region mappings
  regions = {
    hetzner      = "nbg1"        # Nuremberg
    digitalocean = "fra1"        # Frankfurt
    vultr        = "fra"         # Frankfurt
    linode       = "eu-central"  # Frankfurt
  }
  
  # Image mappings
  images = {
    hetzner      = "ubuntu-22.04"
    digitalocean = "ubuntu-22-04-x64"
    vultr        = "ubuntu-22.04"
    linode       = "linode/ubuntu22.04"
  }
  
  # Common tags
  common_tags = {
    Environment = var.environment
    Project     = "video-streaming"
    ManagedBy   = "terraform"
  }
}

# Generate SSH key pair if not provided
resource "tls_private_key" "ssh_key" {
  count     = var.ssh_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  count           = var.ssh_public_key == "" ? 1 : 0
  content         = tls_private_key.ssh_key[0].private_key_pem
  filename        = "${path.module}/ssh_keys/id_rsa"
  file_permission = "0600"
}

resource "local_file" "public_key" {
  count           = var.ssh_public_key == "" ? 1 : 0
  content         = tls_private_key.ssh_key[0].public_key_openssh
  filename        = "${path.module}/ssh_keys/id_rsa.pub"
  file_permission = "0644"
}

# Provider configurations
provider "hcloud" {
  count = var.cloud_provider == "hetzner" ? 1 : 0
  # token = var.hcloud_token # Set via HCLOUD_TOKEN environment variable
}

provider "digitalocean" {
  count = var.cloud_provider == "digitalocean" ? 1 : 0
  # token = var.do_token # Set via DIGITALOCEAN_TOKEN environment variable
}

provider "vultr" {
  count = var.cloud_provider == "vultr" ? 1 : 0
  # api_key = var.vultr_api_key # Set via VULTR_API_KEY environment variable
}

provider "linode" {
  count = var.cloud_provider == "linode" ? 1 : 0
  # token = var.linode_token # Set via LINODE_TOKEN environment variable
}

# Include provider-specific modules
module "hetzner" {
  count  = var.cloud_provider == "hetzner" ? 1 : 0
  source = "./modules/hetzner"
  
  domain_name           = var.domain_name
  environment          = var.environment
  server_count         = var.server_count
  server_type          = local.server_sizes.hetzner[var.server_size]
  region               = local.regions.hetzner
  ssh_public_key       = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.ssh_key[0].public_key_openssh
  enable_load_balancer = var.enable_load_balancer
  enable_monitoring    = var.enable_monitoring
  common_tags          = local.common_tags
}

module "digitalocean" {
  count  = var.cloud_provider == "digitalocean" ? 1 : 0
  source = "./modules/digitalocean"
  
  domain_name           = var.domain_name
  environment          = var.environment
  server_count         = var.server_count
  server_size          = local.server_sizes.digitalocean[var.server_size]
  region               = local.regions.digitalocean
  ssh_public_key       = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.ssh_key[0].public_key_openssh
  enable_load_balancer = var.enable_load_balancer
  enable_monitoring    = var.enable_monitoring
  common_tags          = local.common_tags
}

module "vultr" {
  count  = var.cloud_provider == "vultr" ? 1 : 0
  source = "./modules/vultr"
  
  domain_name           = var.domain_name
  environment          = var.environment
  server_count         = var.server_count
  server_plan          = local.server_sizes.vultr[var.server_size]
  region               = local.regions.vultr
  ssh_public_key       = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.ssh_key[0].public_key_openssh
  enable_load_balancer = var.enable_load_balancer
  enable_monitoring    = var.enable_monitoring
  common_tags          = local.common_tags
}

module "linode" {
  count  = var.cloud_provider == "linode" ? 1 : 0
  source = "./modules/linode"
  
  domain_name           = var.domain_name
  environment          = var.environment
  server_count         = var.server_count
  server_type          = local.server_sizes.linode[var.server_size]
  region               = local.regions.linode
  ssh_public_key       = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.ssh_key[0].public_key_openssh
  enable_load_balancer = var.enable_load_balancer
  enable_monitoring    = var.enable_monitoring
  common_tags          = local.common_tags
}

# Outputs
output "server_ips" {
  description = "IP addresses of created servers"
  value = var.cloud_provider == "hetzner" ? (
    length(module.hetzner) > 0 ? module.hetzner[0].server_ips : []
  ) : var.cloud_provider == "digitalocean" ? (
    length(module.digitalocean) > 0 ? module.digitalocean[0].server_ips : []
  ) : var.cloud_provider == "vultr" ? (
    length(module.vultr) > 0 ? module.vultr[0].server_ips : []
  ) : var.cloud_provider == "linode" ? (
    length(module.linode) > 0 ? module.linode[0].server_ips : []
  ) : []
}

output "load_balancer_ip" {
  description = "Load balancer IP address (if enabled)"
  value = var.enable_load_balancer ? (
    var.cloud_provider == "hetzner" ? (
      length(module.hetzner) > 0 ? module.hetzner[0].load_balancer_ip : null
    ) : var.cloud_provider == "digitalocean" ? (
      length(module.digitalocean) > 0 ? module.digitalocean[0].load_balancer_ip : null
    ) : var.cloud_provider == "vultr" ? (
      length(module.vultr) > 0 ? module.vultr[0].load_balancer_ip : null
    ) : var.cloud_provider == "linode" ? (
      length(module.linode) > 0 ? module.linode[0].load_balancer_ip : null
    ) : null
  ) : null
}

output "ssh_connection_commands" {
  description = "SSH commands to connect to servers"
  value = var.cloud_provider == "hetzner" ? (
    length(module.hetzner) > 0 ? module.hetzner[0].ssh_connection_commands : []
  ) : var.cloud_provider == "digitalocean" ? (
    length(module.digitalocean) > 0 ? module.digitalocean[0].ssh_connection_commands : []
  ) : var.cloud_provider == "vultr" ? (
    length(module.vultr) > 0 ? module.vultr[0].ssh_connection_commands : []
  ) : var.cloud_provider == "linode" ? (
    length(module.linode) > 0 ? module.linode[0].ssh_connection_commands : []
  ) : []
}

output "deployment_info" {
  description = "Deployment information and next steps"
  value = {
    provider     = var.cloud_provider
    environment  = var.environment
    server_count = var.server_count
    server_size  = var.server_size
    domain       = var.domain_name
    next_steps = [
      "1. Update DNS records to point ${var.domain_name} to the server IP(s)",
      "2. Run the deployment script: ./deploy.sh",
      "3. Access your application at https://${var.domain_name}",
      "4. Monitor deployment logs: docker-compose -f docker-compose.prod.yml logs -f"
    ]
  }
}
