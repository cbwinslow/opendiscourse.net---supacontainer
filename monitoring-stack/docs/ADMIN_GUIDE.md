# OpenDiscourse Monitoring Stack Administrator's Guide

## Table of Contents
1. [System Architecture](#system-architecture)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [User Management](#user-management)
5. [Monitoring Configuration](#monitoring-configuration)
6. [Alerting Setup](#alerting-setup)
7. [Backup and Recovery](#backup-and-recovery)
8. [Security Hardening](#security-hardening)
9. [Troubleshooting](#troubleshooting)
10. [Upgrading](#upgrading)

## System Architecture

### Component Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│                 │    │                 │    │                 │
│   Prometheus    │◄───┤     Grafana     ├───►   OpenSearch    │
│                 │    │                 │    │                 │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │                      │                      │
         │                      │                      │
         ▼                      ▼                      ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│                 │    │                 │    │                 │
│      Loki       │    │   RabbitMQ      │    │  AI Orchestrator │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Network Ports

| Port  | Service          | Protocol | Description                     |
|-------|------------------|----------|---------------------------------|
| 3000  | Grafana          | TCP      | Web interface                   |
| 9090  | Prometheus       | TCP      | Metrics and alerting            |
| 9093  | Alertmanager    | TCP      | Alert management                |
| 3100  | Loki             | TCP      | Log aggregation                 |
| 9200  | OpenSearch       | TCP      | Search and analytics            |
| 9300  | OpenSearch       | TCP      | Node communication              |
| 5672  | RabbitMQ         | TCP      | AMQP protocol                   |
| 15672 | RabbitMQ         | TCP      | Management UI                   |
| 8000  | AI Orchestrator  | TCP      | REST API                        |
| 9090  | Cockpit          | TCP      | Server management               |
| 3001  | ntopng           | TCP      | Network traffic monitoring      |

## Installation

### Prerequisites

- Ubuntu 20.04/22.04 LTS server
- Minimum 8GB RAM, 4 vCPUs, 100GB disk space
- Docker 20.10.0+ and Docker Compose 2.0.0+
- Domain name with DNS access

### Automated Installation

```bash
# Clone the repository
git clone https://github.com/yourorg/opendiscourse-monitoring.git
cd opendiscourse-monitoring

# Make the deployment script executable
chmod +x deploy_to_hetzner.sh

# Run the deployment script
./deploy_to_hetzner.sh
```

### Manual Installation

1. **Install Docker and Docker Compose**
   ```bash
   # Install required packages
   sudo apt update
   sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
   
   # Add Docker's official GPG key
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
   
   # Set up the stable repository
   echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
   
   # Install Docker Engine
   sudo apt update
   sudo apt install -y docker-ce docker-ce-cli containerd.io
   
   # Install Docker Compose
   sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
   sudo chmod +x /usr/local/bin/docker-compose
   ```

2. **Clone the repository**
   ```bash
   git clone https://github.com/yourorg/opendiscourse-monitoring.git
   cd opendiscourse-monitoring
   ```

3. **Configure environment variables**
   ```bash
   cp .env.example .env
   nano .env  # Edit the configuration
   ```

4. **Start the stack**
   ```bash
   docker-compose up -d
   ```

## Configuration

### Environment Variables

Edit the `.env` file to configure the following:

```ini
# General
DOMAIN=yourdomain.com
TIMEZONE=UTC

# Grafana
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=your_secure_password

# Prometheus
PROMETHEUS_RETENTION=30d

# OpenSearch
OPENSEARCH_USER=admin
OPENSEARCH_PASSWORD=your_secure_password

# RabbitMQ
RABBITMQ_DEFAULT_USER=admin
RABBITMQ_DEFAULT_PASS=your_secure_password

# AI Orchestrator
AI_ORCHESTRATOR_API_KEY=your_api_key
```

### Persistent Storage

By default, the following directories are mounted as volumes:

- `/data/grafana`: Grafana data and dashboards
- `/data/prometheus`: Prometheus metrics data
- `/data/loki`: Loki log data
- `/data/opensearch`: OpenSearch data
- `/data/rabbitmq`: RabbitMQ data

## User Management

### Creating Service Accounts

1. **Grafana Service Account**
   ```bash
   curl -X POST \
     -H "Content-Type: application/json" \
     -d '{"name":"api-token", "role":"Admin"}' \
     http://admin:password@localhost:3000/api/auth/keys
   ```

2. **OpenSearch User**
   ```bash
   # Create a new user
   curl -X PUT "localhost:9200/_security/user/user1?pretty" \
     -H 'Content-Type: application/json' \
     -u admin:admin \
     -d '{
       "password" : "user_password",
       "roles" : [ "monitoring_user" ]
     }'
   ```

### LDAP Integration

1. Configure LDAP in `grafana/ldap.toml`
2. Update Grafana configuration:
   ```ini
   [auth.ldap]
   enabled = true
   config_file = /etc/grafana/ldap.toml
   ```
3. Restart Grafana

## Monitoring Configuration

### Adding New Targets

1. **Prometheus**
   Edit `prometheus/prometheus.yml` to add new scrape targets:
   ```yaml
   - job_name: 'node'
     static_configs:
       - targets: ['node-exporter:9100']
   ```

2. **Loki**
   Configure log shipping in `loki/loki-config.yaml`

### Custom Dashboards

1. **Importing Dashboards**
   - Navigate to Dashboards > Manage
   - Click "Import"
   - Upload dashboard JSON or paste dashboard ID

2. **Creating Dashboards**
   - Click "Create" > "Dashboard"
   - Add panels with PromQL/Loki queries
   - Save the dashboard

## Alerting Setup

### Prometheus Alerts

Edit `prometheus/alert_rules.yml`:
```yaml
groups:
- name: example
  rules:
  - alert: HighErrorRate
    expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
    for: 10m
    labels:
      severity: critical
    annotations:
      summary: High error rate on {{ $labels.instance }}
      description: "{{ $value }}% of requests are failing"
```

### Alertmanager Configuration

Edit `prometheus/alertmanager.yml`:
```yaml
route:
  receiver: 'slack-notifications'
  group_by: ['alertname', 'cluster']

receivers:
- name: 'slack-notifications'
  slack_configs:
  - api_url: 'https://hooks.slack.com/services/...'
    channel: '#alerts'
```

## Backup and Recovery

### Manual Backup

```bash
./backup_scripts/backup.sh
```

### Restoring from Backup

```bash
./backup_scripts/restore.sh /path/to/backup.tar.gz
```

### Automated Backups

Add to crontab for daily backups:
```
0 2 * * * /path/to/backup_scripts/backup.sh
```

## Security Hardening

### Firewall Configuration

```bash
# Allow only necessary ports
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

### SSL/TLS Configuration

1. Obtain certificates:
   ```bash
   certbot certonly --standalone -d monitoring.yourdomain.com
   ```

2. Update Traefik configuration:
   ```toml
   [entryPoints.https]
     address = ":443"
     [entryPoints.https.tls]
       [[entryPoints.https.tls.certificates]]
         certFile = "/etc/letsencrypt/live/yourdomain.com/fullchain.pem"
         keyFile = "/etc/letsencrypt/live/yourdomain.com/privkey.pem"
   ```

## Troubleshooting

### Common Issues

#### Prometheus Not Scraping Targets
1. Check target status: `http://localhost:9090/targets`
2. Verify network connectivity
3. Check service discovery configuration

#### High Disk Usage
1. Check disk usage: `df -h`
2. Adjust retention policies in Prometheus/Loki
3. Clean up old data:
   ```bash
   # For Prometheus
   docker-compose exec prometheus prometheus --storage.tsdb.retention.time=30d
   
   # For Loki
   docker-compose exec loki logcli --addr=http://loki:3100 delete --older-than=720h
   ```

### Logs

View logs for all services:
```bash
docker-compose logs -f
```

View logs for a specific service:
```bash
docker-compose logs -f grafana
```

## Upgrading

### Minor Version Upgrades

```bash
git pull
docker-compose pull
docker-compose up -d
```

### Major Version Upgrades

1. Check the release notes for breaking changes
2. Backup all data
3. Stop the stack:
   ```bash
   docker-compose down
   ```
4. Update the configuration files
5. Start the stack:
   ```bash
   docker-compose up -d
   ```
6. Verify all services are running

### Database Migrations

Some upgrades may require database migrations. Check the release notes for specific instructions.

---
Last updated: $(date +"%Y-%m-%d")
