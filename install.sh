#!/bin/bash
set -euo pipefail

# =============================================================================
# OpenDiscourse Installation Script
# =============================================================================
# This script installs and configures the complete OpenDiscourse stack including:
# - Core Services: Supabase, Neo4j, Weaviate, MinIO
# - AI Services: LocalAI, OpenWebUI, Flowise
# - Monitoring: Prometheus, Grafana, cAdvisor
# - Automation: n8n, SearxNG
# - Custom Services: RAG API, GraphRAG API, PDF Worker

# =============================================================================
# Configuration
# =============================================================================
STACK_DIR="/opt/opendiscourse"
LOG_FILE="$STACK_DIR/install.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root. Use 'sudo -E $0'"
    fi
}

check_dependencies() {
    local deps=("docker" "docker-compose" "git" "curl" "jq" "openssl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "Missing required dependency: $dep"
        fi
    done
}

# =============================================================================
# Installation Functions
# =============================================================================

install_dependencies() {
    log "Installing system dependencies..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common \
        jq \
        unzip \
        git \
        python3-pip \
        python3-venv \
        build-essential \
        libssl-dev \
        libffi-dev \
        python3-dev \
        python3-setuptools \
        python3-wheel
}

install_docker() {
    if ! command -v docker &> /dev/null; then
        log "Installing Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
        systemctl enable --now docker
    fi
}

setup_directories() {
    log "Setting up directory structure..."
    mkdir -p "$STACK_DIR/{
        data/{postgres,neo4j,weaviate,minio,prometheus,grafana},
        config/{traefik,supabase,localai,n8n,flowise},
        scripts,
        backups,
        logs
    }"
    chmod -R 750 "$STACK_DIR"
    chown -R $SUDO_USER:$SUDO_USER "$STACK_DIR"
}

setup_environment() {
    log "Configuring environment..."
    local env_file="$STACK_DIR/.env"
    
    if [ ! -f "$env_file" ]; then
        # Generate secure secrets
        local jwt_secret=$(openssl rand -hex 32)
        local anon_key=$(openssl rand -hex 32)
        local service_key=$(openssl rand -hex 32)
        local postgres_pass=$(openssl rand -hex 32)
        local minio_access=$(openssl rand -hex 16)
        local minio_secret=$(openssl rand -hex 32)
        
        cat > "$env_file" <<EOF
# =============================================================================
# OpenDiscourse Configuration
# =============================================================================

# Core Configuration
DOMAIN=yourdomain.com
EMAIL=admin@yourdomain.com
STACK_DIR=$STACK_DIR

# Supabase
POSTGRES_PASSWORD=$postgres_pass
JWT_SECRET=$jwt_secret
ANON_KEY=$anon_key
SERVICE_ROLE_KEY=$service_key

# MinIO
MINIO_ROOT_USER=$minio_access
MINIO_ROOT_PASSWORD=$minio_secret
MINIO_BUCKET_NAME=opendiscourse

# Traefik
TRAEFIK_HTTP_PORT=80
TRAEFIK_HTTPS_PORT=443

# Neo4j
NEO4J_AUTH=neo4j/$(openssl rand -hex 16)

# LocalAI
LOCALAI_API_KEY=$(openssl rand -hex 32)

# n8n
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)

# Flowise
FLOWISE_SECRET_KEY=$(openssl rand -hex 32)

# Monitoring
GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 16)

# Backups
BACKUP_RETENTION_DAYS=30
EOF
    fi
    
    # Source the environment file
    set -a
    source "$env_file"
    set +a
    
    log "Environment configured. Please review $env_file and update with your settings."
}

