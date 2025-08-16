# OpenDiscourse Automation Services Deployment Guide

This guide provides instructions for deploying and managing the OpenDiscourse automation services, including n8n workflow automation and backup management.

## Prerequisites

- Docker and Docker Compose installed
- OpenDiscourse stack deployed
- DNS records configured for:
  - `n8n.opendiscourse.net`
  - `s3.opendiscourse.net`
  - `*.opendiscourse.net`

## Deployment Steps

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/opendiscourse.net---supacontainer.git
cd opendiscourse.net---supacontainer
```

### 2. Configure Environment

Create or update the `.env` file in the root directory with the following variables:

```bash
# Domain Configuration
DOMAIN=opendiscourse.net

# SMTP Configuration
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=user@opendiscourse.net
SMTP_PASSWORD=your-smtp-password

# MinIO Configuration
MINIO_ACCESS_KEY=your-access-key
MINIO_SECRET_KEY=your-secret-key

# n8n Configuration
N8N_USER=admin
N8N_PASSWORD=your-secure-password
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
N8N_JWT_SECRET=$(openssl rand -hex 32)
```

### 3. Deploy Automation Services

Run the deployment script:

```bash
sudo ./automation/deploy.sh
```

This will:
1. Set up required directories
2. Deploy n8n and backup services
3. Configure Traefik routing
4. Verify the services are running

### 4. Access the Services

- **n8n Workflow Automation**: https://n8n.opendiscourse.net
  - Use the credentials from `.env` (N8N_USER/N8N_PASSWORD)

- **MinIO S3 Console**: https://s3.opendiscourse.net
  - Use the MinIO credentials from `.env`

## Backup Configuration

Backups are configured to run daily at 2:00 AM with a 7-day retention policy. The backup service will automatically:

1. Create compressed backups of all volumes
2. Upload them to the configured S3-compatible storage (MinIO)
3. Remove backups older than 7 days

### Manual Backup

To create a manual backup:

```bash
cd /opt/opendiscourse
docker-compose -f docker-compose.yml -f automation/docker-compose.automation.yml run --rm backup
```

## Monitoring

Check service status:

```bash
# View running containers
docker ps

# View logs for a specific service
docker-compose logs -f n8n

# View backup logs
docker-compose logs -f backup
```

## Troubleshooting

### Common Issues

1. **Certificate Errors**
   - Ensure DNS records are properly configured
   - Check Traefik logs: `docker-compose logs traefik`

2. **n8n Not Accessible**
   - Verify the container is running: `docker ps | grep n8n`
   - Check logs: `docker-compose logs n8n`

3. **Backup Failures**
   - Verify MinIO credentials in `.env`
   - Check backup container logs: `docker-compose logs backup`

## Security Considerations

- Always use strong, unique passwords
- Regularly rotate encryption keys and secrets
- Monitor access logs for suspicious activity
- Keep the system updated with security patches

## Updating Services

To update the automation services:

1. Pull the latest changes
2. Rebuild and restart the services:

```bash
cd /opt/opendiscourse
docker-compose -f docker-compose.yml -f automation/docker-compose.automation.yml pull
docker-compose -f docker-compose.yml -f automation/docker-compose.automation.yml up -d --build
```

## Support

For issues or questions, please open an issue on the GitHub repository.
