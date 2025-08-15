# Detailed Deployment Guide

This guide provides step-by-step instructions for deploying the OpenDiscourse Monitoring Stack.

## Prerequisites

### Hardware Requirements
- **Minimum**:
  - 4 vCPUs
  - 8GB RAM
  - 100GB SSD storage
- **Recommended**:
  - 8 vCPUs
  - 16GB RAM
  - 200GB+ SSD storage

### Software Requirements
- Ubuntu 20.04/22.04 LTS
- Docker 20.10.0+
- Docker Compose 2.0.0+
- Git
- Python 3.8+

## Deployment Steps

### 1. Server Setup

#### Initial Server Configuration
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    git \
    python3-pip \
    python3-venv \
    unzip \
    jq \
    htop \
    net-tools

# Set timezone
sudo timedatectl set-timezone UTC

# Enable automatic updates
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

#### Docker Installation
```bash
# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Set up the stable repository
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Install Docker Compose
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Add current user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Enable and start Docker
sudo systemctl enable docker
sudo systemctl start docker
```

### 2. Clone the Repository

```bash
# Clone the repository
cd ~
git clone https://github.com/yourusername/opendiscourse-monitoring.git
cd opendiscourse-monitoring

# Create necessary directories
mkdir -p data/{grafana,prometheus,loki,opensearch,rabbitmq,backups}
```

### 3. Configuration

#### Environment Setup
```bash
# Copy example environment file
cp .env.example .env

# Generate random passwords
GENERATE_PASSWORDS=1 ./scripts/generate_secrets.sh

# Edit the .env file with your configuration
nano .env
```

#### Required Configuration
Update the following variables in `.env`:
```ini
# Domain and Email
DOMAIN=yourdomain.com
EMAIL=your.email@example.com

# Cloudflare
CF_API_EMAIL=your.cloudflare@email.com
CF_API_KEY=your_cloudflare_api_key

# OpenSearch Credentials
OPENSEARCH_USER=admin
OPENSEARCH_PASSWORD=your_secure_password

# Grafana
GRAFANA_ADMIN_PASSWORD=your_secure_password

# RabbitMQ
RABBITMQ_DEFAULT_USER=admin
RABBITMQ_DEFAULT_PASS=your_secure_password
```

### 4. Deploy the Stack

#### Initial Deployment
```bash
# Make deployment script executable
chmod +x deploy.sh

# Start the deployment
./deploy.sh
```

This will:
1. Pull all required Docker images
2. Configure all services
3. Start the stack in detached mode
4. Set up initial dashboards and configurations

#### Verify Deployment
```bash
# Check running containers
docker ps

# View logs
docker-compose logs -f

# Check service status
./scripts/status.sh
```

### 5. Post-Deployment Configuration

#### Cloudflare Tunnel Setup
```bash
# Install cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# Authenticate with Cloudflare
cloudflared tunnel login

# Create a new tunnel
cloudflared tunnel create monitoring-tunnel

# Configure the tunnel
mkdir -p ~/.cloudflared/
cat > ~/.cloudflared/config.yml << EOL
tunnel: <tunnel-id>
credentials-file: /root/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: grafana.yourdomain.com
    service: http://localhost:3000
  - hostname: prometheus.yourdomain.com
    service: http://localhost:9090
  - hostname: loki.yourdomain.com
    service: http://localhost:3100
  - hostname: alertmanager.yourdomain.com
    service: http://localhost:9093
  - service: http_status:404
EOL

# Start the tunnel
cloudflared --config ~/.cloudflared/config.yml service install
systemctl start cloudflared
systemctl enable cloudflared
```

#### DNS Configuration
Create the following DNS records in your Cloudflare dashboard:
- A record: `monitoring` → Your server IP (proxied)
- CNAME records for all services pointing to your domain

### 6. Initial Setup