setup_core_services() {
    log "Setting up core services..."
    
    # Create docker-compose file for core services
    cat > "$STACK_DIR/docker-compose.yml" << 'EOL'
version: '3.8'

# Networks
networks:
  opendiscourse_net:
    driver: bridge

# Volumes
volumes:
  postgres_data:
  weaviate_data:
  neo4j_data:
  neo4j_plugins:
  minio_data:
  prometheus_data:
  grafana_data:
  n8n_data:
  flowise_data:

services:
  # Traefik Reverse Proxy
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - opendiscourse_net
    ports:
      - "${TRAEFIK_HTTP_PORT:-80}:80"
      - "${TRAEFIK_HTTPS_PORT:-443}:443"
      - "8080:8080"  # Dashboard
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./config/traefik:/etc/traefik
      - ./data/certificates:/certificates
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.le.acme.email=${EMAIL}"
      - "--certificatesresolvers.le.acme.storage=/certificates/acme.json"
      - "--certificatesresolvers.le.acme.tlschallenge=true"
      - "--api.dashboard=true"
      - "--log.level=INFO"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN}`)"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.tls.certresolver=le"
      - "traefik.http.routers.traefik.middlewares=auth"
      - "traefik.http.middlewares.auth.basicauth.users=${TRAEFIK_AUTH}"

  # Supabase Stack
  supabase-db:
    image: supabase/postgres:15.1.0.76
    container_name: supabase-db
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - opendiscourse_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  supabase-studio:
    image: supabase/studio:latest
    container_name: supabase-studio
    restart: unless-stopped
    environment:
      STUDIO_PG_META_URL: http://meta:8080
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    depends_on:
      - supabase-db
    networks:
      - opendiscourse_net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.supabase-studio.rule=Host(`supabase.${DOMAIN}`)"
      - "traefik.http.routers.supabase-studio.entrypoints=websecure"
      - "traefik.http.routers.supabase-studio.tls.certresolver=le"

  supabase-auth:
    image: supabase/gotrue:v2.168.0
    container_name: supabase-auth
    restart: unless-stopped
    environment:
      GOTRUE_DB_DRIVER: postgres
      GOTRUE_DB_DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@supabase-db:5432/postgres?sslmode=disable
      GOTRUE_SITE_URL: https://${DOMAIN}
      GOTRUE_URI_ALLOW_LIST: *
      GOTRUE_DISABLE_SIGNUP: "false"
      GOTRUE_JWT_SECRET: ${JWT_SECRET}
      GOTRUE_JWT_EXP: 3600
      GOTRUE_JWT_DEFAULT_GROUP_NAME: ""
      GOTRUE_JWT_ADMIN_GROUP_NAME: ""
      GOTRUE_JWT_ISSUER: "supabase"
      GOTRUE_DB_MAX_RETRIES: 10
    depends_on:
      - supabase-db
    networks:
      - opendiscourse_net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.supabase-auth.rule=Host(`auth.${DOMAIN}`)"
      - "traefik.http.routers.supabase-auth.entrypoints=websecure"
      - "traefik.http.routers.supabase-auth.tls.certresolver=le"

  # Weaviate Vector Database
  weaviate:
    image: semitechnologies/weaviate:1.19.0
    container_name: weaviate
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      QUERY_DEFAULTS_LIMIT: 25
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'true'
      DEFAULT_VECTORIZER_MODULE: 'none'
      CLUSTER_HOSTNAME: 'node1'
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
    volumes:
      - weaviate_data:/var/lib/weaviate
    ports:
      - "8081:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/v1/.well-known/ready"]
      interval: 30s
      timeout: 10s
      retries: 3

  # MinIO Object Storage
  minio:
    image: minio/minio:RELEASE.2023-03-20T20-16-18Z
    container_name: minio
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    command: server /data --console-address ":9001"
    volumes:
      - minio_data:/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.minio.rule=Host(`minio.${DOMAIN}`)"
      - "traefik.http.routers.minio.entrypoints=websecure"
      - "traefik.http.routers.minio.tls.certresolver=le"

  # Neo4j Graph Database
  neo4j:
    image: neo4j:5.23
    container_name: neo4j
    restart: unless-stopped
    environment:
      NEO4J_AUTH: "neo4j/${NEO4J_PASSWORD}"
      NEO4J_PLUGINS: '["apoc","graph-data-science"]'
      NEO4J_dbms_memory_pagecache_size: 1G
      NEO4J_dbms_memory_heap_initial__size: 1G
      NEO4J_dbms_memory_heap_max__size: 2G
    volumes:
      - neo4j_data:/data
      - neo4j_plugins:/plugins
    networks:
      - opendiscourse_net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.neo4j.rule=Host(`neo4j.${DOMAIN}`)"
      - "traefik.http.routers.neo4j.entrypoints=websecure"
      - "traefik.http.routers.neo4j.tls.certresolver=le"

  # RAG API
  rag-api:
    build:
      context: ./services/rag-api
    container_name: rag-api
    restart: unless-stopped
    environment:
      DOMAIN: "${DOMAIN}"
      REQUIRE_AUTH: "true"
      SUPABASE_JWKS_URL: "https://${DOMAIN}/auth/v1/jwks"
      WEAVIATE_URL: "http://weaviate:8080"
      WEAVIATE_CLASS: "Document"
      OPENAI_API_KEY: "${OPENAI_API_KEY:-localai}"
      OPENAI_API_BASE_URL: "${OPENAI_API_BASE_URL:-http://localai:8080}"
    depends_on:
      - weaviate
    networks:
      - opendiscourse_net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.rag-api.rule=Host(`api.${DOMAIN}`)"
      - "traefik.http.routers.rag-api.entrypoints=websecure"
      - "traefik.http.routers.rag-api.tls.certresolver=le"

  # GraphRAG API
  graphrag-api:
    build:
      context: ./services/graphrag-api
    container_name: graphrag-api
    restart: unless-stopped
    environment:
      REQUIRE_AUTH: "true"
      SUPABASE_JWKS_URL: "https://${DOMAIN}/auth/v1/jwks"
      NEO4J_URI: "bolt://neo4j:7687"
      NEO4J_USER: "neo4j"
      NEO4J_PASSWORD: "${NEO4J_PASSWORD}"
      OPENAI_API_BASE_URL: "${OPENAI_API_BASE_URL:-http://localai:8080}"
      OPENAI_API_KEY: "${OPENAI_API_KEY:-localai}"
    depends_on:
      - neo4j
    networks:
      - opendiscourse_net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.graphrag-api.rule=Host(`graph-api.${DOMAIN}`)"
      - "traefik.http.routers.graphrag-api.entrypoints=websecure"
      - "traefik.http.routers.graphrag-api.tls.certresolver=le"

  # OAuth2 Proxy
  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
    container_name: oauth2-proxy
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      OAUTH2_PROXY_PROVIDER: github
      OAUTH2_PROXY_CLIENT_ID: "${GITHUB_CLIENT_ID}"
      OAUTH2_PROXY_CLIENT_SECRET: "${GITHUB_CLIENT_SECRET}"
      OAUTH2_PROXY_COOKIE_SECRET: "$(openssl rand -hex 32)"
      OAUTH2_PROXY_EMAIL_DOMAINS: "*"
      OAUTH2_PROXY_UPSTREAMS: "file:///dev/null"
      OAUTH2_PROXY_HTTP_ADDRESS: "0.0.0.0:4180"
      OAUTH2_PROXY_SCOPE: "read:user,read:org"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.oauth2-proxy.rule=Host(`auth.${DOMAIN}`)"
      - "traefik.http.routers.oauth2-proxy.entrypoints=websecure"
      - "traefik.http.routers.oauth2-proxy.tls.certresolver=le"

networks:
  opendiscourse_net:
    name: opendiscourse_net
    driver: bridge
EOL

    log "Core services configuration created."
}

setup_ai_services() {
    log "Setting up AI services..."
    
    # Append AI services to docker-compose
    cat >> "$STACK_DIR/docker-compose.yml" << 'EOL'

  # LocalAI
  localai:
    image: localai/localai:latest
    container_name: localai
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      - MODELS_PATH=/models
      - THREADS=4
      - CONTEXT_SIZE=1024
      - DEBUG=true
    volumes:
      - ./models:/models
    ports:
      - "8082:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/readyz"]
      interval: 30s
      timeout: 10s
      retries: 3

  # OpenWebUI
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      - OLLAMA_API_BASE_URL=http://localai:8080
    volumes:
      - ./data/openwebui:/app/backend/data
    depends_on:
      - localai
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.openwebui.rule=Host(`chat.${DOMAIN}`)"
      - "traefik.http.routers.openwebui.entrypoints=websecure"
      - "traefik.http.routers.openwebui.tls.certresolver=le"
EOL

    log "AI services configuration created."
}

setup_monitoring() {
    log "Setting up monitoring stack..."
    
    # Append monitoring services to docker-compose
    cat >> "$STACK_DIR/docker-compose.yml" << 'EOL'

  # Prometheus
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    networks:
      - opendiscourse_net
    volumes:
      - ./config/prometheus:/etc/prometheus
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--web.enable-lifecycle'
    ports:
      - "9090:9090"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.prometheus.rule=Host(`prometheus.${DOMAIN}`)"
      - "traefik.http.routers.prometheus.entrypoints=websecure"
      - "traefik.http.routers.prometheus.tls.certresolver=le"

  # Grafana
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana_data:/var/lib/grafana
      - ./config/grafana/provisioning:/etc/grafana/provisioning
    depends_on:
      - prometheus
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(`grafana.${DOMAIN}`)"
      - "traefik.http.routers.grafana.entrypoints=websecure"
      - "traefik.http.routers.grafana.tls.certresolver=le"

  # cAdvisor
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    networks:
      - opendiscourse_net
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    devices:
      - /dev/kmsg:/dev/kmsg
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.cadvisor.rule=Host(`cadvisor.${DOMAIN}`)"
      - "traefik.http.routers.cadvisor.entrypoints=websecure"
      - "traefik.http.routers.cadvisor.tls.certresolver=le"

volumes:
  prometheus_data:
  grafana_data:
EOL

    # Create Prometheus configuration
    mkdir -p "$STACK_DIR/config/prometheus"
    cat > "$STACK_DIR/config/prometheus/prometheus.yml" << 'EOL'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
EOL

    log "Monitoring stack configuration created."
}

setup_automation() {
    log "Setting up automation services..."
    
    # Append automation services to docker-compose
    cat >> "$STACK_DIR/docker-compose.yml" << 'EOL'

  # n8n
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - N8N_HOST=workflow.${DOMAIN}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_JWT_SECRET=${JWT_SECRET}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=${N8N_ADMIN_PASSWORD}
    volumes:
      - ./data/n8n:/home/node/.n8n
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`workflow.${DOMAIN}`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=le"

  # Flowise
  flowise:
    image: flowiseai/flowise:latest
    container_name: flowise
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      - PORT=3000
      - FLOWISE_USERNAME=admin
      - FLOWISE_PASSWORD=${FLOWISE_ADMIN_PASSWORD}
      - DATABASE_PATH=/root/.flowise
    volumes:
      - ./data/flowise:/root/.flowise
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.flowise.rule=Host(`flowise.${DOMAIN}`)"
      - "traefik.http.routers.flowise.entrypoints=websecure"
      - "traefik.http.routers.flowise.tls.certresolver=le"
EOL

    log "Automation services configuration created."
}
}

# =============================================================================
# Main Installation Process
# =============================================================================

main() {
    # Initial setup
    check_root
    check_dependencies
    install_dependencies
    install_docker
    setup_directories
    setup_environment
    
    setup_core_services
    setup_ai_services
    setup_monitoring
    setup_automation
    
    log "Installation completed successfully!"
    log "\nNext steps:"
    log "1. Edit $STACK_DIR/.env and configure your domain and other settings"
    log "2. Run the deployment script: $STACK_DIR/scripts/deploy.sh"
    log "3. Access the dashboard at https://dashboard.${DOMAIN:-yourdomain.com}"
    log "\nServices available:"
    log "- Supabase Studio: https://supabase.${DOMAIN:-yourdomain.com}"
    log "- Neo4j Browser: https://neo4j.${DOMAIN:-yourdomain.com}"
    log "- Weaviate Console: https://weaviate.${DOMAIN:-yourdomain.com}"
    log "- MinIO Console: https://minio.${DOMAIN:-yourdomain.com}"
    log "- LocalAI: https://localai.${DOMAIN:-yourdomain.com}"
    log "- OpenWebUI: https://chat.${DOMAIN:-yourdomain.com}"
    log "- n8n: https://n8n.${DOMAIN:-yourdomain.com}"
    log "- Flowise: https://flowise.${DOMAIN:-yourdomain.com}"
    log "- Grafana: https://grafana.${DOMAIN:-yourdomain.com} (admin/${GRAFANA_ADMIN_PASSWORD})"
}

# Run main function
main "$@"
