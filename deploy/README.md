# OpenDiscourse Deployment

This repository contains the deployment scripts and documentation for OpenDiscourse, an open-source discussion platform.

## Prerequisites

- Ubuntu 20.04/22.04 LTS server
- Minimum 4GB RAM (8GB recommended for production)
- Minimum 2 CPU cores (4 recommended for production)
- Minimum 50GB free disk space
- Domain name pointing to your server's IP
- Ports 80, 443, and 22 open in your firewall

## Quick Start

### 1. Server Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required tools
sudo apt install -y git curl wget

# Clone this repository
mkdir -p /opt/opendiscourse
cd /opt/opendiscourse
git clone https://github.com/your-org/opendiscourse-deploy.git .

# Make the installation script executable
chmod +x deploy/install_opendiscourse.sh
```

### 2. Configure Environment

Edit the `.env` file with your configuration:

```bash
cp .env.example .env
nano .env
```

### 3. Run the Installation

```bash
sudo -E ./deploy/install_opendiscourse.sh
```

## Configuration

### Environment Variables

Edit the `.env` file to configure your installation:

```env
# Basic Configuration
DOMAIN=your-domain.com
EMAIL=admin@your-domain.com

# Database
POSTGRES_USER=opendiscourse
POSTGRES_PASSWORD=generate-a-secure-password
POSTGRES_DB=opendiscourse

# Redis
REDIS_PASSWORD=generate-a-secure-password

# JWT
JWT_SECRET=generate-a-secure-secret

# Traefik
TRAEFIK_USER=admin
TRAEFIK_PASSWORD=generate-a-secure-password

# SMTP Configuration
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=user@example.com
SMTP_PASSWORD=your-smtp-password
SMTP_FROM=noreply@your-domain.com
```

### Ports

- `80` - HTTP (required for Let's Encrypt verification)
- `443` - HTTPS
- `3000` - Grafana (optional)
- `9090` - Prometheus (optional)

## Maintenance

### Backup

Automatic daily backups are configured to run at 2 AM. Backups are stored in `/opt/opendiscourse/data/backups` and kept for 30 days by default.

To create a manual backup:

```bash
cd /opt/opendiscourse
./scripts/backup.sh
```

### Updating

To update to the latest version:

```bash
cd /opt/opendiscourse
git pull
sudo -E ./deploy/install_opendiscourse.sh
```

### Monitoring

Access monitoring dashboards:

- **Grafana**: http://your-server-ip:3000
- **Traefik Dashboard**: https://traefik.your-domain.com

## Security

- All services run in isolated Docker containers
- Automatic HTTPS with Let's Encrypt
- Firewall configured to allow only necessary ports
- Regular security updates through unattended-upgrades

## Troubleshooting

### View Logs

```bash
# Application logs
cd /opt/opendiscourse
docker-compose logs -f

# Traefik logs
docker logs traefik
```

### Common Issues

1. **Port Conflicts**: Ensure ports 80 and 443 are not in use by other services
2. **DNS Propagation**: After changing DNS, it may take up to 48 hours to propagate
3. **Let's Encrypt Rate Limits**: Use staging certificates during testing by setting `CERT_RESOLVER=staging` in `.env`

## License

MIT License - See [LICENSE](LICENSE) for more information.
