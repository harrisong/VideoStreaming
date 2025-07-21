# Video Streaming Service - AWS Terraform Configuration
# Simplified version for AWS deployment only

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
  description = "Number of ECS tasks"
  type        = number
  default     = 2
}

variable "server_size" {
  description = "Server/instance size (small, medium, large)"
  type        = string
  default     = "small"
  
  validation {
    condition     = contains(["small", "medium", "large"], var.server_size)
    error_message = "Server size must be one of: small, medium, large."
  }
}

variable "instance_type" {
  description = "Instance type (alias for server_size for compatibility)"
  type        = string
  default     = ""
}

variable "enable_load_balancer" {
  description = "Enable load balancer (always true for AWS)"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable monitoring (CloudWatch)"
  type        = bool
  default     = true
}

variable "ssh_public_key" {
  description = "SSH public key (optional for managed services)"
  type        = string
  default     = ""
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

# Local values
locals {
  # ECS task size mappings
  task_sizes = {
    small  = { cpu = 512, memory = 1024 }   # ~$25/month for 2 tasks
    medium = { cpu = 1024, memory = 2048 }  # ~$50/month for 2 tasks
    large  = { cpu = 2048, memory = 4096 }  # ~$100/month for 2 tasks
  }
  
  region = "us-west-2"  # Oregon
  
  common_tags = {
    Environment = var.environment
    Project     = "video-streaming"
    ManagedBy   = "terraform"
  }
}

# Generate SSH key pair if not provided (optional for AWS managed services)
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

# AWS Provider
provider "aws" {
  region = local.region
  # Credentials via AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables
}

# AWS Provider for us-east-1 (required for CloudFront certificates)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  # Credentials via AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables
}

# AWS Module
module "aws" {
  source = "./modules/aws"
  
  providers = {
    aws.us_east_1 = aws.us_east_1
  }
  
  domain_name           = var.domain_name
  environment          = var.environment
  server_count         = var.server_count
  instance_type        = var.server_size
  region               = local.region
  ssh_public_key       = var.ssh_public_key != "" ? var.ssh_public_key : (length(tls_private_key.ssh_key) > 0 ? tls_private_key.ssh_key[0].public_key_openssh : "")
  enable_load_balancer = var.enable_load_balancer
  enable_monitoring    = var.enable_monitoring
  common_tags          = local.common_tags
}

# Outputs
output "server_ips" {
  description = "ECS service endpoint"
  value       = module.aws.server_ips
}

output "load_balancer_ip" {
  description = "Application Load Balancer DNS name"
  value       = module.aws.load_balancer_ip
}

output "ssh_connection_commands" {
  description = "Connection information"
  value       = module.aws.ssh_connection_commands
}

output "aws_resources" {
  description = "AWS resource information"
  value       = module.aws.server_info
}

output "ecr_repositories" {
  description = "ECR repository URLs for Docker images"
  value       = module.aws.ecr_repositories
}

output "scraper_api_url" {
  description = "API Gateway URL for triggering scraper"
  value       = module.aws.scraper_api_url
}

output "database_endpoint" {
  description = "RDS database endpoint"
  value       = module.aws.database_endpoint
}

output "s3_buckets" {
  description = "S3 bucket names"
  value       = module.aws.s3_buckets
}

output "deployment_info" {
  description = "Deployment information and next steps"
  value = {
    provider     = "aws"
    environment  = var.environment
    server_count = var.server_count
    server_size  = var.server_size
    domain       = var.domain_name
    region       = local.region
    scraper_api  = module.aws.scraper_api_url
    ecr_repos    = module.aws.ecr_repositories
    next_steps = [
      "1. Build and push Docker images to ECR:",
      "   - Backend: ${module.aws.ecr_repositories.backend}",
      "   - Frontend: ${module.aws.ecr_repositories.frontend}",
      "   - Scraper: ${module.aws.ecr_repositories.scraper}",
      "2. Update DNS records to point ${var.domain_name} to the ALB",
      "3. Access your application at https://${var.domain_name}",
      "4. Use scraper API at ${module.aws.scraper_api_url}",
      "5. Monitor via CloudWatch logs and dashboards"
    ]
  }
}