#### Grafana Configuration
1. Access Grafana at `https://grafana.yourdomain.com`
2. Login with admin/your_secure_password
3. Change the default password when prompted
4. Import dashboards from `grafana/dashboards/`

#### Prometheus Configuration
1. Access Prometheus at `https://prometheus.yourdomain.com`
2. Check status → Targets to ensure all services are up
3. Import alert rules from `prometheus/alert_rules.yml`

#### OpenSearch Configuration
1. Access OpenSearch at `https://opensearch.yourdomain.com`
2. Login with admin/your_secure_password
3. Create index patterns for your logs

### 7. Monitoring and Maintenance

#### Daily Tasks
```bash
# Check service status
./scripts/status.sh

# Check disk usage
df -h

# Check resource usage
docker stats --no-stream
```

#### Backup and Restore
```bash
# Create a backup
./backup_scripts/backup.sh

# Restore from backup
./backup_scripts/restore.sh /path/to/backup.tar.gz
```

#### Updating the Stack
```bash
# Pull latest changes
git pull

# Rebuild and restart containers
docker-compose up -d --build

# Run database migrations if needed
./scripts/run_migrations.sh
```

## Troubleshooting

### Common Issues

#### Port Conflicts
```bash
# Check which process is using a port
sudo lsof -i :<port>

# Or using ss
sudo ss -tulpn | grep :<port>
```

#### Docker Issues
```bash
# Check container logs
docker logs <container_name>

# Prune unused resources
docker system prune -f

# Rebuild a specific service
docker-compose up -d --no-deps --build <service_name>
```

#### Performance Issues
```bash
# Check system resources
top
htop

# Check container resource usage
docker stats

# Check disk I/O
iotop
```

## Security Hardening

### Firewall Configuration
```bash
# Install UFW if not installed
sudo apt install ufw

# Allow SSH
sudo ufw allow ssh

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Enable UFW
sudo ufw enable

# Check status
sudo ufw status verbose
```

### Automatic Security Updates
```bash
# Install unattended-upgrades
sudo apt install -y unattended-upgrades

# Configure automatic updates
sudo dpkg-reconfigure -plow unattended-upgrades

# Edit configuration
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
```

## Backup and Recovery

### Backup Strategy
1. **Daily Incremental Backups**
   - Docker volumes
   - Configuration files
   - Database dumps

2. **Weekly Full Backups**
   - Complete system snapshot
   - Off-site storage

### Backup Scripts
- `backup_scripts/backup.sh`: Creates a complete backup
- `backup_scripts/restore.sh`: Restores from backup
- `backup_scripts/rotate_backups.sh`: Manages backup retention

## Monitoring and Alerting

### Alert Configuration
1. **Prometheus Alerts**: Configured in `prometheus/alert_rules.yml`
2. **Grafana Alerts**: Set up in the Grafana UI
3. **Email Notifications**: Configure in `grafana/grafana.ini`

### Alert Channels
- Email
- Slack
- PagerDuty
- Webhooks

## Scaling

### Vertical Scaling
- Increase CPU/RAM allocation
- Optimize container resources in `docker-compose.yml`

### Horizontal Scaling
- Add more worker nodes
- Configure Docker Swarm or Kubernetes

## Maintenance

### Regular Maintenance Tasks
1. **Weekly**:
   - Check for updates
   - Review logs
   - Test backups

2. **Monthly**:
   - Security audit
   - Performance review
   - Clean up old data

### Update Procedure
```bash
# Pull latest changes
git pull

# Rebuild and restart
docker-compose up -d --build

# Run migrations if needed
./scripts/run_migrations.sh
```

## Support

### Getting Help
- Check the [FAQ](./FAQ.md)
- Review the [troubleshooting guide](./TROUBLESHOOTING.md)
- Open an issue on GitHub

### Community
- Join our [Discord server](https://discord.gg/opendiscourse)
- Check the [forum](https://forum.opendiscourse.net)

## License
[Your License Here]

---
Last updated: $(date +"%Y-%m-%d")
