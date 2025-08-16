#!/bin/bash

# Deployment script for OpenDiscourse Monitoring Stack

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${STACK_DIR:-/opt/opendiscourse}"
LOG_FILE="$STACK_DIR/logs/monitoring_deploy_$(date +%Y%m%d_%H%M%S).log"

# Create necessary directories
mkdir -p "$STACK_DIR/logs"
mkdir -p "$STACK_DIR/monitoring/prometheus"
mkdir -p "$STACK_DIR/monitoring/grafana/provisioning/datasources"
mkdir -p "$STACK_DIR/monitoring/grafana/provisioning/dashboards"

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

# Deploy monitoring stack
deploy_monitoring() {
    log "Deploying monitoring stack..."
    
    cd "$SCRIPT_DIR/opentelemetry" || error "Failed to change to OpenTelemetry directory"
    
    # Copy configurations
    cp -r "$SCRIPT_DIR/opentelemetry/promtail" "$STACK_DIR/monitoring/"
    
    # Start the stack
    log "Starting monitoring services..."
    docker-compose -f docker-compose.otel.yml up -d
    
    # Wait for services to be ready
    log "Waiting for services to be ready..."
    sleep 10
    
    log "Monitoring stack deployed successfully!"
}

# Configure Grafana
configure_grafana() {
    log "Configuring Grafana..."
    
    # Wait for Grafana to be ready
    until curl -s http://localhost:3000/api/health >/dev/null; do
        sleep 5
    done
    
    # Configure data sources
    cat > "$STACK_DIR/monitoring/grafana/provisioning/datasources/datasources.yml" << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    version: 1
    editable: true
  
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    version: 1
    editable: true
    
  - name: Jaeger
    type: jaeger
    access: proxy
    url: http://jaeger:16686
    version: 1
    editable: true
EOF
    
    log "Grafana configuration updated. Access at http://localhost:3000"
    log "Default credentials: admin/admin"
}

# Main function
main() {
    log "Starting monitoring stack deployment..."
    
    check_root
    deploy_monitoring
    configure_grafana
    
    log "Monitoring stack deployment completed!"
    log "Access monitoring tools at:"
    log "- Grafana: http://localhost:3000"
    log "- Prometheus: http://localhost:9090"
    log "- Jaeger UI: http://localhost:16686"
    log "- Loki: http://localhost:3100"
    log "Log file: $LOG_FILE"
}

# Run main function
main "$@"
