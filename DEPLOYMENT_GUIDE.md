# Cost-Effective Cloud Deployment Guide for Video Streaming Service

## 🚀 New: Terraform Infrastructure as Code

**We now provide complete Terraform automation for infrastructure deployment!**

### Quick Terraform Deployment
```bash
# 1. Configure your settings
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your domain and SSH key

# 2. Set your cloud provider API token
export HCLOUD_TOKEN="your-hetzner-token"  # For Hetzner (recommended)

# 3. Deploy infrastructure
./terraform-deploy.sh init
./terraform-deploy.sh apply --provider hetzner --domain yourdomain.com

# 4. Deploy application (after infrastructure is ready)
ssh deploy@YOUR_SERVER_IP
git clone https://github.com/yourusername/VideoStreaming.git
cd VideoStreaming
cp .env.prod.example .env.prod
# Edit .env.prod with your settings
./deploy.sh
```

**Benefits of Terraform Approach:**
- ✅ **Complete automation** - Infrastructure + application deployment
- ✅ **Multi-cloud support** - Switch providers with one command
- ✅ **Version controlled** - Infrastructure as code
- ✅ **Reproducible** - Identical deployments every time
- ✅ **Cost optimization** - Automatic resource sizing
- ✅ **Zero vendor lock-in** - Migrate between providers seamlessly

## Architecture Overview
Your video streaming service consists of:
- **Frontend**: React app served via Nginx
- **Backend**: Rust-based API server with WebSocket support
- **YouTube Scraper**: Rust service for video content processing
- **Database**: PostgreSQL
- **Object Storage**: MinIO (S3-compatible)
- **Cache**: Redis
- **Reverse Proxy/Load Balancer**: Nginx

## Recommended IaaS Providers (Cheapest + Vendor Lock-in Free)

### 1. **Hetzner Cloud** (Most Cost-Effective)
**Why Hetzner:**
- Extremely competitive pricing (50-70% cheaper than AWS/GCP/Azure)
- No vendor lock-in (standard Linux VMs, Docker, Kubernetes)
- European data centers with excellent performance
- Transparent pricing with no hidden costs

**Estimated Monthly Cost: $25-45**
```
- 1x CPX21 (3 vCPU, 8GB RAM) for backend services: €8.21/month
- 1x CPX11 (2 vCPU, 4GB RAM) for database: €4.15/month  
- 1x CPX11 (2 vCPU, 4GB RAM) for frontend/proxy: €4.15/month
- Load Balancer: €5.39/month
- 100GB Volume for storage: €4.00/month
- Bandwidth: Included (20TB)
Total: ~€26/month (~$28 USD)
```

### 2. **DigitalOcean** (Good Balance)
**Why DigitalOcean:**
- Simple, predictable pricing
- Excellent documentation and community
- Managed databases available
- No vendor lock-in

**Estimated Monthly Cost: $40-60**
```
- 2x Basic Droplets (2 vCPU, 4GB): $24/month each
- Managed PostgreSQL (1GB): $15/month
- Load Balancer: $12/month
- Spaces (Object Storage): $5/month
Total: ~$80/month
```

### 3. **Vultr** (Alternative Option)
**Why Vultr:**
- Competitive pricing similar to DigitalOcean
- Global presence
- High-performance SSD storage

**Estimated Monthly Cost: $35-55**

### 4. **Linode (Akamai)** (Reliable Choice)
**Why Linode:**
- Consistent performance
- Good pricing
- Strong network infrastructure

**Estimated Monthly Cost: $40-65**

## Deployment Architecture Options

### Option A: Single Server Deployment (Cheapest - $15-25/month)
For low-traffic scenarios, deploy everything on one powerful server:

**Hetzner CPX31 (4 vCPU, 8GB RAM): €12.90/month**
```yaml
# docker-compose-production.yml
version: '3.8'
services:
  # All your existing services
  # Add resource limits and production configs
```

### Option B: Multi-Server Deployment (Recommended - $25-45/month)
Separate concerns for better scalability and reliability:

**Server 1: Application Services (CPX21)**
- Frontend (Nginx)
- Backend (Rust API)
- YouTube Scraper
- Redis

**Server 2: Database & Storage (CPX21)**
- PostgreSQL
- MinIO (Object Storage)

**Load Balancer**
- Hetzner Load Balancer or Nginx proxy

### Option C: Kubernetes Deployment (Scalable - $30-50/month)
Use managed Kubernetes for auto-scaling:

**Hetzner Cloud with k3s or DigitalOcean Kubernetes**

## Step-by-Step Deployment Instructions

### 1. Prepare Production Configuration

