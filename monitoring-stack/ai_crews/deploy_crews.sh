#!/bin/bash

# Deployment script for AI Crews

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR="${STACK_DIR:-/opt/opendiscourse}"
LOG_FILE="$STACK_DIR/logs/ai_crews_deploy_$(date +%Y%m%d_%H%M%S).log"
CONFIG_FILE="$SCRIPT_DIR/crew_config.yaml"

# Create necessary directories
mkdir -p "$STACK_DIR/logs"
mkdir -p "$STACK_DIR/ai_crews/config"

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

# Validate configuration
validate_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration file not found: $CONFIG_FILE"
    fi
    
    # Validate YAML syntax
    if ! command -v yq &> /dev/null; then
        log "Installing yq for YAML validation..."
        sudo apt-get update && sudo apt-get install -y yq
    fi
    
    if ! yq e '.' "$CONFIG_FILE" > /dev/null; then
        error "Invalid YAML syntax in $CONFIG_FILE"
    fi
}

# Deploy AI crews
deploy_crews() {
    log "Deploying AI crews..."
    
    # Copy configuration
    cp "$CONFIG_FILE" "$STACK_DIR/ai_crews/config/"
    
    # Create Docker Compose file
    cat > "$STACK_DIR/ai_crews/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  # AI Orchestrator
  ai-orchestrator:
    image: ${AI_ORCHESTRATOR_IMAGE:-opendiscourse/ai-orchestrator:latest}
    environment:
      - NODE_ENV=production
      - LOG_LEVEL=info
      - OTEL_SERVICE_NAME=ai-orchestrator
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
      - REDIS_URL=redis://redis:6379/0
      - DATABASE_URL=postgresql://postgres:postgres@postgres:5432/opendiscourse
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
    networks:
      - monitoring
    depends_on:
      - redis
      - postgres
      - otel-collector
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # AI Security Crew
  ai-security:
    image: ${AI_SECURITY_IMAGE:-opendiscourse/ai-security:latest}
    environment:
      - NODE_ENV=production
      - LOG_LEVEL=info
      - OTEL_SERVICE_NAME=ai-security
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
      - REDIS_URL=redis://redis:6379/1
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G
    networks:
      - monitoring
    depends_on:
      - redis
      - otel-collector
    restart: unless-stopped

  # AI Monitoring Crew
  ai-monitoring:
    image: ${AI_MONITORING_IMAGE:-opendiscourse/ai-monitoring:latest}
    environment:
      - NODE_ENV=production
      - LOG_LEVEL=info
      - OTEL_SERVICE_NAME=ai-monitoring
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
      - PROMETHEUS_URL=http://prometheus:9090
      - LOKI_URL=http://loki:3100
    deploy:
      resources:
        limits:
          cpus: '1.5'
          memory: 1.5G
    networks:
      - monitoring
    depends_on:
      - prometheus
      - loki
      - otel-collector
    restart: unless-stopped

  # AI Deployment Crew
  ai-deployment:
    image: ${AI_DEPLOYMENT_IMAGE:-opendiscourse/ai-deployment:latest}
    environment:
      - NODE_ENV=production
      - LOG_LEVEL=info
      - OTEL_SERVICE_NAME=ai-deployment
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
      - DOCKER_HOST=unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G
    networks:
      - monitoring
    depends_on:
      - otel-collector
    restart: unless-stopped

  # Redis
  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - monitoring
    restart: unless-stopped

  # PostgreSQL
  postgres:
    image: postgres:14-alpine
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=opendiscourse
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - monitoring
    restart: unless-stopped

networks:
  monitoring:
    external: true

volumes:
  redis_data:
  postgres_data:
EOF

    # Start the services
    cd "$STACK_DIR/ai_crews" || error "Failed to change to AI crews directory"
    
    log "Starting AI crews..."
    docker-compose pull
    docker-compose up -d
    
    log "Waiting for services to start..."
    sleep 10
    
    # Verify services
    for service in ai-orchestrator ai-security ai-monitoring ai-deployment; do
        if ! docker-compose ps | grep -q "$service.*Up"; then
            error "Service $service failed to start. Check logs with: docker-compose logs $service"
        fi
    done
    
    log "AI crews deployed successfully!"
}

# Main function
main() {
    log "Starting AI crews deployment..."
    
    check_root
    validate_config
    deploy_crews
    
    log "AI crews deployment completed!"
    log "Access AI Orchestrator at: http://localhost:3000"
    log "Log file: $LOG_FILE"
}

# Run main function
main "$@"
