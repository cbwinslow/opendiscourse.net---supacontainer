#!/bin/bash

# Deployment script for OpenDiscourse Automation Services
# This script deploys and manages the automation stack

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="/opt/opendiscourse"
LOG_FILE="$STACK_DIR/automation_deploy_$(date +%Y%m%d_%H%M%S).log"

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

# Setup directories
setup_directories() {
    log "Setting up directory structure..."
    mkdir -p "$STACK_DIR/backups"
    mkdir -p "$STACK_DIR/automation"
    log "Directory structure ready"
}

# Deploy automation services
deploy_services() {
    log "Deploying automation services..."
    
    # Copy compose file if it doesn't exist
    if [ ! -f "$STACK_DIR/automation/docker-compose.automation.yml" ]; then
        cp "$SCRIPT_DIR/docker-compose.automation.yml" "$STACK_DIR/automation/"
    fi
    
    # Deploy services
    cd "$STACK_DIR" || error "Failed to change to $STACK_DIR"
    
    log "Starting automation services..."
    docker-compose -f docker-compose.yml -f automation/docker-compose.automation.yml up -d
    
    log "Automation services deployed successfully!"
}

# Verify services
verify_services() {
    log "Verifying services..."
    local services=("n8n" "backup")
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
        log "All automation services are running successfully!"
    else
        error "Some services failed to start. Check the logs with: docker-compose logs"
    fi
}

# Main function
main() {
    log "Starting OpenDiscourse Automation deployment..."
    
    check_root
    setup_directories
    deploy_services
    sleep 10  # Give services time to start
    verify_services
    
    log "Deployment completed successfully!"
    log "n8n is available at: https://n8n.opendiscourse.net"
    log "Backup service is configured with 7-day retention"
    log "Log file: $LOG_FILE"
}

# Run main function
main "$@"
