# Domain Configuration for OpenDiscourse

This document outlines the domain configuration for the OpenDiscourse deployment, including primary and fallback domains, service endpoints, and DNS requirements.

## Primary Domain
- **Domain**: `opendiscourse.net`
- **Usage**: Primary domain for all services
- **SSL/TLS**: Managed by Let's Encrypt

## Fallback Domain
- **Domain**: `cloudcurio.cc`
- **Usage**: Secondary domain for redundancy
- **SSL/TLS**: Included in the same certificate

## Service Endpoints

### n8n Workflow Automation
- **URL**: `https://n8n.opendiscourse.net`
- **Alternative**: `https://n8n.cloudcurio.cc`
- **Port**: 5678
- **Authentication**: Basic Auth

### MinIO S3 Storage
- **Endpoint**: `s3.opendiscourse.net`
- **Port**: 9000
- **Alternative**: `s3.cloudcurio.cc`
- **Protocol**: HTTPS

### Email Sender
- **Address**: `n8n@opendiscourse.net`
- **SMTP**: Configured via environment variables

## DNS Configuration

### Required Records
```
# Primary Domain
opendiscourse.net.    A      <server-ip>
*.opendiscourse.net.  CNAME  opendiscourse.net.

# Fallback Domain
cloudcurio.cc.        A      <server-ip>
*.cloudcurio.cc.      CNAME  cloudcurio.cc.
```

## SSL/TLS Configuration
- **Certificate Provider**: Let's Encrypt
- **Certificate Resolver**: `le`
- **Domains Covered**:
  - `opendiscourse.net`
  - `*.opendiscourse.net`
  - `cloudcurio.cc`
  - `*.cloudcurio.cc`

## Environment Variables

### Required
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
```

## Deployment Notes
1. Ensure DNS records are properly configured before deployment
2. Verify SSL certificate issuance during first deployment
3. Check Traefik logs for any certificate-related issues

## Troubleshooting

### Certificate Issues
```bash
# Check Traefik logs for certificate errors
docker logs traefik

# Verify DNS resolution
dig +short n8n.opendiscourse.net
dig +short s3.opendiscourse.net
```

### Service Health
```bash
# Check service status
docker-compose ps

# View logs for a specific service
docker-compose logs n8n
```

## Backup and Restore

### Backup Configuration
- **Location**: `/opt/opendiscourse/backups`
- **Retention**: 7 days
- **Schedule**: Daily at 2:00 AM

### Manual Backup
```bash
cd /opt/opendiscourse
./deploy.sh backup
```

### Restore from Backup
```bash
cd /opt/opendiscourse
./deploy.sh restore <backup-timestamp>
```

## Security Considerations
- All services are protected by HTTPS
- Basic authentication is enabled for sensitive endpoints
- Regular security updates are recommended
- Monitor Traefik access logs for suspicious activity
