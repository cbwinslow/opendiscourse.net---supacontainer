#!/bin/bash

# Exit on error
set -e

# Check if backup file is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <backup_file.tar.gz>"
    exit 1
fi

BACKUP_FILE="$1"
TEMP_DIR="/tmp/monitoring-restore-$(date +%s)"

# Load environment variables
source .env

# Verify backup file exists
if [ ! -f "${BACKUP_FILE}" ]; then
    echo "Error: Backup file '${BACKUP_FILE}' not found."
    exit 1
fi

# Create temporary directory
echo "Preparing restore environment..."
mkdir -p "${TEMP_DIR}"

# Extract backup
echo "Extracting backup file..."
tar -xzf "${BACKUP_FILE}" -C "${TEMP_DIR}" --strip-components=1

# Function to restore Docker volume
restore_volume() {
    local volume_name=$1
    local backup_file="${TEMP_DIR}/${volume_name}.tar.gz"
    
    if [ ! -f "${backup_file}" ]; then
        echo "Warning: Backup for volume ${volume_name} not found, skipping..."
        return 0
    fi
    
    echo "Restoring volume ${volume_name}..."
    
    # Stop containers using the volume
    CONTAINERS=$(docker ps -q --filter volume="${volume_name}")
    if [ -n "$CONTAINERS" ]; then
        echo "Stopping containers using ${volume_name}..."
        docker stop $CONTAINERS
    fi
    
    # Restore volume
    docker run --rm -v "${volume_name}:/volume" -v "${TEMP_DIR}:/backup" alpine \
        sh -c "rm -rf /volume/* && tar -xzf /backup/$(basename "${backup_file}")" -C /volume
    
    # Start containers if they were stopped
    if [ -n "$CONTAINERS" ]; then
        echo "Starting containers..."
        docker start $CONTAINERS
    fi
    
    echo "Restored ${volume_name}"
}

# Restore volumes
restore_volume "${COMPOSE_PROJECT_NAME:-monitoring}_prometheus_data"
restore_volume "${COMPOSE_PROJECT_NAME:-monitoring}_grafana_data"
restore_volume "${COMPOSE_PROJECT_NAME:-monitoring}_loki_data"
restore_volume "${COMPOSE_PROJECT_NAME:-monitoring}_opensearch_data"
restore_volume "${COMPOSE_PROJECT_NAME:-monitoring}_rabbitmq_data"

# Clean up
echo "Cleaning up..."
rm -rf "${TEMP_DIR}"

echo "Restore completed successfully!"
echo "You may need to restart the stack for all services to pick up the restored data."
