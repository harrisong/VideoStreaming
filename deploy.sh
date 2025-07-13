#!/bin/bash

# Video Streaming Service - Production Deployment Script
# This script deploys your video streaming service to a cloud server

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root for security reasons"
fi

log "Starting Video Streaming Service Deployment..."

# Check if .env.prod exists
if [ ! -f ".env.prod" ]; then
    error ".env.prod file not found. Please copy .env.prod.example to .env.prod and configure it."
fi

# Source environment variables
source .env.prod

# Validate required environment variables
required_vars=("DOMAIN" "DB_USER" "DB_PASSWORD" "JWT_SECRET" "MINIO_USER" "MINIO_PASSWORD")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        error "Required environment variable $var is not set in .env.prod"
    fi
done

log "Environment variables validated successfully"

# Update system packages
log "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install required packages
log "Installing required packages..."
sudo apt install -y curl wget git htop ufw fail2ban

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    log "Docker installed successfully"
else
    log "Docker is already installed"
fi

# Install Docker Compose if not already installed
if ! command -v docker-compose &> /dev/null; then
    log "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    log "Docker Compose installed successfully"
else
    log "Docker Compose is already installed"
fi

# Configure firewall
log "Configuring firewall..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
log "Firewall configured successfully"

# Configure fail2ban
log "Configuring fail2ban..."
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
log "Fail2ban configured successfully"

# Create acme.json for SSL certificates
log "Setting up SSL certificate storage..."
touch acme.json
chmod 600 acme.json

# Update Traefik configuration with actual email
log "Updating Traefik configuration..."
if [ ! -z "$LETSENCRYPT_EMAIL" ]; then
    sed -i "s/your-email@domain.com/$LETSENCRYPT_EMAIL/g" traefik.yml
fi

# Generate Traefik auth if not provided
if [ -z "$TRAEFIK_AUTH" ]; then
    warn "TRAEFIK_AUTH not set. Generating default admin:admin credentials"
    # Install apache2-utils for htpasswd
    sudo apt install -y apache2-utils
    TRAEFIK_AUTH=$(htpasswd -nb admin admin)
    echo "TRAEFIK_AUTH=$TRAEFIK_AUTH" >> .env.prod
fi

# Pull latest images
log "Pulling latest Docker images..."
docker-compose -f docker-compose.prod.yml pull

# Build custom images
log "Building application images..."
docker-compose -f docker-compose.prod.yml build --no-cache

# Create external networks if they don't exist
log "Creating Docker networks..."
docker network create app-network 2>/dev/null || true

# Start services
log "Starting services..."
docker-compose -f docker-compose.prod.yml up -d

# Wait for services to be ready
log "Waiting for services to start..."
sleep 30

# Check service health
log "Checking service health..."
services=("frontend" "backend" "youtube-scraper" "db" "minio" "redis" "traefik")
for service in "${services[@]}"; do
    if docker-compose -f docker-compose.prod.yml ps | grep -q "$service.*Up"; then
        log "✓ $service is running"
    else
        warn "✗ $service may not be running properly"
    fi
done

# Set up log rotation
log "Setting up log rotation..."
sudo tee /etc/logrotate.d/docker-containers > /dev/null <<EOF
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    size=1M
    missingok
    delaycompress
    copytruncate
}
EOF

# Create backup script
log "Creating backup script..."
cat > backup.sh << 'EOF'
#!/bin/bash

# Backup script for Video Streaming Service
BACKUP_DIR="/backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Database backup
docker exec $(docker-compose -f docker-compose.prod.yml ps -q db) pg_dump -U $DB_USER video_streaming_db > "$BACKUP_DIR/database.sql"

# MinIO backup (if mc client is available)
if command -v mc &> /dev/null; then
    mc mirror minio/videos "$BACKUP_DIR/videos/"
fi

# Compress backup
tar -czf "$BACKUP_DIR.tar.gz" -C /backup "$(basename $BACKUP_DIR)"
rm -rf "$BACKUP_DIR"

# Keep only last 7 days of backups
find /backup -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_DIR.tar.gz"
EOF

chmod +x backup.sh

# Set up cron job for backups
log "Setting up automated backups..."
(crontab -l 2>/dev/null; echo "0 2 * * * $(pwd)/backup.sh") | crontab -

# Create monitoring script
log "Creating monitoring script..."
cat > monitor.sh << 'EOF'
#!/bin/bash

# Simple monitoring script
echo "=== Docker Services Status ==="
docker-compose -f docker-compose.prod.yml ps

echo -e "\n=== System Resources ==="
echo "Memory Usage:"
free -h
echo -e "\nDisk Usage:"
df -h
echo -e "\nCPU Usage:"
top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4"%"}'

echo -e "\n=== Service Logs (last 10 lines) ==="
docker-compose -f docker-compose.prod.yml logs --tail=10
EOF

chmod +x monitor.sh

# Display deployment information
log "Deployment completed successfully!"
echo
echo -e "${BLUE}=== Deployment Information ===${NC}"
echo -e "${GREEN}Main Application:${NC} https://$DOMAIN"
echo -e "${GREEN}Traefik Dashboard:${NC} https://traefik.$DOMAIN"
echo -e "${GREEN}MinIO Console:${NC} https://storage.$DOMAIN"
echo
echo -e "${BLUE}=== Useful Commands ===${NC}"
echo -e "${GREEN}View logs:${NC} docker-compose -f docker-compose.prod.yml logs -f"
echo -e "${GREEN}Restart services:${NC} docker-compose -f docker-compose.prod.yml restart"
echo -e "${GREEN}Update services:${NC} docker-compose -f docker-compose.prod.yml pull && docker-compose -f docker-compose.prod.yml up -d"
echo -e "${GREEN}Monitor system:${NC} ./monitor.sh"
echo -e "${GREEN}Create backup:${NC} ./backup.sh"
echo
echo -e "${YELLOW}Important:${NC}"
echo "1. Make sure your domain DNS points to this server's IP address"
echo "2. SSL certificates will be automatically generated by Let's Encrypt"
echo "3. Change default passwords in .env.prod for production use"
echo "4. Monitor logs for any issues: docker-compose -f docker-compose.prod.yml logs -f"
echo
log "Your video streaming service is now running!"
