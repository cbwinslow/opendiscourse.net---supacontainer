# OpenDiscourse Monitoring Stack Operations Manual

## Table of Contents
1. [Daily Operations](#daily-operations)
2. [Weekly Tasks](#weekly-tasks)
3. [Monthly Maintenance](#monthly-maintenance)
4. [Incident Response](#incident-response)
5. [Capacity Planning](#capacity-planning)
6. [Performance Tuning](#performance-tuning)
7. [Disaster Recovery](#disaster-recovery)
8. [Security Procedures](#security-procedures)
9. [Compliance](#compliance)
10. [Appendix](#appendix)

## Daily Operations

### System Health Check

1. **Verify Service Status**
   ```bash
   # Check all containers are running
   docker ps --format "table {{.Names}}\t{{.Status}}"
   
   # Check resource usage
   docker stats --no-stream
   ```

2. **Review Alerts**
   - Check Prometheus alerts: `http://localhost:9090/alerts`
   - Check Alertmanager: `http://localhost:9093`
   - Review notification channels for any missed alerts

3. **Check Disk Space**
   ```bash
   # Check disk usage
   df -h
   
   # Check container disk usage
   docker system df
   ```

### Log Review

1. **System Logs**
   ```bash
   # View system logs
   journalctl --since "24 hours ago" -u docker
   ```

2. **Container Logs**
   ```bash
   # View logs for all containers
   docker-compose logs --tail=100
   
   # View logs for a specific container
   docker-compose logs -f service_name
   ```

3. **Security Logs**
   ```bash
   # Check authentication logs
   journalctl _TRANSPORT=audit --since "24 hours ago"
   
   # Check failed login attempts
   grep "Failed password" /var/log/auth.log
   ```

## Weekly Tasks

### Backup Verification

1. **Verify Backups**
   ```bash
   # List available backups
   ls -lh /backups/
   
   # Verify backup integrity
   tar -tzf /backups/latest_backup.tar.gz
   ```

2. **Test Restore**
   ```bash
   # Test restore to a temporary location
   mkdir -p /tmp/restore_test
   tar -xzf /backups/latest_backup.tar.gz -C /tmp/restore_test
   ```

### Performance Review

1. **Resource Usage Trends**
   - Review Grafana dashboards for trends
   - Identify any growing resource usage patterns

2. **Query Performance**
   ```bash
   # Check slow Prometheus queries
   docker-compose exec prometheus promtool query stats --host=localhost:9090
   ```

## Monthly Maintenance

### System Updates

1. **Update System Packages**
   ```bash
   sudo apt update
   sudo apt upgrade -y
   sudo apt autoremove -y
   ```

2. **Update Container Images**
   ```bash
   # Pull latest images
   docker-compose pull
   
   # Restart services with new images
   docker-compose up -d
   ```

### Security Audit

1. **Vulnerability Scanning**
   ```bash
   # Scan container images
   docker scan $(docker-compose config --images)
   ```

2. **Review User Access**
   - Review Grafana users and permissions
   - Remove inactive users
   - Rotate API keys

## Incident Response

### Incident Classification

| Severity | Response Time | Example |
|----------|---------------|---------|
| Critical | 15 minutes | Complete system outage |
| High     | 1 hour     | Degraded performance   |
| Medium   | 4 hours    | Non-critical service down |
| Low      | 24 hours   | Minor issues, workarounds available |

### Response Procedures

1. **Identification**
   - Acknowledge the alert
   - Gather initial information
   - Classify the incident

2. **Containment**
   - Implement workarounds if available
   - Isolate affected systems
   - Document all actions taken

3. **Eradication**
   - Identify root cause
   - Apply fixes
   - Test solutions

4. **Recovery**
   - Restore services
   - Verify functionality
   - Monitor for recurrence

5. **Post-Mortem**
   - Document the incident
   - Identify lessons learned
   - Update runbooks and procedures

## Capacity Planning

### Resource Monitoring

1. **Metrics to Watch**
   - CPU usage > 80% for extended periods
   - Memory usage > 85%
   - Disk space < 20% free
   - Network bandwidth > 70% utilization

2. **Planning for Growth**
   - Monitor 30-day growth trends
   - Plan upgrades when resources reach 60% capacity
   - Document upgrade procedures

## Performance Tuning

### Prometheus Optimization

1. **Storage**
   ```yaml
   # prometheus.yml
   storage:
     tsdb:
       retention: 30d
       chunk_encoding: double-delta
   ```

2. **Query Performance**
   - Create recording rules for frequent queries
   - Use rate() and increase() appropriately
   - Limit query time ranges

### OpenSearch Tuning

1. **JVM Heap**
   ```yaml
   # jvm.options
   -Xms4g
   -Xmx4g
   ```

2. **Index Management**
   ```bash
   # Force merge segments
   curl -X POST "localhost:9200/_forcemerge?only_expunge_deletes=true"
   ```

## Disaster Recovery

### Recovery Procedures

1. **Full System Recovery**
   ```bash
   # Restore from backup
   ./backup_scripts/restore.sh /backups/latest_backup.tar.gz
   
   # Start services
   docker-compose up -d
   ```

2. **Partial Recovery**
   - Restore specific volumes from backup
   - Rebuild individual services

### Recovery Time Objectives (RTO)

| Component | RTO      | RPO      |
|-----------|----------|----------|
| Grafana   | 15 min   | 5 min    |
| Prometheus| 30 min   | 5 min    |
| OpenSearch| 1 hour   | 15 min   |
| RabbitMQ  | 30 min   | 1 min    |

## Security Procedures

### Access Control

1. **User Management**
   - Use least privilege principle
   - Regular access reviews
   - Implement MFA where possible

2. **Network Security**
   - Restrict access to management interfaces
   - Use VPN for remote access
   - Implement network segmentation

### Incident Response

1. **Security Incidents**
   - Document all actions
   - Preserve evidence
   - Follow incident response plan

2. **Forensics**
   - Capture system state
   - Analyze logs
   - Document findings

## Compliance

### Data Retention

| Data Type | Retention Period | Location |
|-----------|------------------|----------|
| Metrics   | 30 days          | Prometheus|
| Logs      | 90 days          | Loki     |
| Backups   | 1 year           | Offsite  |
| Audit Logs| 1 year           | S3       |

### Audit Procedures

1. **Monthly Audit**
   - Review access logs
   - Verify backup integrity
   - Check security controls

2. **Quarterly Review**
   - Update policies
   - Review compliance requirements
   - Train staff

## Appendix

### Useful Commands

```bash
# View running containers
docker ps

# View logs for all services
docker-compose logs -f

# Execute command in container
docker-compose exec service_name command

# View resource usage
docker stats

# Check service health
curl -s http://localhost:9090/-/healthy

# Backup volumes
docker run --rm -v /backup:/backup -v volume_name:/data alpine tar czf /backup/volume_name_$(date +%Y%m%d).tar.gz -C /data .
```

### Common Issues and Resolutions

#### High CPU Usage
1. **Symptom**: Prometheus using excessive CPU
   - **Cause**: Too many active queries
   - **Resolution**: Optimize queries, add recording rules

2. **Symptom**: Container restarts
   - **Cause**: Out of memory
   - **Resolution**: Increase memory limits, optimize application

#### Disk Space Issues
1. **Symptom**: Prometheus storage growing too fast
   - **Resolution**: Adjust retention, compact blocks
   ```bash
   docker-compose exec prometheus prometheus-tsdb cleanup --storage.tsdb.path=/prometheus
   ```

2. **Symptom**: Logs consuming too much space
   - **Resolution**: Adjust log rotation, implement log retention

### Contact Information

| Role | Contact | Availability |
|------|---------|--------------|
| Primary On-Call | oncall@example.com | 24/7 |
| Systems Team | systems@example.com | Business Hours |
| Security Team | security@example.com | 24/7 |

### Change Log

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2023-10-01 | 1.0.0 | Initial version | Team |
| 2023-10-15 | 1.0.1 | Updated backup procedures | Team |

---
Last updated: $(date +"%Y-%m-%d")
