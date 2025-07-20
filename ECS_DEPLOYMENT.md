# ECS Fargate Sidecar Deployment Guide

This guide explains how to deploy your video streaming application using nginx as a sidecar container in AWS ECS Fargate.

## Architecture Overview

The sidecar pattern isolates nginx as a separate container that handles all incoming traffic and routes it to the appropriate backend services:

- **nginx-proxy container**: Listens on port 80, routes traffic to frontend (port 3000), backend API (port 5050), and WebSocket (port 8080)
- **frontend container**: Serves React app only on port 3000 (no external access)
- **backend container**: Runs Rust backend on ports 5050 (API) and 8080 (WebSocket)

## Traffic Flow

```
Internet → ALB (port 80/443) → nginx-proxy (port 80) → {
  / → frontend:3000
  /api/ → backend:5050
  /api/ws/ → backend:8080 (WebSocket)
}
```

## Prerequisites

1. AWS CLI configured with appropriate permissions
2. Docker installed
3. ECR repositories created (or script will create them)
4. RDS PostgreSQL database
5. Redis instance (ElastiCache)
6. S3 bucket or S3-compatible storage

## Files Created

### nginx-sidecar/
- `nginx.conf`: nginx configuration for Docker Compose (uses service names)
- `nginx.ecs.conf`: nginx configuration for ECS Fargate (uses localhost)
- `Dockerfile`: nginx container definition for Docker Compose
- `Dockerfile.ecs`: nginx container definition for ECS Fargate

### frontend/
- `nginx.sidecar.conf`: nginx config for frontend (port 3000 only)
- `Dockerfile.sidecar`: Modified frontend Dockerfile

### Root directory
- `ecs-task-definition.json`: ECS task definition
- `build-sidecar-containers.sh`: Build and push script

## Deployment Steps

### 1. Set Environment Variables

```bash
export AWS_ACCOUNT_ID=123456789012
export AWS_REGION=us-west-2
export ECR_REGISTRY=123456789012.dkr.ecr.us-west-2.amazonaws.com
```

### 2. Build and Push Containers

```bash
./build-sidecar-containers.sh
```

This script will:
- Create ECR repositories if they don't exist
- Build all three containers (nginx-proxy, frontend-sidecar, rust-backend)
- Push them to ECR

### 3. Update Task Definition

Edit `ecs-task-definition.json` and replace:
- `YOUR_ACCOUNT_ID` with your AWS account ID
- `YOUR_ECR_REGISTRY` with your ECR registry URL
- Database, Redis, and storage endpoints
- Environment variables with actual values

### 4. Create CloudWatch Log Group

```bash
aws logs create-log-group --log-group-name /ecs/video-streaming-app --region $AWS_REGION
```

### 5. Register Task Definition

```bash
aws ecs register-task-definition --cli-input-json file://ecs-task-definition.json --region $AWS_REGION
```

### 6. Create ECS Cluster (if needed)

```bash
aws ecs create-cluster --cluster-name video-streaming-cluster --region $AWS_REGION
```

### 7. Create ECS Service

```bash
aws ecs create-service \
  --cluster video-streaming-cluster \
  --service-name video-streaming-service \
  --task-definition video-streaming-app:1 \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-12345,subnet-67890],securityGroups=[sg-12345],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=arn:aws:elasticloadbalancing:region:account:targetgroup/my-targets/1234567890123456,containerName=nginx-proxy,containerPort=80" \
  --region $AWS_REGION
```

## Security Considerations

### Container Isolation
- Frontend container only accepts traffic on port 3000
- Backend ports (5050, 8080) are not exposed externally
- Only nginx-proxy container accepts external traffic

### Network Security
- Use private subnets for ECS tasks
- Configure security groups to only allow necessary traffic
- Use ALB with SSL termination

### Environment Variables
- Store sensitive data in AWS Systems Manager Parameter Store or AWS Secrets Manager
- Reference secrets in task definition using `valueFrom`

Example for secrets:
```json
{
  "name": "JWT_SECRET",
  "valueFrom": "arn:aws:ssm:region:account:parameter/video-streaming/jwt-secret"
}
```

## Monitoring and Logging

### CloudWatch Logs
- Each container logs to separate log streams
- Log group: `/ecs/video-streaming-app`
- Log streams: `nginx`, `frontend`, `backend`

### Health Checks
- nginx-proxy: Checks backend API status endpoint
- frontend: Checks nginx serving static files
- backend: Checks API status endpoint

### Metrics
Monitor these CloudWatch metrics:
- CPU and memory utilization
- Network I/O
- Task count and health

## Troubleshooting

### Container Startup Issues
1. Check CloudWatch logs for each container
2. Verify environment variables are set correctly
3. Ensure database and Redis are accessible

### Network Connectivity
1. Verify security group rules
2. Check subnet routing tables
3. Ensure ALB target group health checks pass

### nginx Routing Issues
1. Check nginx access and error logs
2. Verify upstream server connectivity
3. Test individual container endpoints

## Scaling

### Horizontal Scaling
```bash
aws ecs update-service \
  --cluster video-streaming-cluster \
  --service video-streaming-service \
  --desired-count 3 \
  --region $AWS_REGION
```

### Vertical Scaling
Update task definition with more CPU/memory:
```json
{
  "cpu": "2048",
  "memory": "4096"
}
```

## Cost Optimization

1. Use Fargate Spot for non-production environments
2. Right-size CPU and memory allocations
3. Use Application Load Balancer for multiple services
4. Consider using ECS Service Connect for service mesh

## Rollback Strategy

1. Keep previous task definition revisions
2. Update service to use previous revision:
```bash
aws ecs update-service \
  --cluster video-streaming-cluster \
  --service video-streaming-service \
  --task-definition video-streaming-app:PREVIOUS_REVISION \
  --region $AWS_REGION
```

## Next Steps

1. Set up CI/CD pipeline for automated deployments
2. Implement blue-green deployment strategy
3. Add monitoring and alerting
4. Configure auto-scaling based on metrics
