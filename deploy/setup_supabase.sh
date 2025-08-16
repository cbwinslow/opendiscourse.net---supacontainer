#!/bin/bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
STACK_DIR="/opt/opendiscourse"
SUPABASE_DIR="$STACK_DIR/supabase"
LOG_FILE="$STACK_DIR/logs/supabase_setup.log"

# Load environment variables
if [ -f "$STACK_DIR/.env" ]; then
    source "$STACK_DIR/.env"
else
    echo -e "${RED}Error: .env file not found in $STACK_DIR${NC}"
    exit 1
fi

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
        error "This script must be run as root. Use 'sudo -E $0'"
    fi
}

# Install required tools
install_dependencies() {
    log "Installing required dependencies..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        jq \
        curl \
        git \
        nodejs \
        npm \
        postgresql-client
}

# Install Supabase CLI
install_supabase_cli() {
    if ! command -v supabase &> /dev/null; then
        log "Installing Supabase CLI..."
        npm install -g supabase --unsafe-perm=true
    else
        log "Supabase CLI is already installed"
    fi
}

# Initialize Supabase project
init_supabase() {
    log "Initializing Supabase project..."
    mkdir -p "$SUPABASE_DIR"
    cd "$SUPABASE_DIR"
    
    if [ ! -f "docker-compose.yml" ]; then
        # Create a new Supabase project
        supabase init
        
        # Configure environment
        cat > ".env.local" <<EOF
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
JWT_SECRET=${JWT_SECRET}
ANON_KEY=${ANON_KEY:-}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY:-}
SITE_URL=http://localhost:3000
ADDITIONAL_REDIRECT_URLS=
ENABLE_EMAIL_SIGNUP=true
ENABLE_EMAIL_AUTOCONFIRM=true
SMTP_ADMIN_EMAIL=${EMAIL}
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_USER=${SMTP_USER}
SMTP_PASS=${SMTP_PASSWORD}
SMTP_SENDER_NAME="OpenDiscourse"
EOF
        
        log "Supabase project initialized in $SUPABASE_DIR"
    else
        log "Supabase project already exists in $SUPABASE_DIR"
    fi
}

# Update Docker Compose for Supabase
update_docker_compose() {
    log "Updating Docker Compose configuration..."
    cd "$STACK_DIR"
    
    # Create a backup of the existing docker-compose.yml
    if [ -f "docker-compose.yml" ]; then
        cp docker-compose.yml docker-compose.yml.bak
    fi
    
    # Create a new docker-compose.override.yml for Supabase
    cat > "docker-compose.override.yml" <<EOF
version: '3.8'

services:
  supabase:
    image: supabase/gotrue:v2.0.0
    container_name: supabase_auth
    restart: unless-stopped
    environment:
      GOTRUE_DB_DRIVER: postgres
      GOTRUE_DB_DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@db:5432/postgres
      GOTRUE_SITE_URL: https://${DOMAIN}
      GOTRUE_URI_ALLOW_LIST: 
      GOTRUE_DISABLE_SIGNUP: "false"
      GOTRUE_JWT_SECRET: ${JWT_SECRET}
      GOTRUE_JWT_EXP: 3600
      GOTRUE_JWT_DEFAULT_GROUP_NAME: authenticated
      GOTRUE_JWT_ADMIN_GROUP_NAME: service_role
      GOTRUE_JWT_ISSUER: supabase
      GOTRUE_MAILER_AUTOCONFIRM: "true"
      GOTRUE_MAILER_URLPATHS_INVITE: /auth/v1/verify
      GOTRUE_MAILER_URLPATHS_CONFIRMATION: /auth/v1/verify
      GOTRUE_MAILER_URLPATHS_RECOVERY: /auth/v1/verify
      GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE: /auth/v1/verify
      GOTRUE_SMTP_HOST: ${SMTP_HOST}
      GOTRUE_SMTP_PORT: ${SMTP_PORT}
      GOTRUE_SMTP_USER: ${SMTP_USER}
      GOTRUE_SMTP_PASS: ${SMTP_PASSWORD}
      GOTRUE_SMTP_ADMIN_EMAIL: ${EMAIL}
      GOTRUE_SMTP_SENDER_NAME: OpenDiscourse
    networks:
      - opendiscourse_net
    depends_on:
      - db

  supabase-studio:
    image: supabase/studio:latest
    container_name: supabase_studio
    restart: unless-stopped
    environment:
      STUDIO_PG_META_URL: http://meta:8080
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - "3001:3000"
    networks:
      - opendiscourse_net
    depends_on:
      - supabase

  meta:
    image: supabase/postgres-meta:v0.66.0
    container_name: supabase_meta
    restart: unless-stopped
    environment:
      PG_META_PORT: 8080
      PG_META_DB_HOST: db
      PG_META_DB_PASSWORD: ${POSTGRES_PASSWORD}
    networks:
      - opendiscourse_net
    depends_on:
      - db

networks:
  opendiscourse_net:
    external: true
EOF
    
    log "Docker Compose configuration updated"
}

