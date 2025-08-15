# OpenDiscourse Monitoring Stack User Guide

## Table of Contents
1. [Introduction](#introduction)
2. [Quick Start](#quick-start)
3. [Accessing Services](#accessing-services)
4. [User Management](#user-management)
5. [Monitoring](#monitoring)
6. [Alerting](#alerting)
7. [Logging](#logging)
8. [Backup and Recovery](#backup-and-recovery)
9. [Troubleshooting](#troubleshooting)
10. [FAQs](#faqs)

## Introduction

Welcome to the OpenDiscourse Monitoring Stack! This guide will help you get started with monitoring your infrastructure, applications, and security events.

### Key Features

- **Real-time Monitoring**: Track system metrics, logs, and application performance
- **Security Monitoring**: Detect and respond to security threats
- **Alerting**: Get notified of issues before they impact your users
- **Visualization**: Create custom dashboards to visualize your data
- **AI-Powered Analysis**: Leverage AI to identify patterns and anomalies

## Quick Start

### Prerequisites

- Web browser (Chrome, Firefox, or Edge recommended)
- Network access to the monitoring server
- Valid user credentials

### First-Time Login

1. Open your web browser and navigate to the Grafana URL provided by your administrator
2. Enter your username and password
3. Change your password when prompted
4. Explore the pre-configured dashboards

## Accessing Services

### Web Interfaces

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| Grafana | `http://<server-ip>:3000` | admin / [from credentials] |
| Prometheus | `http://<server-ip>:9090` | None |
| OpenSearch | `http://<server-ip>:9200` | admin / [from credentials] |
| RabbitMQ | `http://<server-ip>:15672` | guest / [from credentials] |
| Cockpit | `http://<server-ip>:9090` | System credentials |
| ntopng | `http://<server-ip>:3001` | admin / admin |

### API Access

```bash
# Example: Query metrics via API
curl -H "Authorization: Bearer $API_KEY" \
     http://<server-ip>:8000/api/v1/metrics
```

## User Management

### Creating New Users

1. Log in to Grafana as an administrator
2. Navigate to Configuration > Users
3. Click "New user"
4. Fill in the user details and assign appropriate roles
5. Click "Create user" and share the temporary password

### Managing Permissions

- **Viewer**: Can view dashboards and data
- **Editor**: Can create and edit dashboards
- **Admin**: Full access to all settings and configurations

## Monitoring

### Viewing Dashboards

1. Log in to Grafana
2. Navigate to "Dashboards" in the left sidebar
3. Browse or search for dashboards
4. Use the time picker to adjust the time range

### Key Dashboards

- **System Overview**: CPU, memory, disk, and network metrics
- **Application Performance**: Response times and error rates
- **Security Dashboard**: Security events and alerts
- **Database Performance**: Query performance and resource usage

### Creating Custom Dashboards

1. Click "Create" > "Dashboard"
2. Add panels to visualize your metrics
3. Configure queries and visualization options
4. Save the dashboard

## Alerting

### Configuring Alerts

1. Navigate to "Alerting" > "Alert rules"
2. Click "New alert rule"
3. Define the condition for the alert
4. Configure notification policies
5. Save the alert rule

### Notification Channels

- Email
- Slack
- PagerDuty
- Webhooks

## Logging

### Viewing Logs

1. Navigate to "Explore" in Grafana
2. Select "Loki" as the data source
3. Enter a log query (e.g., `{job="varlogs"}`)
4. Click "Run query"

### Common Log Queries

```
# Show error logs
{level="error"}

# Show logs from a specific service
{service="api"}

# Search for specific text
{job="varlogs"} |= "error"
```

## Backup and Recovery

### Manual Backup

```bash
# Create a backup
./backup_scripts/backup.sh

# The backup will be saved to: /backups/monitoring_backup_<timestamp>.tar.gz
```

### Restoring from Backup

```bash
# Restore from the latest backup
./backup_scripts/restore.sh /path/to/backup.tar.gz
```

### Automated Backups

Daily backups are automatically created and retained for 7 days.

## Troubleshooting

### Common Issues

#### Can't Access Grafana
- Verify the service is running: `docker ps | grep grafana`
- Check logs: `docker-compose logs -f grafana`
- Verify port 3000 is open

#### Missing Metrics
- Check if Prometheus is running
- Verify targets are healthy in Prometheus UI
- Check service discovery configuration

#### High Resource Usage
1. Identify the process using `top` or `htop`
2. Check container resource usage: `docker stats`
3. Review logs for errors

### Getting Help

1. Check the [FAQ](#faqs) section below
2. Review service logs
3. Contact your system administrator

## FAQs

### How do I reset my password?

1. Click "Forgot password?" on the login page
2. Follow the instructions in the email
3. If you don't receive an email, contact your administrator

### How do I add a new data source?

1. Log in as an administrator
2. Go to Configuration > Data Sources
3. Click "Add data source"
4. Select the type and configure the connection

### How do I create a custom dashboard?

1. Click "Create" > "Dashboard"
2. Add panels and configure queries
3. Save the dashboard

### How do I set up alerts?

1. Go to Alerting > Alert rules
2. Click "New alert rule"
3. Define the condition and notification settings
4. Save the rule

### How do I access logs?

1. Go to "Explore" in Grafana
2. Select the Loki data source
3. Enter your query and run it

## Additional Resources

- [Grafana Documentation](https://grafana.com/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [OpenSearch Documentation](https://opensearch.org/docs/)
- [RabbitMQ Documentation](https://www.rabbitmq.com/documentation.html)

---
Last updated: $(date +"%Y-%m-%d")
