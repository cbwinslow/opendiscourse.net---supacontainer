#!/bin/bash

# Deployment script for AI Crews and Monitoring Stack

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${STACK_DIR:-/opt/opendiscourse}"
LOG_FILE="$STACK_DIR/logs/ai_crews_deploy_$(date +%Y%m%d_%H%M%S).log"

# Create necessary directories
mkdir -p "$STACK_DIR/logs"
mkdir -p "$STACK_DIR/monitoring/grafana/provisioning/dashboards"
mkdir -p "$STACK_DIR/monitoring/prometheus"

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

# Install required packages
install_dependencies() {
    log "Installing required packages..."
    apt-get update
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        jq \
        yq
    
    # Install Docker if not already installed
    if ! command -v docker &> /dev/null; then
        log "Installing Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
        systemctl enable --now docker
    fi

    # Install Docker Compose if not already installed
    if ! command -v docker-compose &> /dev/null; then
        log "Installing Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
}

# Deploy monitoring stack
deploy_monitoring() {
    log "Deploying monitoring stack..."
    cd "$SCRIPT_DIR/monitoring-stack/opentelemetry" || error "Failed to change to OpenTelemetry directory"
    
    # Create Docker network if it doesn't exist
    if ! docker network inspect monitoring &> /dev/null; then
        docker network create monitoring
    fi
    
    # Start the stack
    docker-compose -f docker-compose.otel.yml up -d
    
    # Wait for services to be ready
    log "Waiting for services to start..."
    sleep 10
    
    # Configure Grafana
    configure_grafana
}

# Configure Grafana
configure_grafana() {
    log "Configuring Grafana..."
    
    # Wait for Grafana to be ready
    until curl -s http://localhost:3000/api/health >/dev/null; do
        sleep 5
    done
    
    # Set up data sources
    curl -X POST http://admin:admin@localhost:3000/api/datasources \
        -H "Content-Type: application/json" \
        -d '{"name":"Prometheus","type":"prometheus","url":"http://prometheus:9090","access":"proxy","isDefault":true}'
    
    curl -X POST http://admin:admin@localhost:3000/api/datasources \
        -H "Content-Type: application/json" \
        -d '{"name":"Loki","type":"loki","url":"http://loki:3100","access":"proxy"}'
    
    # Import dashboards
    for dashboard in "$SCRIPT_DIR/monitoring-stack/grafana/provisioning/dashboards/"*.json; do
        if [ -f "$dashboard" ]; then
            log "Importing dashboard: $(basename "$dashboard")"
            jq '. * {overwrite: true, dashboard: {id: null}}' "$dashboard" | \
                curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
                -H "Content-Type: application/json" \
                -d @-
        fi
    done
}

# Deploy AI crews
deploy_ai_crews() {
    log "Deploying AI crews..."
    cd "$SCRIPT_DIR/monitoring-stack/ai_crews" || error "Failed to change to AI crews directory"
    
    # Start the services
    docker-compose up -d
    
    # Wait for services to be ready
    log "Waiting for AI crews to start..."
    sleep 10
    
    # Verify services
    for service in ai-orchestrator ai-security ai-monitoring ai-deployment; do
        if ! docker-compose ps | grep -q "$service.*Up"; then
            error "Service $service failed to start. Check logs with: docker-compose logs $service"
        fi
    done
}

# Main function
main() {
    log "Starting AI Crews and Monitoring deployment..."
    
    check_root
    install_dependencies
    deploy_monitoring
    deploy_ai_crews
    
    log "\nDeployment completed successfully!"
    log "Access monitoring tools at:"
    log "- Grafana: http://localhost:3000 (admin/admin)"
    log "- Prometheus: http://localhost:9090"
    log "- Jaeger UI: http://localhost:16686"
    log "- Loki: http://localhost:3100"
    log "\nLog file: $LOG_FILE"
}

# Run main function
main "$@"