# Initialize Supabase schema
init_supabase_schema() {
    log "Initializing Supabase schema..."
    cd "$SUPABASE_DIR"
    
    # Wait for PostgreSQL to be ready
    until pg_isready -h localhost -p 5432 -U postgres; do
        log "Waiting for PostgreSQL to be ready..."
        sleep 2
    done
    
    # Create initial schema
    psql "postgresql://postgres:${POSTGRES_PASSWORD}@localhost:5432/postgres" -c "
        -- Enable necessary extensions
        CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
        CREATE EXTENSION IF NOT EXISTS "pgcrypto";
        
        -- Create auth schema and tables
        CREATE SCHEMA IF NOT EXISTS auth;
        
        -- Users table
        CREATE TABLE IF NOT EXISTS auth.users (
            id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
            email TEXT UNIQUE NOT NULL,
            encrypted_password TEXT,
            confirmed_at TIMESTAMPTZ,
            confirmation_token TEXT,
            confirmation_sent_at TIMESTAMPTZ,
            recovery_token TEXT,
            recovery_sent_at TIMESTAMPTZ,
            email_change_token_new TEXT,
            email_change TEXT,
            email_change_sent_at TIMESTAMPTZ,
            last_sign_in_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            is_super_admin BOOLEAN DEFAULT FALSE
        );
        
        -- Create a function to update the updated_at column
        CREATE OR REPLACE FUNCTION update_updated_at_column()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.updated_at = NOW();
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        
        -- Create a trigger to update the updated_at column
        DROP TRIGGER IF EXISTS update_auth_users_updated_at ON auth.users;
        CREATE TRIGGER update_auth_users_updated_at
        BEFORE UPDATE ON auth.users
        FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    "
    
    log "Supabase schema initialized"
}

# Start Supabase services
start_supabase() {
    log "Starting Supabase services..."
    cd "$STACK_DIR"
    docker-compose up -d supabase supabase-studio meta
    
    log "Waiting for Supabase to be ready..."
    until curl -s -f http://localhost:3001 >/dev/null 2>&1; do
        sleep 2
    done
    
    log "Supabase is now running at http://localhost:3001"
}

# Configure OpenDiscourse to use Supabase
configure_opendiscourse() {
    log "Configuring OpenDiscourse to use Supabase..."
    cd "$STACK_DIR"
    
    # Update the OpenDiscourse .env file
    cat >> ".env" <<EOF

# Supabase Configuration
NEXT_PUBLIC_SUPABASE_URL=http://supabase:3000
NEXT_PUBLIC_SUPABASE_ANON_KEY=${ANON_KEY}
SUPABASE_SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}

# Authentication
AUTH_ENABLED=true
AUTH_PROVIDER=supabase
AUTH_JWT_SECRET=${JWT_SECRET}
AUTH_JWT_EXPIRES_IN=3600
EOF
    
    log "OpenDiscourse configured to use Supabase for authentication"
}

# Main function
main() {
    check_root
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "Starting Supabase setup for OpenDiscourse..."
    
    install_dependencies
    install_supabase_cli
    init_supabase
    update_docker_compose
    start_supabase
    init_supabase_schema
    configure_opendiscourse
    
    log "${GREEN}Supabase setup completed successfully!${NC}"
    log "\nAccess Supabase Studio at: http://localhost:3001"
    log "Supabase API URL: http://localhost:3000"
    log "\nTo apply changes, restart the stack:"
    log "  cd $STACK_DIR && docker-compose down && docker-compose up -d"
}

# Run main function
main "$@"
