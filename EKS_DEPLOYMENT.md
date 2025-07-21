# EKS Deployment Guide

This guide explains how to deploy your Video Streaming Service to Amazon EKS (Elastic Kubernetes Service) instead of ECS.

## Overview

The EKS deployment provides the same functionality as the ECS deployment but uses Kubernetes for container orchestration. This offers several advantages:

- **Better scalability**: Kubernetes provides more sophisticated scaling options
- **Multi-cloud portability**: Kubernetes workloads can run on any cloud provider
- **Rich ecosystem**: Access to the vast Kubernetes ecosystem of tools and operators
- **Advanced networking**: More flexible networking options with service mesh support
- **Better resource management**: More granular control over resource allocation

## Architecture

The EKS deployment maintains the same multi-container architecture:

```
┌─────────────────────────────────────────────────────────────────┐
│                        CloudFront CDN                          │
└─────────────────────┬───────────────────────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────────────────────┐
│                Application Load Balancer                       │
└─────────────────────┬───────────────────────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────────────────────┐
│                     EKS Cluster                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Pod                                  │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐   │   │
│  │  │    Nginx    │ │  Frontend   │ │     Backend     │   │   │
│  │  │   Proxy     │ │   (React)   │ │     (Rust)      │   │   │
│  │  │             │ │             │ │                 │   │   │
│  │  └─────────────┘ └─────────────┘ └─────────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                      │                    │
        ┌─────────────┴──────────┐ ┌──────┴──────────┐
        │     RDS PostgreSQL     │ │ ElastiCache     │
        │                        │ │ Redis           │
        └────────────────────────┘ └─────────────────┘
```

## Prerequisites

Before deploying to EKS, ensure you have the following tools installed:

1. **AWS CLI** - For AWS authentication and resource management
2. **kubectl** - Kubernetes command-line tool
3. **Terraform** - Infrastructure as Code tool
4. **Docker** - For building container images

### Installing kubectl

```bash
# macOS
brew install kubectl

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Windows
choco install kubernetes-cli
```

## Deployment Process

### 1. Environment Setup

Set your environment variables:

```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-west-2
export DOMAIN_NAME=your-domain.com
export ENVIRONMENT=prod
```

### 2. Deploy with EKS Script

Use the provided EKS deployment script:

```bash
# Make the script executable
chmod +x eks-deploy.sh

# Run the deployment
./eks-deploy.sh
```

The script will:
1. Build and push Docker images to ECR
2. Deploy EKS infrastructure with Terraform
3. Configure kubectl for the new cluster
4. Deploy Kubernetes manifests
5. Run database migrations
6. Wait for the deployment to be ready

### 3. Manual Deployment (Alternative)

If you prefer to run each step manually:

#### Step 1: Build and Push Images
```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-west-2
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export ENVIRONMENT=prod

./build-and-push.sh
```

#### Step 2: Deploy Infrastructure
```bash
cd terraform
terraform init
terraform plan -var="domain_name=your-domain.com" -var="environment=prod"
terraform apply
```

#### Step 3: Configure kubectl
```bash
aws eks update-kubeconfig --region us-west-2 --name prod-video-streaming-eks
```

#### Step 4: Deploy Kubernetes Resources
```bash
# Update manifests with actual values
# (This is automated in the eks-deploy.sh script)

kubectl apply -f k8s/processed/namespace.yaml
kubectl apply -f k8s/processed/secrets.yaml
kubectl apply -f k8s/processed/serviceaccount.yaml
kubectl apply -f k8s/processed/service.yaml
kubectl apply -f k8s/processed/deployment.yaml
kubectl apply -f k8s/processed/jobs.yaml
```

## Kubernetes Resources

The deployment creates the following Kubernetes resources:

### Namespace
- `video-streaming` - Isolates all application resources

### Deployment
- `video-streaming-app` - Main application deployment with 3 containers:
  - **nginx-proxy**: Routes traffic and serves static files
  - **frontend**: React application
  - **backend**: Rust API server

### Services
- `video-streaming-service` - NodePort service (port 30080) for ALB integration
- `video-streaming-backend` - ClusterIP service for internal backend access
- `video-streaming-frontend` - ClusterIP service for internal frontend access

### Jobs
- `video-streaming-db-migration` - One-time database migration job
- `video-streaming-scraper` - Template for on-demand video scraping

### ConfigMap & Secrets
- `video-streaming-config` - Non-sensitive configuration
- `video-streaming-secrets` - Database credentials and API keys

## Monitoring and Management

### Useful kubectl Commands

