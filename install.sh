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
        local jwt_secret
        local anon_key
        local service_key
        jwt_secret=$(openssl rand -hex 32)
        anon_key=$(openssl rand -hex 32)
        service_key=$(openssl rand -hex 32)
        cat > "$env_file" <<EOF
# =============================================================================
# OpenDiscourse Configuration
# =============================================================================

# Domain and Email
DOMAIN=$DOMAIN
EMAIL=$EMAIL
SITE_URL=$SITE_URL

# Database
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
NEO4J_PASSWORD=$NEO4J_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD

# Supabase
JWT_SECRET=$jwt_secret
ANON_KEY=$anon_key
SERVICE_ROLE_KEY=$service_key
SECRET_KEY_BASE=$(openssl rand -hex 32)

# MinIO
MINIO_ROOT_USER=$MINIO_ROOT_USER
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD
MINIO_ACCESS_KEY=$MINIO_ACCESS_KEY
MINIO_SECRET_KEY=$MINIO_SECRET_KEY

# OAuth2 Proxy
OAUTH2_PROXY_CLIENT_ID=$OAUTH2_PROXY_CLIENT_ID
OAUTH2_PROXY_CLIENT_SECRET=$OAUTH2_PROXY_CLIENT_SECRET
OAUTH2_PROXY_COOKIE_SECRET=$OAUTH2_PROXY_COOKIE_SECRET

# Application
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
FLOWISE_PASSWORD=$FLOWISE_PASSWORD

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

