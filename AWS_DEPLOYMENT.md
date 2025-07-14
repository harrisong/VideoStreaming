# AWS Managed Services Deployment Guide

Deploy your video streaming service to AWS using fully managed services for maximum scalability and minimal maintenance.

## 🏗️ AWS Architecture Overview

Your video streaming service will use these AWS managed services:

### **Compute & Networking**
- **ECS Fargate**: Serverless containers for your application
- **Application Load Balancer**: Traffic distribution and SSL termination
- **VPC**: Isolated network with public/private subnets
- **NAT Gateway**: Secure outbound internet access for private subnets

### **Storage & Database**
- **RDS PostgreSQL**: Managed database with automated backups
- **ElastiCache Redis**: Managed in-memory cache
- **S3**: Object storage for videos and static assets
- **CloudFront**: Global CDN for fast content delivery

### **Security & Monitoring**
- **ACM**: Automatic SSL certificate management
- **CloudWatch**: Logging and monitoring
- **IAM**: Fine-grained access control
- **Security Groups**: Network-level security

## 💰 Cost Estimation

### **Small Setup (Development/Testing)**
```
ECS Fargate (2 tasks, small):     ~$25/month
RDS PostgreSQL (db.t3.micro):    ~$15/month
ElastiCache Redis (cache.t3.micro): ~$15/month
ALB:                              ~$20/month
NAT Gateway:                      ~$45/month
S3 Storage (100GB):               ~$3/month
CloudFront:                       ~$5/month
Total:                            ~$128/month
```

### **Medium Setup (Production)**
```
ECS Fargate (4 tasks, medium):    ~$80/month
RDS PostgreSQL (db.t3.small):    ~$30/month
ElastiCache Redis (cache.t3.small): ~$30/month
ALB:                              ~$20/month
NAT Gateway (2 AZs):              ~$90/month
S3 Storage (500GB):               ~$12/month
CloudFront:                       ~$15/month
Total:                            ~$277/month
```

### **Large Setup (High Traffic)**
```
ECS Fargate (8 tasks, large):     ~$320/month
RDS PostgreSQL (db.t3.medium):   ~$60/month
ElastiCache Redis (cache.t3.medium): ~$60/month
ALB:                              ~$20/month
NAT Gateway (2 AZs):              ~$90/month
S3 Storage (1TB):                 ~$24/month
CloudFront:                       ~$30/month
Total:                            ~$604/month
```

## 🚀 Quick Deployment

