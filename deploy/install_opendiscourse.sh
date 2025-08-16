#!/bin/bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default configuration
STACK_DIR="/opt/opendiscourse"
LOG_FILE="/var/log/opendiscourse_install.log"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root. Use 'sudo -E $0'"
    fi
}

# Install required packages
install_dependencies() {
    log "Updating package lists and installing dependencies..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        jq \
        unzip \
        git \
        python3-pip \
        python3-venv \
        ufw
}

# Install Docker and Docker Compose
install_docker() {
    if ! command -v docker &> /dev/null; then
        log "Installing Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
        systemctl enable --now docker
    else
        log "Docker is already installed"
    fi
}

# Configure firewall
setup_firewall() {
    log "Configuring firewall..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    systemctl enable --now ufw
}

# Create directory structure
setup_directories() {
    log "Creating directory structure..."
    mkdir -p "$STACK_DIR/"{letsencrypt,traefik,services,monitoring,scripts,data/{inbox,backups}}
    chmod 700 "$STACK_DIR/letsencrypt"
    touch "$STACK_DIR/letsencrypt/acme.json"
    chmod 600 "$STACK_DIR/letsencrypt/acme.json"
    chmod -R 755 "$STACK_DIR/data"
}

# Clone the OpenDiscourse repository
clone_repository() {
    local repo_dir="$STACK_DIR/repo"
    if [ ! -d "$repo_dir" ]; then
        log "Cloning OpenDiscourse repository..."
        git clone https://github.com/your-org/opendiscourse.git "$repo_dir"
    else
        log "Repository already exists at $repo_dir, pulling latest changes..."
        git -C "$repo_dir" pull
    fi
}

# Generate environment file
setup_environment() {
    local env_file="$STACK_DIR/.env"
    if [ ! -f "$env_file" ]; then
        log "Creating environment file..."
        cat > "$env_file" <<EOF
# OpenDiscourse Configuration
DOMAIN=opendiscourse.net
EMAIL=admin@opendiscourse.net

# Database
POSTGRES_USER=opendiscourse
POSTGRES_PASSWORD=$(openssl rand -hex 24)
POSTGRES_DB=opendiscourse

# Redis
REDIS_PASSWORD=$(openssl rand -hex 24)

# JWT Secret
JWT_SECRET=$(openssl rand -hex 32)

# Traefik
TRAEFIK_USER=admin
TRAEFIK_PASSWORD=$(openssl rand -hex 16)

# Monitoring
GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 16)

# Email (SMTP)
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=user@example.com
SMTP_PASSWORD=your-smtp-password
SMTP_FROM=noreply@opendiscourse.net

# Backups
BACKUP_CRON="0 2 * * *"  # Daily at 2 AM
BACKUP_RETENTION_DAYS=30

# Storage
UPLOAD_DIR=/var/lib/opendiscourse/uploads
MAX_UPLOAD_SIZE=100M

# Development
DEBUG=false
EOF
        chmod 600 "$env_file"
        log "Environment file created at $env_file"
    else
        log "Environment file already exists at $env_file"
    fi
}

# Install monitoring stack
setup_monitoring() {
    log "Setting up monitoring stack..."
    local monitoring_dir="$STACK_DIR/monitoring"
    mkdir -p "$monitoring_dir"
    
    # Create Prometheus config
    cat > "$monitoring_dir/prometheus.yml" <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'docker'
    static_configs:
      - targets: ['docker:9323']
    metrics_path: '/metrics'
    scheme: http

  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8080']
EOF

    # Create docker-compose.monitoring.yml
    cat > "$monitoring_dir/docker-compose.monitoring.yml" <<EOF
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    ports:
      - "9090:9090"
    networks:
      - opendiscourse_net

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=\${GRAFANA_ADMIN_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
    ports:
      - "3000:3000"
    networks:
      - opendiscourse_net
    depends_on:
      - prometheus

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - opendiscourse_net

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    devices:
      - /dev/kmsg
    networks:
      - opendiscourse_net

networks:
  opendiscourse_net:
    external: true

volumes:
  prometheus_data:
  grafana_data:
EOF
    
    log "Monitoring stack configuration complete"
}

# Setup backup script
setup_backups() {
    log "Setting up backup script..."
    local backup_script="$STACK_DIR/scripts/backup.sh"
    
    cat > "$backup_script" <<'EOF'
#!/bin/bash
set -euo pipefail

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$SCRIPT_DIR")"
cd "$STACK_DIR"

# Load environment variables
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Default values
BACKUP_DIR="${BACKUP_DIR:-$STACK_DIR/data/backups}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/backup_${TIMESTAMP}.tar.gz"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Create backup
echo "Creating backup at $BACKUP_FILE..."
docker-compose exec -T db pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > "${BACKUP_DIR}/db_dump.sql"

tar -czf "$BACKUP_FILE" \
    --exclude='*/node_modules/*' \
    --exclude='*/venv/*' \
    --exclude='*/.git/*' \
    --exclude='*/__pycache__/*' \
    "${BACKUP_DIR}/db_dump.sql" \
    "$STACK_DIR/letsencrypt" \
    "$STACK_DIR/traefik"

# Clean up old backups
find "$BACKUP_DIR" -name "backup_*.tar.gz" -type f -mtime "+$RETENTION_DAYS" -delete

echo "Backup completed: $BACKUP_FILE"
EOF

    chmod +x "$backup_script"
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "0 2 * * * $backup_script") | crontab -
    
    log "Backup script installed and scheduled"
}

