#!/bin/bash
set -euo pipefail

# =============================================================================
# OpenDiscourse Deployment Script
# =============================================================================
# This script manages the OpenDiscourse stack deployment

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="/opt/opendiscourse"
LOG_FILE="$STACK_DIR/deploy.log"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

check_env() {
    if [ ! -f "$STACK_DIR/.env" ]; then
        error "Environment file not found at $STACK_DIR/.env. Please run install.sh first."
    fi
    
    # Source the environment file
    set -a
    source "$STACK_DIR/.env"
    set +a
    
    # Verify required variables
    if [ -z "${DOMAIN:-}" ] || [ -z "${POSTGRES_PASSWORD:-}" ]; then
        error "Required environment variables are not set. Please check your .env file."
    fi
}

wait_for_service() {
    local service=$1
    local host=$2
    local port=$3
    local max_attempts=30
    local attempt=0
    
    log "Waiting for $service to be ready..."
    
    until nc -z "$host" "$port" >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        
        if [ $attempt -ge $max_attempts ]; then
            error "$service failed to start after $max_attempts attempts"
        fi
        
        echo -n "."
        sleep 2
    done
    
    echo -e "\n${GREEN}$service is ready!${NC}"
}

start_services() {
    log "Starting OpenDiscourse stack..."
    cd "$STACK_DIR"
    
    # Pull latest images
    log "Pulling latest Docker images..."
    docker-compose pull --quiet
    
    # Start all services
    log "Starting containers..."
    docker-compose up -d --remove-orphans
    
    # Wait for key services to be ready
    wait_for_service "PostgreSQL" "localhost" 5432
    wait_for_service "Weaviate" "localhost" 8081
    wait_for_service "MinIO" "localhost" 9000
    
    log "OpenDiscourse stack started successfully!"
}

stop_services() {
    log "Stopping OpenDiscourse stack..."
    cd "$STACK_DIR"
    docker-compose down
    log "OpenDiscourse stack stopped."
}

restart_services() {
    log "Restarting OpenDiscourse stack..."
    cd "$STACK_DIR"
    docker-compose restart
    log "OpenDiscourse stack restarted."
}

status_services() {
    cd "$STACK_DIR"
    docker-compose ps
}

update_stack() {
    log "Updating OpenDiscourse stack..."
    
    # Pull latest code
    git -C "$SCRIPT_DIR" pull
    
    # Rebuild and restart
    cd "$STACK_DIR"
    docker-compose pull
    docker-compose up -d --build
    
    log "OpenDiscourse stack updated successfully!"
}

backup_stack() {
    local backup_dir="$STACK_DIR/backups/$(date +%Y%m%d_%H%M%S)"
    
    log "Creating backup in $backup_dir..."
    mkdir -p "$backup_dir"
    
    # Backup configuration
    cp -r "$STACK_DIR/.env" "$backup_dir/"
    cp -r "$STACK_DIR/config" "$backup_dir/"
    
    # Backup volumes
    for volume in "postgres" "weaviate" "minio"; do
        log "Backing up $volume volume..."
        docker run --rm -v "${volume}_data:/source" -v "$backup_dir:/backup" \
            alpine tar czf "/backup/${volume}_backup.tar.gz" -C /source .
    done
    
    log "Backup completed successfully!"
}

show_help() {
    echo "OpenDiscourse Deployment Script"
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  start     Start all services"
    echo "  stop      Stop all services"
    echo "  restart   Restart all services"
    echo "  status    Show service status"
    echo "  update    Update to the latest version"
    echo "  backup    Create a backup of all data"
    echo "  help      Show this help message"
    echo ""
    echo "If no command is provided, 'start' will be used."
}

# Main execution
check_env

case "${1:-start}" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    status)
        status_services
        ;;
    update)
        update_stack
        ;;
    backup)
        backup_stack
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac

exit 0
