#!/bin/bash
"""
Supabase Docker Deployment Script for OpenDiscourse
"""

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SUPABASE_DIR="${PROJECT_ROOT}/supabase-docker"
LOG_FILE="${PROJECT_ROOT}/logs/supabase-deploy.log"

# Create logs directory
mkdir -p "${PROJECT_ROOT}/logs"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "${LOG_FILE}"
    exit 1
}

# Check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
    fi
    
    log "Docker and Docker Compose are installed"
}

# Check if Supabase directory exists
check_supabase_dir() {
    if [ ! -d "${SUPABASE_DIR}" ]; then
        error "Supabase directory not found at ${SUPABASE_DIR}"
    fi
    
    if [ ! -f "${SUPABASE_DIR}/.env" ]; then
        error "Supabase .env file not found. Please generate it first."
    fi
    
    if [ ! -f "${SUPABASE_DIR}/docker-compose.yml" ]; then
        error "Supabase docker-compose.yml file not found."
    fi
    
    log "Supabase directory and configuration files found"
}

# Generate .env file if it doesn't exist
generate_env_if_missing() {
    if [ ! -f "${SUPABASE_DIR}/.env" ]; then
        log "Generating Supabase .env file..."
        python3 "${PROJECT_ROOT}/scripts/generate_supabase_env.py" --output "${SUPABASE_DIR}/.env" --force
    fi
}

# Start Supabase services
start_supabase() {
    log "Starting Supabase services..."
    
    cd "${SUPABASE_DIR}"
    
    # Pull latest images
    log "Pulling latest Docker images..."
    docker-compose pull
    
    # Start services
    log "Starting containers..."
    docker-compose up -d
    
    log "Supabase services started successfully!"
    log "Access Supabase Studio at http://localhost:3000"
    log "API endpoint: http://localhost:8000"
}

# Stop Supabase services
stop_supabase() {
    log "Stopping Supabase services..."
    
    cd "${SUPABASE_DIR}"
    docker-compose down
    
    log "Supabase services stopped"
}

# Restart Supabase services
restart_supabase() {
    log "Restarting Supabase services..."
    
    cd "${SUPABASE_DIR}"
    docker-compose restart
    
    log "Supabase services restarted"
}

# Show Supabase service status
status_supabase() {
    cd "${SUPABASE_DIR}"
    docker-compose ps
}

# Show Supabase logs
logs_supabase() {
    cd "${SUPABASE_DIR}"
    docker-compose logs -f
}

# Wait for Supabase services to be ready
wait_for_supabase_ready() {
    log "Waiting for Supabase services to be ready..."
    
    # Wait for key services
    local services=("db" "kong" "auth" "rest" "realtime" "storage" "studio")
    
    for service in "${services[@]}"; do
        log "Waiting for $service to be healthy..."
        local timeout=300  # 5 minutes timeout
        local count=0
        
        while [ $count -lt $timeout ]; do
            if docker-compose ps | grep "$service" | grep "Up" > /dev/null; then
                log "$service is up"
                break
            fi
            
            sleep 1
            ((count++))
            
            if [ $count -eq $timeout ]; then
                error "$service failed to start within $timeout seconds"
            fi
        done
    done
    
    log "All Supabase services are ready!"
}

# Health check Supabase services
health_check_supabase() {
    log "Performing health checks on Supabase services..."
    
    # Check Studio health
    if curl -s -f http://localhost:3000/api/profile > /dev/null; then
        log "Studio health check: OK"
    else
        warn "Studio health check: FAILED"
    fi
    
    # Check Auth health
    if curl -s -f http://localhost:8000/auth/v1/health > /dev/null; then
        log "Auth health check: OK"
    else
        warn "Auth health check: FAILED"
    fi
    
    # Check REST health
    if curl -s -f http://localhost:8000/rest/v1/ > /dev/null; then
        log "REST health check: OK"
    else
        warn "REST health check: FAILED"
    fi
    
    # Check Storage health
    if curl -s -f http://localhost:8000/storage/v1/status > /dev/null; then
        log "Storage health check: OK"
    else
        warn "Storage health check: FAILED"
    fi
    
    log "Health checks completed"
}

# Main function
main() {
    case "${1:-start}" in
        start)
            check_docker
            check_supabase_dir
            generate_env_if_missing
            start_supabase
            wait_for_supabase_ready
            health_check_supabase
            ;;
        stop)
            check_docker
            check_supabase_dir
            stop_supabase
            ;;
        restart)
            check_docker
            check_supabase_dir
            restart_supabase
            wait_for_supabase_ready
            health_check_supabase
            ;;
        status)
            check_docker
            check_supabase_dir
            status_supabase
            ;;
        logs)
            check_docker
            check_supabase_dir
            logs_supabase
            ;;
        wait)
            check_docker
            check_supabase_dir
            wait_for_supabase_ready
            ;;
        health)
            check_docker
            check_supabase_dir
            health_check_supabase
            ;;
        help|--help|-h)
            echo "Supabase Deployment Script"
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  start     Start Supabase services"
            echo "  stop      Stop Supabase services"
            echo "  restart   Restart Supabase services"
            echo "  status    Show service status"
            echo "  logs      Show service logs"
            echo "  wait      Wait for services to be ready"
            echo "  health    Perform health checks"
            echo "  help      Show this help message"
            echo ""
            echo "If no command is provided, 'start' will be used."
            ;;
        *)
            error "Unknown command: $1"
            ;;
    esac
}

# Run main function
main "$@"