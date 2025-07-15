# AWS On-Demand YouTube Scraper Guide

## Overview

This guide explains how to set up and use the on-demand YouTube scraper infrastructure on AWS. The scraper runs on AWS Fargate with a **scale-to-zero** approach, meaning you only pay when it's actually running.

## Architecture

The on-demand scraper uses the following AWS services:

- **ECS Fargate**: Runs the scraper container on-demand (scale-to-zero)
- **Lambda**: Triggers scraper tasks via API calls
- **API Gateway**: Provides REST API endpoint for triggering scrapes
- **ECR**: Stores the scraper Docker image
- **CloudWatch**: Logs scraper execution
- **S3**: Stores scraped videos
- **RDS**: Stores video metadata

## Cost Structure

### Pay-Per-Use Model
- **ECS Fargate**: ~$0.04 per vCPU-hour, ~$0.004 per GB-hour
- **Lambda**: ~$0.0000002 per request + execution time
- **API Gateway**: ~$3.50 per million requests
- **CloudWatch Logs**: ~$0.50 per GB ingested

### Example Costs
- **Single video scrape** (5 minutes): ~$0.01-0.02
- **100 videos per month**: ~$1-2
- **No usage**: $0 (true scale-to-zero)

## Setup Instructions

### 1. Deploy Infrastructure

```bash
# Deploy with Terraform
cd terraform
terraform apply -var="domain_name=yourdomain.com"
```

Or create a terraform.tfvars file:
```bash
# Create terraform.tfvars
cat > terraform.tfvars << EOF
domain_name = "stream.harrisonng.dev"
environment = "prod"
server_count = 2
server_size = "small"
enable_load_balancer = true
enable_monitoring = true
EOF

# Then apply
terraform apply
```

### 2. Build and Push Scraper Image

Use the provided script to build and push the scraper image:

```bash
# Run the build script
./build-and-push-scraper.sh
```

This script will:
- Automatically detect your AWS account ID
- Check if the ECR repository exists
- Build the scraper Docker image
- Tag and push it to ECR
- Verify the upload

**Manual steps (if you prefer):**
```bash
# Get your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Build the scraper image
cd youtube-scraper
docker build -t video-streaming-scraper .

# Login to ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com

# Tag and push
docker tag video-streaming-scraper:latest ${ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com/prod-video-streaming-scraper:latest
docker push ${ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com/prod-video-streaming-scraper:latest
```

### 3. Get API Endpoint

After deployment, get the scraper API URL from Terraform outputs:

```bash
terraform output scraper_api_url
# Output: https://abc123.execute-api.us-west-2.amazonaws.com/prod/scrape
```

## Usage

### 1. Trigger Scraper via API

**Endpoint**: `POST /scrape`

**Request Body**:
```json
{
  "youtube_url": "https://www.youtube.com/watch?v=VIDEO_ID",
  "user_id": 1
}
```

**Example using curl**:
```bash
curl -X POST https://abc123.execute-api.us-west-2.amazonaws.com/prod/scrape \
  -H "Content-Type: application/json" \
  -d '{
    "youtube_url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    "user_id": 1
  }'
```

**Response**:
```json
{
  "message": "Scraper task started successfully",
  "task_arn": "arn:aws:ecs:us-west-2:123456789:task/cluster/task-id",
  "task_name": "scraper-abc12345",
  "youtube_url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
}
```

### 2. Trigger from Frontend

Add this to your React frontend:

```javascript
// Frontend integration
const triggerScraper = async (youtubeUrl, userId = 1) => {
  try {
    const response = await fetch('https://abc123.execute-api.us-west-2.amazonaws.com/prod/scrape', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        youtube_url: youtubeUrl,
        user_id: userId
      })
    });
    
    const result = await response.json();
    
    if (response.ok) {
      console.log('Scraper started:', result);
      return result;
    } else {
      console.error('Error:', result.error);
      throw new Error(result.error);
    }
  } catch (error) {
    console.error('Failed to trigger scraper:', error);
    throw error;
  }
};

// Usage
triggerScraper('https://www.youtube.com/watch?v=dQw4w9WgXcQ')
  .then(result => console.log('Task started:', result.task_name))
  .catch(error => console.error('Error:', error));
```

### 3. Trigger from Backend

Add this endpoint to your Rust backend:

```rust
use reqwest;
use serde_json::json;

#[post("/api/scrape-video")]
async fn trigger_scraper(
    req: web::Json<ScrapeVideoRequest>,
) -> impl Responder {
    let client = reqwest::Client::new();
    
    let payload = json!({
        "youtube_url": req.youtube_url,
        "user_id": req.user_id.unwrap_or(1)
    });
    
    match client
        .post("https://abc123.execute-api.us-west-2.amazonaws.com/prod/scrape")
        .json(&payload)
        .send()
        .await
    {
        Ok(response) => {
            if response.status().is_success() {
                let result: serde_json::Value = response.json().await.unwrap_or_default();
                HttpResponse::Ok().json(result)
            } else {
                HttpResponse::InternalServerError().json(json!({
                    "error": "Failed to trigger scraper"
                }))
            }
        }
        Err(e) => {
            error!("Failed to trigger scraper: {}", e);
            HttpResponse::InternalServerError().json(json!({
                "error": "Failed to trigger scraper"
            }))
        }
    }
}
```

