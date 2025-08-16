#!/bin/bash

# Deployment script for OpenDiscourse domain configuration
# This script applies the domain configuration changes and restarts services

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
STACK_DIR="/opt/opendiscourse"
LOG_FILE="$STACK_DIR/domain_config_$(date +%Y%m%d_%H%M%S).log"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root"
    fi
}

# Create directory structure if it doesn't exist
setup_directories() {
    log "Setting up directory structure..."
    mkdir -p "$STACK_DIR/backups"
    mkdir -p "$STACK_DIR/automation"
    log "Directory structure ready"
}

# Backup current configuration
backup_config() {
    log "Creating backup of current configuration..."
    local backup_dir="$STACK_DIR/backups/config_$(date +%Y%m%d_%H%M%S)"
    
    mkdir -p "$backup_dir"
    
    # Only copy files that exist
    if [ -f "$STACK_DIR/docker-compose.yml" ]; then
        cp -r "$STACK_DIR/docker-compose.yml" "$backup_dir/"
    fi
    
    if [ -f "$STACK_DIR/automation/docker-compose.automation.yml" ]; then
        mkdir -p "$backup_dir/automation"
        cp "$STACK_DIR/automation/docker-compose.automation.yml" "$backup_dir/automation/"
    fi
    
    log "Backup created at: $backup_dir"
}

# Apply domain configuration
apply_domain_config() {
    log "Applying domain configuration..."
    
    # Ensure automation directory exists
    mkdir -p "$STACK_DIR/automation"
    
    # Copy automation compose file if it doesn't exist
    if [ ! -f "$STACK_DIR/automation/docker-compose.automation.yml" ]; then
        cp "$(dirname "$0")/docker-compose.automation.yml" "$STACK_DIR/automation/"
    fi
    
    log "Domain configuration applied successfully"
}

# Restart services
restart_services() {
    log "Restarting services with new configuration..."
    
    cd "$STACK_DIR" || error "Failed to change to $STACK_DIR"
    
    # Include automation services if available
    local compose_files="-f docker-compose.yml"
    if [ -f "automation/docker-compose.automation.yml" ]; then
        compose_files="$compose_files -f automation/docker-compose.automation.yml"
    fi
    
    # Pull latest images and restart
    docker-compose $compose_files pull
    docker-compose $compose_files up -d --build
    
    log "Services restarted successfully"
}

# Verify services
verify_services() {
    log "Verifying services..."
    
    local services=("traefik" "n8n")
    local all_ok=true
    
    for service in "${services[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            log "✅ $service is running"
        else
            log "❌ $service is not running"
            all_ok=false
        fi
    done
    
    if [ "$all_ok" = true ]; then
        log "All services are running successfully!"
    else
        error "Some services failed to start. Check the logs for details."
    fi
}

# Main function
main() {
    log "Starting OpenDiscourse domain configuration..."
    
    check_root
    setup_directories
    backup_config
    apply_domain_config
    
    # Only attempt to restart services if we're in the production environment
    if [ -d "/opt/opendiscourse" ]; then
        restart_services
        sleep 10  # Give services time to start
        verify_services
        
        log "Domain configuration completed successfully!"
        log "n8n is available at: https://n8n.opendiscourse.net"
        log "S3 endpoint: https://s3.opendiscourse.net"
    else
        log "Development environment detected. Services not restarted."
        log "To complete setup in production:"
        log "1. Deploy files to /opt/opendiscourse"
        log "2. Run: sudo $STACK_DIR/automation/deploy_domain_config.sh"
    fi
    
    log "Log file: $LOG_FILE"
}

# Run main function
main "$@"