# Note: Automation services are now included via deploy.sh

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
  # Database Volumes
  postgres_data:
  redis_data:
  neo4j_data:
  neo4j_import:
  weaviate_data:
  minio_data:
  
  # AI/ML Volumes
  localai_data:
  
  # Application Data
  supabase_storage:
  n8n_data:
  flowise_data:
  
  # Monitoring
  prometheus_data:
  grafana_data:
  loki_data:
  
  # Backups
  backup_data:

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
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik:/etc/traefik
      - ./letsencrypt:/letsencrypt
    environment:
      - CF_API_EMAIL=${EMAIL}
      - CF_DNS_API_TOKEN=${CF_API_TOKEN}
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.file.directory=/etc/traefik/dynamic"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.le.acme.email=${EMAIL}"
      - "--certificatesresolvers.le.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.le.acme.dnschallenge.provider=cloudflare"
      - "--certificatesresolvers.le.acme.dnschallenge.delayBeforeCheck=30"
      - "--log.level=INFO"
    labels:
      - "traefik.enable=true"
      # Dashboard
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN}`)"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=le"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.middlewares=traefik-auth"
      # Global middleware
      - "traefik.http.middlewares.https-redirect.redirectscheme.scheme=https"
      - "traefik.http.middlewares.https-redirect.redirectscheme.permanent=true"
      # Basic Auth for Traefik Dashboard
      - "traefik.http.middlewares.traefik-auth.basicauth.users=${TRAEFIK_AUTH}"
      # Rate limiting
      - "traefik.http.middlewares.ratelimit.ratelimit.average=100"
      - "traefik.http.middlewares.ratelimit.ratelimit.burst=50"
      # Security headers
      - "traefik.http.middlewares.security-headers.headers.forceSTSHeader=true"
      - "traefik.http.middlewares.security-headers.headers.STSSeconds=31536000"
      - "traefik.http.middlewares.security-headers.headers.STSIncludeSubdomains=true"
      - "traefik.http.middlewares.security-headers.headers.STSPreload=true"
      - "traefik.http.middlewares.security-headers.headers.browserXSSFilter=true"
      - "traefik.http.middlewares.security-headers.headers.contentTypeNosniff=true"
      - "traefik.http.middlewares.security-headers.headers.frameDeny=true"
      - "traefik.http.middlewares.security-headers.headers.sslRedirect=true"
      # Global default middleware chain
      - "traefik.http.middlewares.default-chain.chain.middlewares=security-headers,ratelimit"

  # Supabase Database
  supabase-db:
    image: supabase/postgres:15.1.0.76
    container_name: supabase-db
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      JWT_SECRET: ${JWT_SECRET}
      JWT_EXPIRY: 3600
      JWT_DEFAULT_GROUP: authenticated
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init-scripts/:/docker-entrypoint-initdb.d/
    networks:
      - opendiscourse_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
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
      GOTRUE_MAILER_AUTOCONFIRM: "true"
      GOTRUE_MAILER_URLPATHS_CONFIRMATION: "/auth/v1/verify"
      GOTRUE_MAILER_URLPATHS_INVITE: "/auth/v1/verify"
      GOTRUE_MAILER_URLPATHS_RECOVERY: "/auth/v1/verify"
      GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE: "/auth/v1/verify"
    depends_on:
      - supabase-db
    networks:
      - opendiscourse_net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.supabase-auth.rule=Host(`auth.${DOMAIN}`)"
      - "traefik.http.routers.supabase-auth.entrypoints=websecure"
      - "traefik.http.routers.supabase-auth.tls.certresolver=le"

  supabase-meta:
    image: supabase/postgres-meta:v0.66.0
    container_name: supabase-meta
    restart: unless-stopped
    environment:
      PG_META_PORT: 8080
      PG_META_DB_HOST: supabase-db
      PG_META_DB_PASSWORD: ${POSTGRES_PASSWORD}
    depends_on:
      - supabase-db
    networks:
      - opendiscourse_net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  supabase-rest:
    image: postgrest/postgrest:v11.2.0
    container_name: supabase-rest
    restart: unless-stopped
    environment:
      PGRST_DB_URI: postgres://postgres:${POSTGRES_PASSWORD}@supabase-db:5432/${POSTGRES_DB}
      PGRST_DB_SCHEMA: public,storage,graphql_public
      PGRST_DB_ANON_ROLE: anon
      PGRST_JWT_SECRET: ${JWT_SECRET}
      PGRST_DB_USE_LEGACY_GUCS: "false"
      PGRST_SERVER_PORT: 3000
      PGRST_OPENAPI_SERVER_PROXY_URI: ${SITE_URL}/rest/v1/
      PGRST_DB_POOL: 200
      PGRST_DB_POOL_TIMEOUT: 10
      PGRST_SERVER_TIMEOUT: 60
      PGRST_LOG_LEVEL: info
      PGRST_APP_SETTINGS_JWT_SECRET: ${JWT_SECRET}
      PGRST_APP_SETTINGS_JWT_SECRET_IS_BASE64: "false"
      PGRST_APP_SETTINGS_EXTERNAL_API_URL: ${SITE_URL}
      PGRST_APP_SETTINGS_SITE_URL: ${SITE_URL}
    depends_on:
      supabase-db:
        condition: service_healthy
    networks:
      - opendiscourse_net
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/rest/v1/"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.supabase-rest.rule=Host(`rest.${DOMAIN}`)"
      - "traefik.http.routers.supabase-rest.entrypoints=websecure"
      - "traefik.http.routers.supabase-rest.tls.certresolver=le"
      - "traefik.http.services.supabase-rest.loadbalancer.server.port=3000"
      - "traefik.http.middlewares.supabase-rest-stripprefix.stripprefix.prefixes=/rest/v1"
      - "traefik.http.routers.supabase-rest.middlewares=supabase-rest-stripprefix"

  supabase-realtime:
    image: supabase/realtime:v2.22.0
    container_name: supabase-realtime
    restart: unless-stopped
    environment:
      DB_HOST: supabase-db
      DB_PORT: 5432
      DB_NAME: ${POSTGRES_DB}
      DB_USER: postgres
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_AFTER_CONNECT_QUERY: 'SET search_path TO _realtime,public;'
      DB_ENC_KEY: ${JWT_SECRET}
      PORT: 4000
      JWT_SECRET: ${JWT_SECRET}
      SLOT_NAME: supabase_realtime
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      ERL_AFLAGS: "-proto_dist inet_tcp"
      REPLICATION_MODE: RLS
      REPLICATION_POLL_INTERVAL: 100
      API_JWT_SECRET: ${JWT_SECRET}
      API_JWT_ISSUER: supabase
      API_JWT_EXP: 3600
      API_JWT_LEEWAY: 60
      API_JWT_AUD: ""
      API_JWT_CLAIM_VALIDATORS: ""
      API_JWT_CLAIM_VALIDATORS_REQUIRED: ""
      API_JWT_CLAIM_VALIDATORS_OPTIONAL: ""
    depends_on:
      supabase-db:
        condition: service_healthy
    networks:
      - opendiscourse_net
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.supabase-realtime.rule=Host(`realtime.${DOMAIN}`)"
      - "traefik.http.routers.supabase-realtime.entrypoints=websecure"
      - "traefik.http.routers.supabase-realtime.tls.certresolver=le"
      - "traefik.http.services.supabase-realtime.loadbalancer.server.port=4000"
      - "traefik.http.services.supabase-realtime.loadbalancer.server.scheme=h2c"

  supabase-storage:
    image: supabase/storage-api:v0.41.2
    container_name: supabase-storage
    restart: unless-stopped
    environment:
      DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@supabase-db:5432/${POSTGRES_DB}?sslmode=disable
      DATABASE_POOL_SIZE: 30
      PGRST_JWT_SECRET: ${JWT_SECRET}
      FILE_SIZE_LIMIT: 157286400  # 150MB
      STORAGE_BACKEND: s3
      S3_ENDPOINT: http://minio:9000
      S3_ACCESS_KEY: ${MINIO_ACCESS_KEY}
      S3_SECRET_KEY: ${MINIO_SECRET_KEY}
      S3_BUCKET: supabase-storage
      S3_FORCE_PATH_STYLE: 'true'
      S3_SSL_ENABLED: 'false'
      TENANT_ID: stub
      REGION: us-east-1
      GLOBAL_S3_BUCKET: supabase-storage
      ANON_KEY: ${ANON_KEY}
      SERVICE_KEY: ${SERVICE_ROLE_KEY}
      STORAGE_S3_MAX_CONCURRENCY: 100
      STORAGE_S3_PART_SIZE: 5242880  # 5MB
      LOG_LEVEL: info
      ENABLE_CORS: 'true'
      CACHE_CONTROL_MAX_AGE: 3600
      IMGPROXY_ENABLED: 'true'
      IMGPROXY_URL: http://imgproxy:8081
    depends_on:
      supabase-db:
        condition: service_healthy
      minio:
        condition: service_healthy
    networks:
      - opendiscourse_net
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5000/status"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.supabase-storage.rule=Host(`storage.${DOMAIN}`)"
      - "traefik.http.routers.supabase-storage.entrypoints=websecure"
      - "traefik.http.routers.supabase-storage.tls.certresolver=le"
      - "traefik.http.services.supabase-storage.loadbalancer.server.port=5000"
      - "traefik.http.middlewares.supabase-storage-stripprefix.stripprefix.prefixes=/storage/v1"
      - "traefik.http.routers.supabase-storage.middlewares=supabase-storage-stripprefix"

  supabase-kong:
    image: kong:3.4
    container_name: supabase-kong
    restart: unless-stopped
    environment:
      # Core settings
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: "/var/lib/kong/kong.yml"
      KONG_DNS_ORDER: "LAST,A,CNAME"
      KONG_NGINX_WORKER_PROCESSES: "auto"
      KONG_NGINX_WORKER_CONNECTIONS: "4096"
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_PROXY_LISTEN: "0.0.0.0:8000, 0.0.0.0:8443 ssl http2"
      KONG_ADMIN_LISTEN: "0.0.0.0:8001, 0.0.0.0:8444 ssl http2"
      KONG_SSL_CERT: /var/run/secrets/ssl/kong.crt
      KONG_SSL_CERT_KEY: /var/run/secrets/ssl/kong.key
      
      # Performance
      KONG_WORKER_STATE_UPDATE_FREQUENCY: 5
      KONG_UPSTREAM_KEEPALIVE_POOL_SIZE: 100
      KONG_UPSTREAM_KEEPALIVE_IDLE_TIMEOUT: 60
      KONG_UPSTREAM_KEEPALIVE_REQUESTS: 1000
      
      # Security
      KONG_HEADERS: "off"
      KONG_SSL_PREFER_SERVER_CIPHERS: "on"
      KONG_SSL_CIPHERS: "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384"
      KONG_SSL_CIPHER_SUITE: "custom"
      
      # Logging
      KONG_PROXY_ACCESS_LOG: "/dev/stdout"
      KONG_PROXY_ERROR_LOG: "/dev/stderr"
      KONG_ADMIN_ACCESS_LOG: "/dev/stdout"
      KONG_ADMIN_ERROR_LOG: "/dev/stderr"
      KONG_NGINX_HTTP_LOG_LEVEL: "notice"
      
      # Plugins
      KONG_PLUGINS: "bundled,request-transformer,cors,key-auth,acl"
      
      # Rate limiting
      KONG_PLUGINSERVER_NAMES: "rate-limiting,rate-limiting-advanced"
      KONG_RATE_LIMITING_REDIS_HOST: "redis"
      KONG_RATE_LIMITING_REDIS_PORT: 6379
      KONG_RATE_LIMITING_REDIS_SSL: "off"
      
      # Request/Response transformation
      KONG_PLUGINSERVER_REQUEST_TRANSFORMER_START_CMD: "/usr/local/bin/kong-request-transformer"
      KONG_PLUGINSERVER_REQUEST_TRANSFORMER_NAMED_PIPE_PREFIX: "/usr/local/kong/request_transformer_named_pipes"
      
      # CORS
      KONG_PLUGINSERVER_CORS_NAMED_PIPE_PREFIX: "/usr/local/kong/cors_named_pipes"
      
      # Custom Nginx templates
      KONG_NGINX_HTTP_INCLUDE: "/etc/kong/custom-nginx.template"
      
    volumes:
      - ./config/supabase/kong.yml:/var/lib/kong/kong.yml
      - ./config/supabase/kong-nginx.template:/etc/kong/custom-nginx.template:ro
      - ./certs:/var/run/secrets/ssl:ro
      
    depends_on:
      redis:
        condition: service_healthy
      supabase-auth:
        condition: service_healthy
      supabase-rest:
        condition: service_healthy
      supabase-realtime:
        condition: service_healthy
      supabase-storage:
        condition: service_healthy
        
    networks:
      - opendiscourse_net
      
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 30s
      timeout: 10s
      retries: 3
      
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.supabase-kong.rule=Host(`api.${DOMAIN}`)"
      - "traefik.http.routers.supabase-kong.entrypoints=websecure"
      - "traefik.http.routers.supabase-kong.tls.certresolver=le"
      - "traefik.http.services.supabase-kong.loadbalancer.server.port=8000"
      - "traefik.http.middlewares.supabase-kong-stripprefix.stripprefix.prefixes=/rest/v1,/auth/v1,/storage/v1,/realtime/v1"
      - "traefik.http.routers.supabase-kong.middlewares=supabase-kong-stripprefix"

  # Supabase Studio (Admin UI)
  supabase-studio:
    image: supabase/studio:20240318-9b1a4c7
    container_name: supabase-studio
    restart: unless-stopped
    environment:
      # Database connection
      STUDIO_PG_META_URL: http://supabase-meta:8080
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      
      # App settings
      STUDIO_DEFAULT_ORGANIZATION: default-org
      STUDIO_DEFAULT_PROJECT: default-project
      
      # API configuration
      SUPABASE_URL: ${SITE_URL}
      SUPABASE_PUBLIC_URL: ${SITE_URL}
      SUPABASE_ANON_KEY: ${ANON_KEY}
      SUPABASE_SERVICE_KEY: ${SERVICE_ROLE_KEY}
      
      # Authentication
      SUPABASE_AUTH_URL: ${SITE_URL}/auth/v1
      SUPABASE_AUTH_ANON_KEY: ${ANON_KEY}
      
      # Storage
      SUPABASE_STORAGE_URL: ${SITE_URL}/storage/v1
      SUPABASE_STORAGE_KEY: ${SERVICE_ROLE_KEY}
      
      # Realtime
      SUPABASE_REALTIME_URL: ${SITE_URL}/realtime/v1
      
      # Logging
      LOG_LEVEL: info
      
      # Feature flags
      DISABLE_SIGNUP: "false"
      DISABLE_ANALYTICS: "true"
      
    depends_on:
      supabase-meta:
        condition: service_healthy
      supabase-rest:
        condition: service_healthy
      supabase-auth:
        condition: service_healthy
      supabase-storage:
        condition: service_healthy
      supabase-realtime:
        condition: service_healthy
        
    networks:
      - opendiscourse_net
      
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/api/profile"]
      interval: 30s
      timeout: 10s
      retries: 3
      
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.supabase-studio.rule=Host(`studio.${DOMAIN}`)"
      - "traefik.http.routers.supabase-studio.entrypoints=websecure"
      - "traefik.http.routers.supabase-studio.tls.certresolver=le"
      - "traefik.http.services.supabase-studio.loadbalancer.server.port=3000"
      - "traefik.http.middlewares.supabase-studio-headers.headers.customrequestheaders.X-Forwarded-Proto=https"
      - "traefik.http.routers.supabase-studio.middlewares=supabase-studio-headers"

  # Supabase Meta (for Studio)
  supabase-meta:
    image: supabase/postgres-meta:v0.66.0
    container_name: supabase-meta
    restart: unless-stopped
    environment:
      PG_META_PORT: 8080
      PG_META_DB_HOST: supabase-db
      PG_META_DB_PASSWORD: ${POSTGRES_PASSWORD}
      PG_META_DB_NAME: ${POSTGRES_DB}
      PG_META_DB_USER: postgres
      PG_META_SERVER_HOST: 0.0.0.0
      PG_META_SERVER_PORT: 8080
      PG_META_READ_ONLY: "false"
      PG_META_SERVER_TIMEOUT: 60
      PG_META_SERVER_ENABLE_TLS: "false"
      PG_META_DEBUG_MODE: "false"
      PG_META_QUERY_LIMIT: 100
      PG_META_QUERY_TIMEOUT_MS: 60000
      PG_META_QUERY_CACHE: "true"
      PG_META_QUERY_CACHE_EXPIRE: 300
      PG_META_QUERY_CACHE_REFRESH: "false"
      PG_META_QUERY_CACHE_STALE: 300
      PG_META_QUERY_CACHE_MAX_ENTRIES: 1000
      PG_META_QUERY_CACHE_MAX_SIZE: "10MB"
      PG_META_QUERY_CACHE_PATH: /tmp/pg_meta_query_cache
      
    depends_on:
      supabase-db:
        condition: service_healthy
        
    networks:
      - opendiscourse_net
      
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      
    labels:
      - "traefik.enable=false"

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
      ENABLE_MODULES: 'text2vec-transformers,generative-openai,generative-cohere,generative-palm,reranker-transformers'
      TRANSFORMERS_INFERENCE_API: 'http://localai:8080'
      
    volumes:
      - weaviate_data:/var/lib/weaviate
      
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/v1/.well-known/ready"]
      interval: 30s
      timeout: 10s
      retries: 3

  # LocalAI - Local OpenAI-compatible API
  localai:
    image: localai/localai:latest
    container_name: localai
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      - DEBUG=true
      - THREADS=4
      - MODELS_PATH=/models
      - CONTEXT_SIZE=2048
      - BACKEND=llama
      - MODEL=ggml-model-q4_0.bin
      - PRELOAD_MODELS="/models/ggml-model-q4_0.bin"
      - HUGGINGFACE_HUB_CACHE=/models/huggingface
      - HF_HUB_ENABLE_HF_TRANSFER=1
      - CUSTOM_MODELS=""
      - SKIP_VERIFY_TLS=false
      - PARALLEL_REQUESTS=false
      - PARALLEL_REQUESTS_LIMIT=5
      - MAX_EMBEDDING_TOKENS=8191
      - MAX_TOKENS=32768
      - F16=true
      - DEBUG=true
      - LOAD_CONFIGS="/models/config.yaml"
      - LOAD_CONFIGS_FILE="/models/config.yaml"
    volumes:
      - ./models:/models
      - localai_data:/models/huggingface
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/readyz"]
      interval: 30s
      timeout: 10s
      retries: 3

  # OpenWebUI - Web interface for LocalAI
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      - OLLAMA_API_BASE_URL=http://localai:8080/v1
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
      - WEBUI_JWT_SECRET=${JWT_SECRET}
      - WEBUI_NAME="OpenDiscourse AI"
      - WEBUI_URL=https://ai.${DOMAIN}
      - WEBUI_DEFAULT_MODEL=localai
      - WEBUI_DEFAULT_PROMPT_SUFFIX=""
      - WEBUI_DEFAULT_TEMPERATURE=0.7
      - WEBUI_DEFAULT_TOP_P=0.9
      - WEBUI_DEFAULT_TOP_K=40
      - WEBUI_DEFAULT_MAX_TOKENS=2048
      - WEBUI_AUTH=disable
      - WEBUI_ALLOW_SIGNUP=true
      - WEBUI_ALLOW_PASSWORD_LOGIN=true
      - WEBUI_DEFAULT_USER_QUOTA=1000000
      - WEBUI_DEFAULT_USER_QUOTA_PERIOD=monthly
      - WEBUI_DEFAULT_USER_ROLE=user
      - WEBUI_DEFAULT_USER_THEME=dark
      - WEBUI_DEFAULT_USER_LOCALE=en
      - WEBUI_FOOTER_HTML="<div>Powered by OpenDiscourse</div>"
    volumes:
      - openwebui_data:/app/backend/data
    depends_on:
      - localai
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.openwebui.rule=Host(`ai.${DOMAIN}`)"
      - "traefik.http.routers.openwebui.entrypoints=websecure"
      - "traefik.http.routers.openwebui.tls.certresolver=le"
      - "traefik.http.services.openwebui.loadbalancer.server.port=8080"

  # Flowise - Visual LangChain builder
  flowise:
    image: flowiseai/flowise:latest
    container_name: flowise
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      - PORT=3000
      - FLOWISE_USERNAME=${FLOWISE_USERNAME:-admin}
      - FLOWISE_PASSWORD=${FLOWISE_PASSWORD:-${ADMIN_PASSWORD}}
      - FLOWISE_SECRETKEY=${FLOWISE_SECRET:-$(openssl rand -hex 32)}
      - DATABASE_PATH=/root/.flowise
      - APIKEY_ENABLED=true
      - APIKEY_HASH=$(echo -n "${FLOWISE_API_KEY:-$(openssl rand -hex 16)}" | argon2 $(openssl rand -hex 16) -e -id -k 19456 -t 2 -p 1)
      - EXECUTION_MODE=child
      - TOOL_FUNCTION_BUILTIN_DEP=all
      - TOOL_FUNCTION_EXTERNAL=
      - LANGCHAIN_TRACING_V2=false
      - LANGCHAIN_ENDPOINT=
      - LANGCHAIN_API_KEY=
      - LANGCHAIN_PROJECT=
      - OPENAI_API_KEY=
      - OPENAI_API_KEY_1=
      - OPENAI_TYPE=
      - OPENAI_API_VERSION=
      - OPENAI_ORGANIZATION=
      - OPENAI_BASE_PATH=
      - AZURE_OPENAI_API_KEY=
      - AZURE_OPENAI_API_VERSION=
      - AZURE_OPENAI_API_INSTANCE_NAME=
      - AZURE_OPENAI_API_DEPLOYMENT_NAME=
      - AZURE_OPENAI_API_EMBEDDINGS_DEPLOYMENT_NAME=
      - AZURE_OPENAI_API_COMPLETIONS_DEPLOYMENT_NAME=
      - DEBUG=flowise*
    volumes:
      - flowise_data:/root/.flowise
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/api/v1/version"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.flowise.rule=Host(`flow.${DOMAIN}`)"
      - "traefik.http.routers.flowise.entrypoints=websecure"
      - "traefik.http.routers.flowise.tls.certresolver=le"
      - "traefik.http.services.flowise.loadbalancer.server.port=3000"
      - "traefik.http.routers.flowise.middlewares=auth-basic@docker"
      - "traefik.http.middlewares.auth-basic.basicauth.users=${FLOWISE_USERNAME:-admin}:${FLOWISE_PASSWORD_HASH:-$(openssl passwd -apr1 ${ADMIN_PASSWORD})}"
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
      DEFAULT_VECTORIZER_MODULE: 'text2vec-transformers'
      ENABLE_MODULES: 'text2vec-transformers,generative-openai'
      TRANSFORMERS_INFERENCE_API: 'http://localai:8080'
      CLUSTER_HOSTNAME: 'node1'
    volumes:
      - weaviate_data:/var/lib/weaviate
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.weaviate.rule=Host(`weaviate.${DOMAIN}`)"
      - "traefik.http.routers.weaviate.entrypoints=websecure"
      - "traefik.http.routers.weaviate.tls.certresolver=le"
      - "traefik.http.services.weaviate.loadbalancer.server.port=8080"

  # LocalAI for embeddings and LLM
  localai:
    image: localai/localai:latest
    container_name: localai
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      - MODELS_PATH=/models
      - THREADS=4
      - CONTEXT_SIZE=2048
      - DEBUG=true
    volumes:
      - localai_data:/models
      - ./config/localai/models.yaml:/app/models.yaml
    ports:
      - "8080:8080"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.localai.rule=Host(`localai.${DOMAIN}`)
      - "traefik.http.routers.localai.entrypoints=websecure"
      - "traefik.http.routers.localai.tls.certresolver=le"

  # OpenWebUI for chat interface
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      - OLLAMA_API_BASE_URL=http://localai:8080
      - OPENAI_API_KEY=localai
    depends_on:
      - localai
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.openwebui.rule=Host(`chat.${DOMAIN}`)
      - "traefik.http.routers.openwebui.entrypoints=websecure"
      - "traefik.http.routers.openwebui.tls.certresolver=le"
      - "traefik.http.services.openwebui.loadbalancer.server.port=8080"

  # n8n for workflow automation
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
      - N8N_WEBHOOK_URL=https://n8n.${DOMAIN}/
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_HOST=supabase-db
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - DB_POSTGRESDB_PORT=5432
    depends_on:
      - supabase-db
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`n8n.${DOMAIN}`)
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=le"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"

  # Flowise for AI workflow automation
  flowise:
    image: flowiseai/flowise:latest
    container_name: flowise
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      - PORT=3000
      - FLOWISE_USERNAME=admin
      - FLOWISE_PASSWORD=${FLOWISE_PASSWORD}
      - DATABASE_TYPE=postgres
      - DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@supabase-db:5432/${POSTGRES_DB}
    depends_on:
      - supabase-db
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.flowise.rule=Host(`flowise.${DOMAIN}`)
      - "traefik.http.routers.flowise.entrypoints=websecure"
      - "traefik.http.routers.flowise.tls.certresolver=le"
      - "traefik.http.services.flowise.loadbalancer.server.port=3000"

  # RAG API for document retrieval
  rag-api:
    build: ./services/rag-api
    container_name: rag-api
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      - WEAVIATE_URL=http://weaviate:8080
      - OPENAI_API_KEY=localai
      - OPENAI_API_BASE=http://localai:8080
    depends_on:
      - weaviate
      - localai
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.rag-api.rule=Host(`rag.${DOMAIN}`)
      - "traefik.http.routers.rag-api.entrypoints=websecure"
      - "traefik.http.routers.rag-api.tls.certresolver=le"

  # GraphRAG API for knowledge graph operations
  graphrag-api:
    build: ./services/graphrag-api
    container_name: graphrag-api
    restart: unless-stopped
    networks:
      - opendiscourse_net
    environment:
      - NEO4J_URI=bolt://neo4j:7687
      - NEO4J_USER=neo4j
      - NEO4J_PASSWORD=${NEO4J_PASSWORD}
      - OPENAI_API_KEY=localai
      - OPENAI_API_BASE=http://localai:8080
    depends_on:
      - neo4j
      - localai
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.graphrag-api.rule=Host(`graphrag.${DOMAIN}`)
      - "traefik.http.routers.graphrag-api.entrypoints=websecure"
      - "traefik.http.routers.graphrag-api.tls.certresolver=le"

  # PDF Worker for document processing
  pdf-worker:
    build: ./services/pdf-worker
    container_name: pdf-worker
    restart: unless-stopped
    networks:
      - opendiscourse_net
    volumes:
      - ./data/inbox:/inbox
      - ./data/processed:/processed
    environment:
      - RAG_API_URL=http://rag-api:8000
      - GRAPHRAG_API_URL=http://graphrag-api:8010
    depends_on:
      - rag-api
      - graphrag-api
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
