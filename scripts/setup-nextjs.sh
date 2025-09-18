#!/bin/bash
# Next.js Setup Script
# Sets up the Next.js application with Supabase integration

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEXTJS_DIR="${SCRIPT_DIR}/nextjs"
LOG_FILE="${SCRIPT_DIR}/logs/nextjs-setup.log"

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

# Check if pnpm is installed
check_pnpm() {
    if ! command -v pnpm &> /dev/null; then
        error "pnpm is not installed. Please install pnpm first."
    fi
    
    log "pnpm is installed"
}

# Check if Next.js directory exists
check_nextjs_dir() {
    if [ ! -d "${NEXTJS_DIR}" ]; then
        error "Next.js directory not found at ${NEXTJS_DIR}"
    fi
    
    log "Next.js directory found"
}

# Install dependencies
install_dependencies() {
    log "Installing dependencies..."
    
    cd "${NEXTJS_DIR}"
    pnpm install
    
    log "Dependencies installed successfully"
}

# Create .env.local file
create_env_file() {
    log "Creating .env.local file..."
    
    cd "${NEXTJS_DIR}"
    
    # Get Supabase URL and anon key from the Supabase .env file
    if [ -f "../supabase-docker/.env" ]; then
        SUPABASE_URL="http://localhost:8000"
        SUPABASE_ANON_KEY=$(grep "ANON_KEY=" ../supabase-docker/.env | cut -d '=' -f2)
        
        cat > .env.local << EOF
NEXT_PUBLIC_SUPABASE_URL=${SUPABASE_URL}
NEXT_PUBLIC_SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
EOF
        
        log ".env.local file created with Supabase configuration"
    else
        warn "Supabase .env file not found. Creating .env.local with placeholder values."
        cat > .env.local << EOF
NEXT_PUBLIC_SUPABASE_URL=http://localhost:8000
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key-here
EOF
    fi
}

# Build the application
build_app() {
    log "Building the Next.js application..."
    
    cd "${NEXTJS_DIR}"
    pnpm run build
    
    log "Next.js application built successfully"
}

# Start development server
start_dev() {
    log "Starting Next.js development server..."
    
    cd "${NEXTJS_DIR}"
    pnpm run dev
}

# Main function
main() {
    case "${1:-setup}" in
        setup)
            check_pnpm
            check_nextjs_dir
            install_dependencies
            create_env_file
            log "Next.js setup completed successfully!"
            log "Run 'pnpm run dev' in the nextjs directory to start the development server"
            ;;
        build)
            check_pnpm
            check_nextjs_dir
            build_app
            ;;
        dev)
            check_pnpm
            check_nextjs_dir
            start_dev
            ;;
        help|--help|-h)
            echo "Next.js Setup Script"
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  setup     Set up the Next.js application (install dependencies, create .env.local)"
            echo "  build     Build the Next.js application"
            echo "  dev       Start the development server"
            echo "  help      Show this help message"
            echo ""
            echo "If no command is provided, 'setup' will be used."
            ;;
        *)
            error "Unknown command: $1"
            ;;
    esac
}

# Run main function
main "$@"