### Prerequisites
1. **AWS Account** with appropriate permissions
2. **AWS CLI** configured with your credentials
3. **Domain name** for your application
4. **Docker images** pushed to ECR (we'll help with this)

### Step 1: Configure AWS Credentials
```bash
# Option 1: AWS CLI
aws configure
# Enter your Access Key ID, Secret Access Key, and region

# Option 2: Environment Variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-west-2"
```

### Step 2: Configure Terraform
```bash
# Copy configuration template
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Edit configuration
nano terraform/terraform.tfvars
```

**Minimum configuration for AWS:**
```hcl
# AWS deployment
cloud_provider = "aws"
domain_name = "yourdomain.com"
environment = "prod"

# Server configuration
server_count = 2
server_size = "small"  # small, medium, large

# Features (always enabled for AWS)
enable_load_balancer = true
enable_monitoring = true

# SSH key (optional for managed services)
ssh_public_key = ""
```

### Step 3: Deploy Infrastructure
```bash
# Initialize Terraform
./terraform-deploy.sh init

# Plan deployment
./terraform-deploy.sh plan --provider aws

# Deploy infrastructure
./terraform-deploy.sh apply --provider aws --domain yourdomain.com
```

### Step 4: Build and Push Docker Images
```bash
# Get ECR login token
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin YOUR_ACCOUNT.dkr.ecr.us-west-2.amazonaws.com

# Build and push backend
docker build -t video-streaming-backend ./rust-backend
docker tag video-streaming-backend:latest YOUR_ACCOUNT.dkr.ecr.us-west-2.amazonaws.com/prod-video-streaming-backend:latest
docker push YOUR_ACCOUNT.dkr.ecr.us-west-2.amazonaws.com/prod-video-streaming-backend:latest

# Build and push frontend
docker build -t video-streaming-frontend ./frontend
docker tag video-streaming-frontend:latest YOUR_ACCOUNT.dkr.ecr.us-west-2.amazonaws.com/prod-video-streaming-frontend:latest
docker push YOUR_ACCOUNT.dkr.ecr.us-west-2.amazonaws.com/prod-video-streaming-frontend:latest
```

### Step 5: Update ECS Service
```bash
# Update ECS service to use new images
aws ecs update-service --cluster prod-video-streaming --service prod-video-streaming --force-new-deployment
```

### Step 6: Configure DNS
Point your domain to the Application Load Balancer:
```bash
# Get ALB DNS name from Terraform output
terraform output load_balancer_ip

# Create DNS records
# A record: yourdomain.com -> ALB DNS name
# CNAME record: *.yourdomain.com -> ALB DNS name
```

## 🔧 Advanced Configuration

### Multi-Environment Setup
```bash
# Development environment
cp terraform.tfvars terraform-dev.tfvars
# Edit terraform-dev.tfvars with dev settings

# Deploy development
terraform workspace new dev
terraform apply -var-file="terraform-dev.tfvars"

# Production environment
terraform workspace new prod
terraform apply -var-file="terraform.tfvars"
```

### Auto Scaling Configuration
```hcl
# In terraform.tfvars
server_count = 2  # Minimum tasks
# ECS will auto-scale based on CPU/memory usage
```

### Database Configuration
```hcl
# Custom database settings
variable "db_instance_class" {
  default = "db.t3.small"  # Upgrade for production
}

variable "db_allocated_storage" {
  default = 100  # GB
}
```

### Monitoring and Alerting
```bash
# CloudWatch alarms are automatically created
# View in AWS Console -> CloudWatch -> Alarms

# Custom metrics
aws cloudwatch put-metric-data --namespace "VideoStreaming/prod" --metric-data MetricName=CustomMetric,Value=1
```

## 📊 Monitoring and Management

### CloudWatch Dashboards
Access pre-configured dashboards:
- **ECS Service Metrics**: CPU, Memory, Task count
- **RDS Metrics**: Database performance
- **ALB Metrics**: Request count, latency
- **Application Logs**: Centralized logging

### ECS Management
```bash
# View running tasks
aws ecs list-tasks --cluster prod-video-streaming

# Connect to running container
aws ecs execute-command --cluster prod-video-streaming --task TASK_ID --container backend --interactive --command "/bin/bash"

# View service logs
aws logs tail /ecs/prod-video-streaming --follow
```

### Database Management
```bash
# Connect to RDS instance
psql -h YOUR_RDS_ENDPOINT -U postgres -d video_streaming_db

# Create database backup
aws rds create-db-snapshot --db-instance-identifier prod-video-streaming-db --db-snapshot-identifier manual-backup-$(date +%Y%m%d)
```

### S3 Management
```bash
# List video files
aws s3 ls s3://your-video-bucket/

# Sync local files to S3
aws s3 sync ./local-videos/ s3://your-video-bucket/videos/

# Set up lifecycle policies for cost optimization
aws s3api put-bucket-lifecycle-configuration --bucket your-video-bucket --lifecycle-configuration file://lifecycle.json
```

## 🔒 Security Best Practices

### IAM Roles and Policies
- **ECS Task Role**: Minimal permissions for S3 access
- **ECS Execution Role**: Container registry and logging access
- **RDS**: Encrypted at rest and in transit
- **S3**: Server-side encryption enabled

### Network Security
- **Private Subnets**: Application runs in private subnets
- **Security Groups**: Restrictive inbound rules
- **NAT Gateway**: Secure outbound internet access
- **VPC Flow Logs**: Network traffic monitoring

### SSL/TLS Configuration
- **ACM Certificates**: Automatic SSL certificate management
- **ALB**: SSL termination and HTTPS redirect
- **Security Headers**: HSTS, CSP headers configured

## 💾 Backup and Disaster Recovery

### Automated Backups
- **RDS**: 7-day automated backups
- **S3**: Versioning enabled
- **ECS**: Stateless containers (no backup needed)

### Manual Backup Procedures
```bash
# Database backup
aws rds create-db-snapshot --db-instance-identifier prod-video-streaming-db --db-snapshot-identifier manual-$(date +%Y%m%d)

# S3 cross-region replication
aws s3api put-bucket-replication --bucket source-bucket --replication-configuration file://replication.json
```

### Disaster Recovery
1. **RDS**: Point-in-time recovery available
2. **S3**: Cross-region replication
3. **ECS**: Multi-AZ deployment
4. **Infrastructure**: Terraform state for quick rebuild

## 📈 Scaling Strategies

### Horizontal Scaling
```bash
# Increase ECS task count
aws ecs update-service --cluster prod-video-streaming --service prod-video-streaming --desired-count 4

# Auto Scaling based on metrics
aws application-autoscaling register-scalable-target --service-namespace ecs --scalable-dimension ecs:service:DesiredCount --resource-id service/prod-video-streaming/prod-video-streaming --min-capacity 2 --max-capacity 10
```

### Vertical Scaling
```hcl
# Upgrade task size in terraform.tfvars
server_size = "medium"  # or "large"

# Apply changes
terraform apply
```

### Database Scaling
```bash
# Upgrade RDS instance
aws rds modify-db-instance --db-instance-identifier prod-video-streaming-db --db-instance-class db.t3.medium --apply-immediately
```

## 🚨 Troubleshooting

### Common Issues

#### 1. ECS Tasks Not Starting
```bash
# Check service events
aws ecs describe-services --cluster prod-video-streaming --services prod-video-streaming

# Check task definition
aws ecs describe-task-definition --task-definition prod-video-streaming

# View container logs
aws logs tail /ecs/prod-video-streaming --follow
```

#### 2. Database Connection Issues
```bash
# Test database connectivity
aws rds describe-db-instances --db-instance-identifier prod-video-streaming-db

# Check security groups
aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx
```

#### 3. Load Balancer Health Checks Failing
```bash
# Check target group health
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:...

# View ALB access logs
aws s3 ls s3://your-alb-logs-bucket/
```

#### 4. SSL Certificate Issues
```bash
# Check certificate status
aws acm describe-certificate --certificate-arn arn:aws:acm:...

# Validate domain ownership
aws acm list-certificates --certificate-statuses ISSUED,PENDING_VALIDATION
```

## 💡 Cost Optimization Tips

### 1. Right-sizing Resources
- Start with smaller instances and scale up based on usage
- Use CloudWatch metrics to identify over-provisioned resources
- Consider Reserved Instances for predictable workloads

### 2. Storage Optimization
- Use S3 Intelligent Tiering for automatic cost optimization
- Implement lifecycle policies to move old data to cheaper storage classes
- Enable S3 compression for static assets

### 3. Network Optimization
- Use CloudFront for global content delivery
- Optimize data transfer between services
- Consider VPC endpoints for S3 access to avoid NAT Gateway costs

### 4. Monitoring and Alerts
```bash
# Set up billing alerts
aws budgets create-budget --account-id YOUR_ACCOUNT_ID --budget file://budget.json

# Cost anomaly detection
aws ce create-anomaly-detector --anomaly-detector file://detector.json
```

## 🔄 CI/CD Integration

### GitHub Actions Example
```yaml
name: Deploy to AWS
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-west-2
      
      - name: Deploy infrastructure
        run: |
          ./terraform-deploy.sh apply --provider aws --force
      
      - name: Build and push images
        run: |
          # Build and push Docker images
          # Update ECS service
```

## 🎯 Production Checklist

### Before Going Live
- [ ] SSL certificate validated and applied
- [ ] DNS records configured correctly
- [ ] Database backups tested
- [ ] Monitoring and alerting configured
- [ ] Security groups reviewed
- [ ] Cost budgets and alerts set up
- [ ] Disaster recovery plan documented
- [ ] Performance testing completed

### Post-Deployment
- [ ] Monitor CloudWatch dashboards
- [ ] Verify application functionality
- [ ] Test backup and restore procedures
- [ ] Review security configurations
- [ ] Optimize costs based on usage patterns

This AWS deployment provides enterprise-grade infrastructure with automatic scaling, high availability, and comprehensive monitoring while maintaining cost efficiency through managed services.