Create production-ready Docker Compose file:
```yaml
# docker-compose.prod.yml
version: '3.8'

services:
  frontend:
    build: ./frontend
    restart: unless-stopped
    environment:
      - NODE_ENV=production
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.frontend.rule=Host(`yourdomain.com`)"
      - "traefik.http.routers.frontend.tls.certresolver=letsencrypt"

  backend:
    build: ./rust-backend
    restart: unless-stopped
    environment:
      - DATABASE_URL=postgres://user:pass@db:5432/video_streaming_db
      - JWT_SECRET=${JWT_SECRET}
      - MINIO_ENDPOINT=http://minio:9000
      - REDIS_URL=redis://redis:6379
      - RUST_LOG=info
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 512M

  youtube-scraper:
    build: ./youtube-scraper
    restart: unless-stopped
    environment:
      - DATABASE_URL=postgres://user:pass@db:5432/video_streaming_db
      - MINIO_ENDPOINT=http://minio:9000
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G

  db:
    image: postgres:15-alpine
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${DB_USER}
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=video_streaming_db
    volumes:
      - db-data:/var/lib/postgresql/data
      - ./rust-backend/init-db.sql:/docker-entrypoint-initdb.d/init-db.sql
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G

  minio:
    image: minio/minio:latest
    restart: unless-stopped
    environment:
      - MINIO_ROOT_USER=${MINIO_USER}
      - MINIO_ROOT_PASSWORD=${MINIO_PASSWORD}
    volumes:
      - minio-data:/data
    command: server /data --console-address ":9001"
    deploy:
      resources:
        limits:
          memory: 512M

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    volumes:
      - redis-data:/data
    command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
    deploy:
      resources:
        limits:
          memory: 512M

  traefik:
    image: traefik:v3.0
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./acme.json:/acme.json
    labels:
      - "traefik.enable=true"

volumes:
  db-data:
  minio-data:
  redis-data:

networks:
  default:
    name: video-streaming-network
```

### 2. Environment Configuration

Create `.env.prod` file:
```bash
# Database
DB_USER=your_db_user
DB_PASSWORD=your_secure_db_password

# JWT
JWT_SECRET=your_very_secure_jwt_secret_key_here

# MinIO
MINIO_USER=your_minio_user
MINIO_PASSWORD=your_secure_minio_password

# Domain
DOMAIN=yourdomain.com
```

### 3. Traefik Configuration for SSL

Create `traefik.yml`:
```yaml
api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entrypoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false

certificatesResolvers:
  letsencrypt:
    acme:
      email: your-email@domain.com
      storage: /acme.json
      httpChallenge:
        entryPoint: web
```

### 4. Deployment Script

Create `deploy.sh`:
```bash
#!/bin/bash

# Deploy to Hetzner Cloud
echo "Deploying Video Streaming Service..."

# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Clone repository
git clone https://github.com/yourusername/VideoStreaming.git
cd VideoStreaming

# Set up environment
cp .env.example .env.prod
# Edit .env.prod with your values

# Create acme.json for SSL certificates
touch acme.json
chmod 600 acme.json

# Deploy
docker-compose -f docker-compose.prod.yml up -d

# Set up monitoring
docker run -d \
  --name watchtower \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower \
  --cleanup \
  --interval 3600

echo "Deployment complete!"
echo "Your service will be available at https://yourdomain.com"
```

### 5. Monitoring and Backup Setup

Create `monitoring.yml`:
```yaml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    restart: unless-stopped
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(`monitoring.yourdomain.com`)"

volumes:
  prometheus-data:
  grafana-data:
```

## Cost Optimization Tips

### 1. Resource Optimization
- Use Alpine Linux images where possible
- Set memory limits for containers
- Enable Redis memory optimization
- Use PostgreSQL connection pooling

### 2. Storage Optimization
- Use object storage for videos (cheaper than block storage)
- Implement video compression
- Set up CDN for static assets (Cloudflare free tier)

### 3. Scaling Strategy
- Start with single server
- Scale horizontally by adding more backend instances
- Use database read replicas for heavy read workloads
- Implement caching strategies

### 4. Backup Strategy
```bash
# Automated backup script
#!/bin/bash
# backup.sh

# Database backup
docker exec postgres pg_dump -U $DB_USER video_streaming_db > backup_$(date +%Y%m%d).sql

# MinIO backup
docker exec minio mc mirror /data /backup/minio/

# Upload to external storage (optional)
# rclone copy backup/ remote:backups/
```

## Security Considerations

1. **Firewall Configuration**
```bash
# UFW setup
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80
sudo ufw allow 443
sudo ufw enable
```

2. **Docker Security**
- Run containers as non-root users
- Use secrets management
- Regular security updates
- Network segmentation

3. **SSL/TLS**
- Automatic SSL certificates via Let's Encrypt
- HSTS headers
- Secure cipher suites

## Migration Strategy (Avoiding Vendor Lock-in)

Your application is already designed to avoid vendor lock-in:
- **Containerized**: Can run anywhere Docker is supported
- **Standard databases**: PostgreSQL, Redis
- **S3-compatible storage**: MinIO can be replaced with any S3-compatible service
- **Standard protocols**: HTTP/HTTPS, WebSockets

To migrate between providers:
1. Export data from databases
2. Sync object storage
3. Update DNS records
4. Deploy to new provider
5. Switch traffic

## Recommended Starting Configuration

**For MVP/Testing: Hetzner CPX21 ($12/month)**
- Single server deployment
- All services on one machine
- Suitable for up to 100 concurrent users

**For Production: Hetzner Multi-server ($28/month)**
- Separate app and database servers
- Load balancer
- Suitable for up to 1000 concurrent users

**For Scale: Kubernetes cluster ($40+/month)**
- Auto-scaling
- High availability
- Suitable for 1000+ concurrent users

This setup provides the most cost-effective deployment while maintaining flexibility and avoiding vendor lock-in.