```bash
# Check pod status
kubectl get pods -n video-streaming

# View pod logs
kubectl logs -f deployment/video-streaming-app -n video-streaming -c backend
kubectl logs -f deployment/video-streaming-app -n video-streaming -c frontend
kubectl logs -f deployment/video-streaming-app -n video-streaming -c nginx-proxy

# Execute commands in pods
kubectl exec -it deployment/video-streaming-app -n video-streaming -c backend -- /bin/bash

# Check service status
kubectl get services -n video-streaming

# View deployment status
kubectl get deployments -n video-streaming

# Check job status
kubectl get jobs -n video-streaming

# Scale deployment
kubectl scale deployment video-streaming-app -n video-streaming --replicas=3

# Rolling update
kubectl rollout restart deployment/video-streaming-app -n video-streaming
kubectl rollout status deployment/video-streaming-app -n video-streaming
```

### Monitoring Resources

```bash
# Watch pods in real-time
kubectl get pods -n video-streaming -w

# Check resource usage
kubectl top pods -n video-streaming
kubectl top nodes

# View events
kubectl get events -n video-streaming --sort-by='.lastTimestamp'
```

## Scaling

### Horizontal Pod Autoscaler (HPA)

Create an HPA to automatically scale based on CPU usage:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: video-streaming-hpa
  namespace: video-streaming
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: video-streaming-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

Apply with:
```bash
kubectl apply -f hpa.yaml
```

### Cluster Autoscaler

The EKS node group is configured with auto-scaling. Nodes will be added/removed based on pod scheduling needs.

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending state**
   ```bash
   kubectl describe pod <pod-name> -n video-streaming
   ```
   Usually indicates resource constraints or node issues.

2. **ImagePullBackOff errors**
   ```bash
   kubectl describe pod <pod-name> -n video-streaming
   ```
   Check ECR repository permissions and image tags.

3. **Database connection issues**
   ```bash
   kubectl logs deployment/video-streaming-app -n video-streaming -c backend
   ```
   Verify database endpoint and credentials in secrets.

4. **Service not accessible**
   ```bash
   kubectl get svc -n video-streaming
   kubectl describe svc video-streaming-service -n video-streaming
   ```
   Check NodePort configuration and ALB target group health.

### Debug Commands

```bash
# Check cluster info
kubectl cluster-info

# Verify node status
kubectl get nodes

# Check system pods
kubectl get pods -n kube-system

# View cluster events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Check EKS cluster status
aws eks describe-cluster --name prod-video-streaming-eks --region us-west-2
```

## Security Considerations

### RBAC
The deployment uses Kubernetes RBAC with a dedicated service account that has minimal required permissions.

### Network Policies
Consider implementing network policies to restrict pod-to-pod communication:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: video-streaming-netpol
  namespace: video-streaming
spec:
  podSelector:
    matchLabels:
      app: video-streaming-app
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector: {}
  egress:
  - to: []
```

### Pod Security Standards
The deployment follows Kubernetes security best practices:
- Non-root containers where possible
- Resource limits and requests
- Health checks and readiness probes
- Secrets management

## Cost Optimization

### Right-sizing Resources
Monitor resource usage and adjust requests/limits:

```bash
kubectl top pods -n video-streaming
```

### Spot Instances
The node group supports spot instances for cost savings. The deployment includes tolerations for spot instance interruptions.

### Cluster Autoscaler
Automatically scales nodes down during low usage periods.

## Backup and Disaster Recovery

### Database Backups
RDS automated backups are configured with 7-day retention.

### Application State
The application is stateless, so recovery involves:
1. Redeploying Kubernetes resources
2. Restoring database from backup if needed

### Configuration Backup
Store Kubernetes manifests in version control for easy recovery.

## Migration from ECS

If migrating from an existing ECS deployment:

1. **Backup your data**: Ensure RDS and S3 data is backed up
2. **Deploy EKS in parallel**: Use a different environment name
3. **Test thoroughly**: Verify all functionality works
4. **Update DNS**: Point your domain to the new ALB
5. **Cleanup ECS**: Remove old ECS resources after verification

## Support

For issues with the EKS deployment:

1. Check the troubleshooting section above
2. Review Kubernetes and AWS EKS documentation
3. Check AWS CloudWatch logs for infrastructure issues
4. Use kubectl commands to debug application issues

## Cleanup

To destroy the EKS deployment:

```bash
# Delete Kubernetes resources
kubectl delete namespace video-streaming

# Destroy infrastructure
./eks-deploy.sh --destroy
```

Or manually:

```bash
cd terraform
terraform destroy -var="domain_name=your-domain.com" -var="environment=prod"
```

**Warning**: This will permanently delete all resources including databases and S3 buckets. Ensure you have backups if needed.