# Create docker-compose.yml
create_docker_compose() {
    log "Creating docker-compose.yml..."
    cat > "$STACK_DIR/docker-compose.yml" <<'EOF'
version: '3.8'

services:
  # Reverse Proxy
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: unless-stopped
    command:
      - --api.insecure=false
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --certificatesresolvers.letsencryptresolver.acme.httpchallenge=true
      - --certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web
      - --certificatesresolvers.letsencryptresolver.acme.email=${EMAIL}
      - --certificatesresolvers.letsencryptresolver.acme.storage=/letsencrypt/acme.json
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${STACK_DIR}/letsencrypt:/letsencrypt
    networks:
      - opendiscourse_net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN}`)"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=letsencryptresolver"
      - "traefik.http.routers.traefik.middlewares=auth"
      - "traefik.http.middlewares.auth.basicauth.users=${TRAEFIK_USER}:${TRAEFIK_PASSWORD}"

  # Database
  db:
    image: postgres:15-alpine
    container_name: db
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - opendiscourse_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Redis
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    networks:
      - opendiscourse_net
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Application
  app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: app
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      - NODE_ENV=production
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}
      - REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379/0
      - JWT_SECRET=${JWT_SECRET}
      - SMTP_HOST=${SMTP_HOST}
      - SMTP_PORT=${SMTP_PORT}
      - SMTP_USER=${SMTP_USER}
      - SMTP_PASSWORD=${SMTP_PASSWORD}
      - SMTP_FROM=${SMTP_FROM}
    volumes:
      - ${UPLOAD_DIR}:/app/uploads
    networks:
      - opendiscourse_net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app.rule=Host(`${DOMAIN}`)"
      - "traefik.http.routers.app.entrypoints=websecure"
      - "traefik.http.routers.app.tls.certresolver=letsencryptresolver"
      - "traefik.http.services.app.loadbalancer.server.port=3000"

networks:
  opendiscourse_net:
    driver: bridge

volumes:
  db_data:
  redis_data:
EOF

    log "docker-compose.yml created"
}

# Start services
start_services() {
    log "Starting OpenDiscourse services..."
    cd "$STACK_DIR"
    
    # Create Docker network if it doesn't exist
    if ! docker network inspect opendiscourse_net >/dev/null 2>&1; then
        docker network create opendiscourse_net
    fi
    
    # Start main services
    docker-compose up -d
    
    # Start monitoring stack
    if [ -f "monitoring/docker-compose.monitoring.yml" ]; then
        docker-compose -f monitoring/docker-compose.monitoring.yml up -d
    fi
    
    log "Services started successfully!"
}

# Main execution
main() {
    log "Starting OpenDiscourse installation..."
    
    check_root
    install_dependencies
    install_docker
    setup_firewall
    setup_directories
    clone_repository
    setup_environment
    setup_monitoring
    setup_backups
    create_docker_compose
    start_services
    
    log "\n${GREEN}OpenDiscourse has been successfully installed!${NC}"
    log "\nNext steps:"
    log "1. Access the application at: https://${DOMAIN:-your-domain.com}"
    log "2. Access Traefik dashboard at: https://traefik.${DOMAIN:-your-domain.com}"
    log "3. Access Grafana at: http://localhost:3000 (admin:${GRAFANA_ADMIN_PASSWORD:-your-password})"
    log "\nBackups are scheduled to run daily at 2 AM and kept for ${BACKUP_RETENTION_DAYS:-30} days."
    log "\nTo stop all services: cd $STACK_DIR && docker-compose down"
    log "To start services: cd $STACK_DIR && docker-compose up -d"
    log "To view logs: cd $STACK_DIR && docker-compose logs -f"
    log "\nFor more information, refer to the documentation in the repo/docs directory."
}

# Run main function
main "$@"
