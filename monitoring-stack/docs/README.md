# OpenDiscourse Monitoring Stack Documentation

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Deployment Guide](#deployment-guide)
3. [Configuration](#configuration)
4. [Maintenance](#maintenance)
5. [Security](#security)
6. [Troubleshooting](#troubleshooting)
7. [API Documentation](#api-documentation)
8. [Agent Development](#agent-development)

## Architecture Overview

### Core Components
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation
- **OpenSearch**: Log and event storage
- **RabbitMQ**: Message broker for AI agents
- **AI Orchestrator**: Central brain for automated operations
- **Cockpit**: Web-based server management
- **Snort**: Network intrusion detection
- **ntopng**: Network traffic monitoring
- **Cloudflare WAF**: Web application firewall

### Data Flow
```
[Services] → [Prometheus/Loki] → [Grafana]
    ↓
[RabbitMQ] ←→ [AI Orchestrator] → [OpenSearch]
    ↑
[Agents] → [Actions]
```

## Deployment Guide

### Prerequisites
- Ubuntu 20.04/22.04 server
- Root access
- Minimum 8GB RAM, 4 vCPUs, 100GB disk
- Domain name (for HTTPS)

### Quick Start
1. Clone the repository
2. Copy `.env.example` to `.env` and configure
3. Run `./deploy_to_hetzner.sh`

### Detailed Deployment
[See detailed deployment guide](./DEPLOYMENT.md)

## Configuration

### Environment Variables
- `DOMAIN`: Your domain name
- `EMAIL`: Email for Let's Encrypt
- `CF_TOKEN`: Cloudflare API token
- `OPENSEARCH_USER`: OpenSearch admin user
- `OPENSEARCH_PASSWORD`: OpenSearch admin password

### Service Configuration
- [Prometheus Configuration](./docs/prometheus.md)
- [Grafana Dashboards](./docs/grafana.md)
- [AI Orchestrator Setup](./docs/orchestrator.md)
- [Security Configuration](./docs/security.md)

## Maintenance

### Backups
Automated backups are configured to run daily. To restore:
```bash
./backup_scripts/restore.sh /path/to/backup.tar.gz
```

### Updates
To update the stack:
```bash
git pull
docker-compose pull
docker-compose up -d --force-recreate
```

## Security

### Hardening
- All services run with least privilege
- Automatic security updates enabled
- Intrusion detection with Snort
- File integrity monitoring with AIDE

### Monitoring
- Real-time security alerts
- Daily security reports
- Log analysis with OpenSearch

## Troubleshooting

### Common Issues
- **Port conflicts**: Check running services with `ss -tulnp`
- **Docker issues**: Run `docker system prune -f` and restart
- **Logs**: Check container logs with `docker-compose logs -f`

### Recovery
1. Stop services: `docker-compose down`
2. Restore from backup
3. Start services: `docker-compose up -d`

## API Documentation

### AI Orchestrator API
- Base URL: `https://api.yourdomain.com/v1`
- Authentication: Bearer token
- [Full API Documentation](./API.md)

### Message Schema
```json
{
  "message_type": "alert|metric|log",
  "source": "service_name",
  "timestamp": "ISO-8601",
  "content": {},
  "severity": "info|warning|error|critical"
}
```

## Agent Development

### Creating a New Agent
1. Create a new Python file in `agents/`
2. Extend the `BaseAgent` class
3. Implement required methods
4. Register the agent in `config/agents.yaml`

### Agent Lifecycle
1. **Initialization**: Load configuration, connect to RabbitMQ
2. **Startup**: Register with orchestrator
3. **Operation**: Process messages, execute tasks
4. **Shutdown**: Clean up resources

### Best Practices
- Use environment variables for configuration
- Implement proper error handling
- Include logging
- Write unit tests
- Document your agent

---
For additional help, please contact the system administrator or open an issue in the repository.
