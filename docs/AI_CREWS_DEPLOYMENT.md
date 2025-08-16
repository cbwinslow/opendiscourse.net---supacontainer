# AI Crews Deployment Guide

This document provides a comprehensive guide to deploying and managing the AI Crews and Monitoring Stack for OpenDiscourse.

## Prerequisites

- Ubuntu 20.04/22.04 LTS
- Docker 20.10.0 or later
- Docker Compose v2.0.0 or later
- Minimum 8GB RAM (16GB recommended)
- Minimum 4 vCPUs (8 recommended)
- At least 50GB of free disk space

## Deployment Steps

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/opendiscourse.net---supacontainer.git
cd opendiscourse.net---supacontainer
```

### 2. Run the Deployment Script

```bash
sudo ./deploy_ai_crews.sh
```

This script will:
1. Install required dependencies (Docker, Docker Compose, etc.)
2. Deploy the monitoring stack (Prometheus, Grafana, Loki, Jaeger)
3. Deploy the AI crews (orchestrator, security, monitoring, deployment)
4. Configure Grafana dashboards and data sources

### 3. Verify the Deployment

After the deployment completes, run the verification script:

```bash
sudo ./verify_ai_crews.sh
```

This will check that all services are running correctly and accessible.

## Accessing the Services

- **Grafana**: http://your-server-ip:3000 (admin/admin)
- **Prometheus**: http://your-server-ip:9090
- **Jaeger UI**: http://your-server-ip:16686
- **Loki**: http://your-server-ip:3100
- **AI Orchestrator API**: http://your-server-ip:8000

## Configuration

### Environment Variables

You can customize the deployment by setting the following environment variables before running the deployment script:

```bash
export STACK_DIR=/opt/opendiscourse  # Custom installation directory
export GRAFANA_ADMIN_PASSWORD=secure_password  # Change Grafana admin password
export AI_ORCHESTRATOR_IMAGE=your-registry/ai-orchestrator:latest  # Custom image
```

### Persistent Data

All persistent data is stored in the following directories by default:

- `/opt/opendiscourse/monitoring/grafana` - Grafana data and dashboards
- `/opt/opendiscourse/monitoring/prometheus` - Prometheus time-series data
- `/opt/opendiscourse/monitoring/loki` - Loki logs
- `/opt/opendiscourse/ai_crews/postgres` - PostgreSQL database
- `/opt/opendiscourse/ai_crews/redis` - Redis data

## Monitoring and Logging

### Grafana Dashboards

Several pre-configured dashboards are available:

1. **AI Crews Overview**: High-level metrics for all AI services
2. **Container Metrics**: Detailed container resource usage
3. **Log Explorer**: Search and analyze logs across all services
4. **Tracing**: Distributed tracing with Jaeger

### Alerting

Alerting is configured to notify on the following conditions:

- Container restarts
- High CPU/Memory usage
- Service unavailability
- Error rates exceeding thresholds

## Maintenance

### Updating the Stack

To update the stack to the latest version:

```bash
git pull origin main
sudo ./deploy_ai_crews.sh
```

### Backups

Regular backups of the following directories are recommended:

- `/opt/opendiscourse/monitoring/grafana`
- `/opt/opendiscourse/ai_crews/postgres`
- `/opt/opendiscourse/ai_crews/redis`

### Logs

All service logs can be accessed via:

```bash
# View logs for all services
docker-compose -f monitoring-stack/opentelemetry/docker-compose.otel.yml logs
docker-compose -f monitoring-stack/ai_crews/docker-compose.yml logs

# View logs for a specific service
docker-compose -f monitoring-stack/ai_crews/docker-compose.yml logs ai-orchestrator
```

## Troubleshooting

### Common Issues

1. **Port conflicts**: Ensure ports 3000, 9090, 3100, 16686, and 8000 are available
2. **Permission issues**: Run deployment script with `sudo`
3. **Insufficient resources**: Check Docker logs for out-of-memory errors
4. **Network issues**: Ensure Docker network 'monitoring' exists

### Getting Help

For additional support, please open an issue on our [GitHub repository](https://github.com/yourusername/opendiscourse.net---supacontainer/issues).

## Security Considerations

1. Change default credentials (Grafana, PostgreSQL, Redis)
2. Enable HTTPS for all web interfaces
3. Restrict access to monitoring endpoints using a firewall
4. Regularly update Docker images to the latest versions
5. Monitor security advisories for all components

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