## Monitoring

### 1. View Logs

```bash
# View scraper logs
aws logs tail /ecs/prod-video-streaming-scraper --follow

# View specific task logs
aws logs tail /ecs/prod-video-streaming-scraper --follow --filter-pattern "scraper-abc12345"
```

### 2. Check Task Status

```bash
# List running tasks
aws ecs list-tasks --cluster prod-video-streaming --service-name scraper

# Describe specific task
aws ecs describe-tasks --cluster prod-video-streaming --tasks arn:aws:ecs:us-west-2:123456789:task/cluster/task-id
```

### 3. Monitor Costs

```bash
# Check ECS costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Troubleshooting

### Common Issues

1. **Task fails to start**
   - Check ECR image exists and is accessible
   - Verify IAM permissions for ECS task role
   - Check subnet and security group configuration

2. **Scraper fails during execution**
   - Check CloudWatch logs for error details
   - Verify database connectivity
   - Ensure S3 bucket permissions are correct

3. **API Gateway returns errors**
   - Check Lambda function logs
   - Verify Lambda has permissions to run ECS tasks
   - Check API Gateway configuration

### Debug Commands

```bash
# Check ECS cluster status
aws ecs describe-clusters --clusters prod-video-streaming

# Check task definition
aws ecs describe-task-definition --task-definition prod-video-streaming-scraper

# Check Lambda function
aws lambda get-function --function-name prod-video-streaming-scraper-trigger

# Test Lambda directly
aws lambda invoke --function-name prod-video-streaming-scraper-trigger \
  --payload '{"youtube_url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ","user_id":1}' \
  response.json
```

## Security Considerations

### 1. API Authentication (Optional)

Add API key authentication:

```bash
# Create API key
aws apigateway create-api-key --name scraper-api-key --enabled

# Create usage plan
aws apigateway create-usage-plan --name scraper-usage-plan

# Associate API key with usage plan
aws apigateway create-usage-plan-key --usage-plan-id <plan-id> --key-id <key-id> --key-type API_KEY
```

### 2. Rate Limiting

The current setup allows unlimited requests. Consider adding:
- API Gateway throttling
- Lambda concurrency limits
- ECS task limits

### 3. Network Security

- Scraper runs in private subnets
- No direct internet access (uses NAT Gateway)
- Security groups restrict access

## Scaling Considerations

### Concurrent Scraping

- **Default**: 1 task per request
- **Maximum**: Limited by AWS account limits
- **Recommendation**: Implement queue system for high volume

### Cost Optimization

1. **Right-size resources**: Adjust CPU/memory based on video complexity
2. **Optimize images**: Use multi-stage builds, Alpine base images
3. **Log retention**: Set appropriate CloudWatch log retention
4. **Monitoring**: Set up billing alerts

## Advanced Usage

### 1. Batch Processing

```bash
# Trigger multiple scrapes
for url in $(cat urls.txt); do
  curl -X POST https://abc123.execute-api.us-west-2.amazonaws.com/prod/scrape \
    -H "Content-Type: application/json" \
    -d "{\"youtube_url\":\"$url\",\"user_id\":1}"
  sleep 1  # Rate limiting
done
```

### 2. Webhook Integration

Set up webhooks to notify when scraping completes:

```python
# Add to Lambda function
import requests

def notify_completion(task_arn, status, video_data):
    webhook_url = os.environ.get('WEBHOOK_URL')
    if webhook_url:
        requests.post(webhook_url, json={
            'task_arn': task_arn,
            'status': status,
            'video_data': video_data
        })
```

### 3. Custom Processing

Modify the scraper for custom processing:

```rust
// Add custom processing logic
impl YoutubeScraper {
    async fn custom_process_video(&self, video_path: &str) -> Result<(), Box<dyn std::error::Error>> {
        // Add thumbnail generation
        // Add video transcoding
        // Add metadata extraction
        // Add content analysis
        Ok(())
    }
}
```

## Migration from Always-On

If migrating from an always-on scraper:

1. **Update frontend**: Replace direct scraper calls with API Gateway calls
2. **Remove old infrastructure**: Delete always-on ECS service
3. **Update monitoring**: Switch to task-based monitoring
4. **Test thoroughly**: Ensure all scraping workflows work

## Support

For issues or questions:

1. Check CloudWatch logs first
2. Review this guide for common solutions
3. Check AWS service health dashboards
4. Review Terraform state for configuration issues

## Cost Monitoring Script

```bash
#!/bin/bash
# monitor-scraper-costs.sh

# Get current month costs for ECS
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "$(date +%Y-%m-01)" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter file://cost-filter.json

# cost-filter.json
{
  "Dimensions": {
    "Key": "SERVICE",
    "Values": ["Amazon Elastic Container Service"]
  }
}
```

This setup provides a truly serverless, cost-effective solution for on-demand video scraping that scales from zero to handle any workload while keeping costs minimal.
