# Alerting Configuration

This directory contains the Alertmanager configuration for the OpenDiscourse monitoring stack.

## Alert Rules

Alert rules are defined in `prometheus/alert.rules` and include the following alerts:

### Container Alerts
- **ContainerRestarted**: Container has restarted more than 3 times in 5 minutes
- **ContainerOOMKilled**: Container was OOM killed
- **ServiceDown**: Service is not responding to health checks

### Resource Alerts
- **HighCpuUsage**: CPU usage > 80% for 5 minutes
- **HighMemoryUsage**: Memory usage > 80% for 5 minutes
- **LowDiskSpace**: Disk space < 20% remaining

### Application Alerts
- **HighErrorRate**: More than 5 errors per second in logs

## Alertmanager Configuration

Alertmanager is configured to handle alerts with the following receivers:

1. **email-admin**: Sends all alerts to admin@opendiscourse.net
2. **email-devops**: Receives resource-related alerts
3. **email-pagerduty**: Receives critical alerts for immediate attention

### Routing
- Critical alerts go to PagerDuty
- CPU/Memory alerts go to DevOps team
- All other alerts go to admin

## Setup

1. Update SMTP settings in `alertmanager.yml`
2. Set PagerDuty integration key as an environment variable:
   ```bash
   export SMTP_PASSWORD='your-smtp-password'
   ```
3. Deploy the monitoring stack:
   ```bash
   ./deploy_monitoring.sh
   ```

## Testing Alerts

To test the alerting pipeline:

1. Trigger a test alert:
   ```bash
   curl -H "Content-Type: application/json" -d '{"receiver":"email-admin","status":"firing","alerts":[{"status":"firing","labels":{"alertname":"TestAlert","severity":"warning"},"annotations":{"summary":"Test alert"}}]}' http://localhost:9093/api/v1/alerts
   ```

2. Check Alertmanager UI: http://localhost:9093

## Adding New Alerts

1. Add new alert rules to `prometheus/alert.rules`
2. Update routing in `alertmanager.yml` if needed
3. Reload Prometheus configuration:
   ```bash
   curl -X POST http://localhost:9090/-/reload
   ```

## Monitoring

Alertmanager metrics are available at `http://localhost:9093/metrics`
