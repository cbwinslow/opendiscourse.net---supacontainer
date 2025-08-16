#!/bin/bash

# Verification script for AI Crews and Monitoring Stack

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${STACK_DIR:-/opt/opendiscourse}"
LOG_FILE="$STACK_DIR/logs/ai_crews_verify_$(date +%Y%m%d_%H%M%S).log"

# Create necessary directories
mkdir -p "$STACK_DIR/logs"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

# Check if a service is running
check_service() {
    local service=$1
    local container_id
    
    container_id=$(docker ps -q -f "name=$service")
    if [ -z "$container_id" ]; then
        warn "Service $service is not running"
        return 1
    else
        log "Service $service is running (Container ID: ${container_id:0:12})"
        return 0
    fi
}

# Check if a URL is accessible
check_url() {
    local url=$1
    local name=$2
    local status_code
    
    status_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || true)
    if [[ "$status_code" =~ ^(200|302|401)$ ]]; then
        log "$name is accessible at $url (Status: $status_code)"
        return 0
    else
        warn "$name is not accessible at $url (Status: ${status_code:-Unknown})"
        return 1
    fi
}

# Check container logs for errors
check_logs() {
    local service=$1
    local container_id
    
    container_id=$(docker ps -q -f "name=$service")
    if [ -z "$container_id" ]; then
        warn "Cannot check logs for $service - container not found"
        return 1
    fi
    
    log "Checking logs for $service (last 10 lines):"
    docker logs --tail=10 "$container_id" 2>&1 | sed 's/^/  /' | tee -a "$LOG_FILE"
    
    # Check for error patterns
    if docker logs "$container_id" 2>&1 | grep -i -E 'error|fail|exception|critical' | grep -v -i 'DEBUG' | head -5; then
        warn "Found potential errors in $service logs"
        return 1
    fi
    
    return 0
}

# Verify monitoring stack
verify_monitoring() {
    log "Verifying monitoring stack..."
    
    # Check if containers are running
    local -a services=(
        "prometheus"
        "grafana"
        "loki"
        "promtail"
        "jaeger"
        "otel-collector"
    )
    
    local all_ok=true
    for service in "${services[@]}"; do
        if ! check_service "$service"; then
            all_ok=false
        fi
    done
    
    # Check if web UIs are accessible
    check_url "http://localhost:3000" "Grafana"
    check_url "http://localhost:9090" "Prometheus"
    check_url "http://localhost:3100" "Loki"
    check_url "http://localhost:16686" "Jaeger"
    
    # Check logs for errors
    for service in "${services[@]}"; do
        if ! check_logs "$service"; then
            all_ok=false
        fi
    done
    
    if $all_ok; then
        log "Monitoring stack verification completed successfully"
    else
        warn "Monitoring stack verification completed with warnings or errors"
    fi
}

# Verify AI crews
verify_ai_crews() {
    log "Verifying AI crews..."
    
    # Check if containers are running
    local -a services=(
        "ai-orchestrator"
        "ai-security"
        "ai-monitoring"
        "ai-deployment"
        "redis"
        "postgres"
    )
    
    local all_ok=true
    for service in "${services[@]}"; do
        if ! check_service "$service"; then
            all_ok=false
        fi
    done
    
    # Check logs for errors
    for service in "${services[@]}"; do
        if ! check_logs "$service"; then
            all_ok=false
        fi
    done
    
    # Check API endpoints
    check_url "http://localhost:8000/health" "AI Orchestrator API"
    
    if $all_ok; then
        log "AI crews verification completed successfully"
    else
        warn "AI crews verification completed with warnings or errors"
    fi
}

# Main function
main() {
    log "Starting verification of AI Crews and Monitoring Stack..."
    
    verify_monitoring
    verify_ai_crews
    
    log "\nVerification completed!"
    log "Access monitoring tools at:"
    log "- Grafana: http://localhost:3000 (admin/admin)"
    log "- Prometheus: http://localhost:9090"
    log "- Jaeger UI: http://localhost:16686"
    log "- Loki: http://localhost:3100"
    log "- AI Orchestrator: http://localhost:8000"
    log "\nLog file: $LOG_FILE"
}

# Run main function
main "$@"
