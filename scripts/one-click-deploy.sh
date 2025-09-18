#!/bin/bash
# One-Click Deployment Script
# Deploys the entire OpenDiscourse platform with Supabase and Next.js

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/logs/one-click-deploy.log"

# Create logs directory
mkdir -p "${SCRIPT_DIR}/logs"

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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
    fi
    
    # Check pnpm
    if ! command -v pnpm &> /dev/null; then
        error "pnpm is not installed. Please install pnpm first."
    fi
    
    log "All prerequisites are installed"
}

# Deploy Supabase
deploy_supabase() {
    log "Deploying Supabase..."
    
    # Generate Supabase .env file if it doesn't exist
    if [ ! -f "${SCRIPT_DIR}/supabase-docker/.env" ]; then
        log "Generating Supabase .env file..."
        python3 "${SCRIPT_DIR}/scripts/generate_supabase_env.py" --output "${SCRIPT_DIR}/supabase-docker/.env" --force
    fi
    
    # Start Supabase services
    log "Starting Supabase services..."
    cd "${SCRIPT_DIR}/supabase-docker"
    docker-compose pull
    docker-compose up -d
    
    # Wait for services to be ready
    log "Waiting for Supabase services to be ready..."
    sleep 30
    
    log "Supabase deployed successfully"
}

# Setup Next.js
setup_nextjs() {
    log "Setting up Next.js application..."
    
    # Install dependencies
    log "Installing Next.js dependencies..."
    cd "${SCRIPT_DIR}/nextjs"
    pnpm install
    
    # Create .env.local file
    log "Creating .env.local file..."
    SUPABASE_URL="http://localhost:8000"
    SUPABASE_ANON_KEY=$(grep "ANON_KEY=" ../supabase-docker/.env | cut -d '=' -f2)
    
    cat > .env.local << EOF
NEXT_PUBLIC_SUPABASE_URL=${SUPABASE_URL}
NEXT_PUBLIC_SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
EOF
    
    log "Next.js application setup completed"
}

# Build Next.js application
build_nextjs() {
    log "Building Next.js application..."
    
    cd "${SCRIPT_DIR}/nextjs"
    pnpm run build
    
    log "Next.js application built successfully"
}

# Show deployment status
show_status() {
    log "Deployment status:"
    
    # Check Supabase services
    log "Supabase services:"
    cd "${SCRIPT_DIR}/supabase-docker"
    docker-compose ps
    
    # Show access information
    log "Access information:"
    log "- Supabase Studio: http://localhost:3000"
    log "- Supabase API: http://localhost:8000"
    log "- Next.js Application: http://localhost:3001 (after starting)"
}

# Main function
main() {
    log "Starting one-click deployment of OpenDiscourse platform..."
    
    check_prerequisites
    deploy_supabase
    setup_nextjs
    build_nextjs
    show_status
    
    log "One-click deployment completed successfully!"
    log "To start the Next.js development server, run:"
    log "  cd nextjs && pnpm run dev"
    log "Then access the application at http://localhost:3001"
}

# Run main function
main "$@"