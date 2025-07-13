# Quick Start Deployment Guide

This guide will get your video streaming service deployed to the cloud in under 30 minutes.

## 🚀 Recommended: Hetzner Cloud (Cheapest Option)

### Step 1: Create Server
1. Go to [Hetzner Cloud Console](https://console.hetzner-cloud.com/)
2. Create new project: "VideoStreaming"
3. Create server:
   - **Location**: Nuremberg (or closest to your users)
   - **Image**: Ubuntu 22.04
   - **Type**: CPX21 (3 vCPU, 8GB RAM) - €8.21/month
   - **SSH Key**: Add your SSH public key
   - **Name**: video-streaming-server

### Step 2: Configure Domain (Required)
1. Point your domain to the server IP:
   ```
   A     yourdomain.com        -> YOUR_SERVER_IP
   A     *.yourdomain.com      -> YOUR_SERVER_IP
   ```
2. Wait for DNS propagation (5-30 minutes)

### Step 3: Deploy Application
1. SSH into your server:
   ```bash
   ssh root@YOUR_SERVER_IP
   ```

2. Create a non-root user:
   ```bash
   adduser deploy
   usermod -aG sudo deploy
   su - deploy
   ```

3. Clone your repository:
   ```bash
   git clone https://github.com/yourusername/VideoStreaming.git
   cd VideoStreaming
   ```

4. Configure environment:
   ```bash
   cp .env.prod.example .env.prod
   nano .env.prod
   ```
   
   **Minimum required changes:**
   ```bash
   DOMAIN=yourdomain.com
   DB_PASSWORD=your_secure_db_password_here
   JWT_SECRET=your_very_secure_jwt_secret_key_minimum_32_characters_long
   MINIO_PASSWORD=your_secure_minio_password_here
   REDIS_PASSWORD=your_secure_redis_password_here
   LETSENCRYPT_EMAIL=your-email@domain.com
   ```

5. Run deployment:
   ```bash
   ./deploy.sh
   ```

6. Wait 5-10 minutes for deployment to complete.

### Step 4: Verify Deployment
Visit these URLs to confirm everything is working:
- **Main App**: https://yourdomain.com
- **Traefik Dashboard**: https://traefik.yourdomain.com (admin/admin)
- **MinIO Console**: https://storage.yourdomain.com

## 🔧 Alternative Providers

### DigitalOcean
1. Create Droplet: Basic, 2 vCPU, 4GB RAM ($24/month)
2. Follow same steps as Hetzner

### Vultr
1. Create Instance: Regular Performance, 2 vCPU, 4GB RAM ($20/month)
2. Follow same steps as Hetzner

### Linode
1. Create Linode: Shared CPU, 2GB RAM ($12/month)
2. Follow same steps as Hetzner

## 💰 Cost Breakdown (Monthly)

### Single Server Setup (Recommended for MVP)
- **Hetzner CPX21**: €8.21 (~$9 USD)
- **Domain**: $10-15/year
- **Total**: ~$10-12/month

### Multi-Server Setup (Production)
- **App Server (CPX21)**: €8.21
- **DB Server (CPX21)**: €8.21  
- **Load Balancer**: €5.39
- **Total**: ~$24/month

## 🛠️ Post-Deployment Tasks

### 1. Security Hardening
```bash
# Change SSH port (optional)
sudo nano /etc/ssh/sshd_config
# Change Port 22 to Port 2222
sudo systemctl restart ssh

# Update firewall
sudo ufw allow 2222/tcp
sudo ufw delete allow ssh
```

### 2. Monitoring Setup
```bash
# Check service status
./monitor.sh

# View logs
docker-compose -f docker-compose.prod.yml logs -f

# Check resource usage
htop
```

### 3. Backup Configuration
```bash
# Manual backup
./backup.sh

# Verify automated backups
crontab -l
```

### 4. Performance Optimization
```bash
# Enable Docker logging limits
echo '{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```

## 🚨 Troubleshooting

### SSL Certificate Issues
```bash
# Check certificate status
docker-compose -f docker-compose.prod.yml logs traefik

# Force certificate renewal
docker-compose -f docker-compose.prod.yml restart traefik
```

### Service Not Starting
```bash
# Check service logs
docker-compose -f docker-compose.prod.yml logs [service-name]

# Restart specific service
docker-compose -f docker-compose.prod.yml restart [service-name]
```

### Database Connection Issues
```bash
# Check database logs
docker-compose -f docker-compose.prod.yml logs db

# Connect to database
docker-compose -f docker-compose.prod.yml exec db psql -U $DB_USER -d video_streaming_db
```

### High Memory Usage
```bash
# Check memory usage
free -h
docker stats

# Restart services to free memory
docker-compose -f docker-compose.prod.yml restart
```

## 📈 Scaling Up

### When to Scale
- CPU usage consistently > 80%
- Memory usage > 90%
- Response times > 2 seconds
- More than 100 concurrent users

### Horizontal Scaling
1. Create additional app servers
2. Update load balancer configuration
3. Use external database (managed PostgreSQL)
4. Implement Redis cluster

### Vertical Scaling
1. Upgrade server size:
   - CPX31 (4 vCPU, 8GB): €12.90/month
   - CPX41 (8 vCPU, 16GB): €25.20/month

## 🔄 Updates and Maintenance

### Update Application
```bash
git pull origin main
docker-compose -f docker-compose.prod.yml build --no-cache
docker-compose -f docker-compose.prod.yml up -d
```

### Update System
```bash
sudo apt update && sudo apt upgrade -y
sudo reboot  # If kernel updates
```

### Database Migrations
```bash
# Run migrations (if needed)
docker-compose -f docker-compose.prod.yml exec backend your-migration-command
```

## 📞 Support

If you encounter issues:
1. Check the logs: `docker-compose -f docker-compose.prod.yml logs -f`
2. Review the troubleshooting section above
3. Check system resources: `./monitor.sh`
4. Restart services: `docker-compose -f docker-compose.prod.yml restart`

## 🎉 Success!

Your video streaming service is now running in production with:
- ✅ Automatic SSL certificates
- ✅ Load balancing and reverse proxy
- ✅ Automated backups
- ✅ Security hardening
- ✅ Monitoring and logging
- ✅ Cost optimization

**Total deployment time**: 15-30 minutes
**Monthly cost**: $9-24 USD
**No vendor lock-in**: Can migrate to any provider
