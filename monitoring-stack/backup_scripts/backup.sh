#!/bin/bash

# Exit on error
set -e

# Load environment variables
source .env

# Timestamp for backup files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/monitoring-${TIMESTAMP}"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Function to backup Docker volumes
backup_volume() {
    local volume_name=$1
    local backup_file="${BACKUP_DIR}/${volume_name}.tar.gz"
    
    echo "Backing up volume ${volume_name}..."
    docker run --rm -v "${volume_name}:/volume" -v "${BACKUP_DIR}:/backup" alpine \
        tar -czf "/backup/$(basename "${backup_file}")" -C /volume ./
    
    echo "Backup created at ${backup_file}"
}

# Backup Prometheus data
backup_volume "${COMPOSE_PROJECT_NAME:-monitoring}_prometheus_data"

# Backup Grafana data
backup_volume "${COMPOSE_PROJECT_NAME:-monitoring}_grafana_data"

# Backup Loki data
backup_volume "${COMPOSE_PROJECT_NAME:-monitoring}_loki_data"

# Backup OpenSearch data
backup_volume "${COMPOSE_PROJECT_NAME:-monitoring}_opensearch_data"

# Backup RabbitMQ data
backup_volume "${COMPOSE_PROJECT_NAME:-monitoring}_rabbitmq_data"

# Create a single archive of all backups
echo "Creating final backup archive..."
tar -czf "/backups/monitoring-backup-${TIMESTAMP}.tar.gz" -C "${BACKUP_DIR%/*}" "$(basename "${BACKUP_DIR}")"

# Clean up
rm -rf "${BACKUP_DIR}"

echo "Backup completed successfully: /backups/monitoring-backup-${TIMESTAMP}.tar.gz"
