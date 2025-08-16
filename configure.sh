#!/bin/bash
set -euo pipefail

# =============================================================================
# OpenDiscourse Configuration Script
# =============================================================================
# This script helps configure the OpenDiscourse environment

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="/opt/opendiscourse"
ENV_FILE="$STACK_DIR/.env"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root. Use 'sudo -E $0'${NC}" >&2
    exit 1
fi

# Load existing environment if it exists
if [ -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}Loading existing environment from $ENV_FILE${NC}"
    # Create a backup of the existing file
    cp "$ENV_FILE" "${ENV_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    # Source the existing environment
    set -a
    source "$ENV_FILE"
    set +a
else
    echo -e "${YELLOW}Creating new environment file at $ENV_FILE${NC}"
    mkdir -p "$STACK_DIR"
fi

# Function to prompt for input with default value
prompt_with_default() {
    local var_name="$1"
    local prompt="$2"
    local default_value="${!var_name:-}"
    
    read -p "$prompt${default_value:+ [$defaultValue]}: " value
    if [ -n "$value" ]; then
        eval "$var_name=\"$value\""
    elif [ -n "$default_value" ]; then
        eval "$var_name=\"$default_value\""
    fi
}

# Function to generate random string
generate_random_string() {
    local length=${1:-32}
    openssl rand -hex $((length/2)) | tr -d '\n'
}

# Main configuration
clear
echo -e "${GREEN}OpenDiscourse Configuration${NC}"
echo -e "${YELLOW}==========================${NC}\n"

# Domain and Email
prompt_with_default "DOMAIN" "Enter your domain (e.g., example.com):"
while [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]]; do
    echo -e "${RED}Invalid domain format. Please enter a valid domain.${NC}"
    prompt_with_default "DOMAIN" "Enter your domain (e.g., example.com):"
done

prompt_with_default "EMAIL" "Enter your email address (for Let's Encrypt):"
while [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; do
    echo -e "${RED}Invalid email format. Please enter a valid email address.${NC}"
    prompt_with_default "EMAIL" "Enter your email address (for Let's Encrypt):"
done

# Database Configuration
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$(generate_random_string 32)}
NEO4J_PASSWORD=${NEO4J_PASSWORD:-$(generate_random_string 32)}

# Authentication
JWT_SECRET=${JWT_SECRET:-$(generate_random_string 64)}
ANON_KEY=${ANON_KEY:-$(generate_random_string 64)}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY:-$(generate_random_string 64)}

# MinIO Configuration
MINIO_ROOT_USER=${MINIO_ROOT_USER:-$(openssl rand -hex 8)}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-$(generate_random_string 32)}

# Admin Passwords
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-$(generate_random_string 16)}
N8N_ADMIN_PASSWORD=${N8N_ADMIN_PASSWORD:-$(generate_random_string 16)}
FLOWISE_ADMIN_PASSWORD=${FLOWISE_ADMIN_PASSWORD:-$(generate_random_string 16)}

# Save configuration
cat > "$ENV_FILE" << EOF
# OpenDiscourse Configuration
# Generated on $(date)

# Core Configuration
DOMAIN="$DOMAIN"
EMAIL="$EMAIL"
STACK_DIR="$STACK_DIR"

# Database
POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
NEO4J_PASSWORD="$NEO4J_PASSWORD"

# Authentication
JWT_SECRET="$JWT_SECRET"
ANON_KEY="$ANON_KEY"
SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"

# MinIO
MINIO_ROOT_USER="$MINIO_ROOT_USER"
MINIO_ROOT_PASSWORD="$MINIO_ROOT_PASSWORD"
MINIO_BUCKET_NAME="opendiscourse"

# Traefik
TRAEFIK_HTTP_PORT=80
TRAEFIK_HTTPS_PORT=443
TRAEFIK_AUTH="admin:$(openssl passwd -apr1 "$ADMIN_PASSWORD" 2>/dev/null || echo "admin")"

# Admin Interfaces
GRAFANA_ADMIN_PASSWORD="$GRAFANA_ADMIN_PASSWORD"
N8N_ADMIN_PASSWORD="$N8N_ADMIN_PASSWORD"
FLOWISE_ADMIN_PASSWORD="$FLOWISE_ADMIN_PASSWORD"

# LocalAI Configuration
LOCALAI_API_KEY="$(generate_random_string 64)"

# Redis Configuration (for monitoring)
REDIS_PASSWORD="$(generate_random_string 32)"

# Backup Configuration
BACKUP_RETENTION_DAYS=30
EOF

# Set permissions
chmod 600 "$ENV_FILE"
chown "$SUDO_USER:" "$ENV_FILE"

# Create required directories
mkdir -p "$STACK_DIR/{
    data/{postgres,neo4j,weaviate,minio,prometheus,grafana},
    config/{traefik,supabase,localai,n8n,flowise},
    scripts,
    backups,
    logs
}"
chown -R "$SUDO_USER:" "$STACK_DIR"

echo -e "\n${GREEN}Configuration saved to $ENV_FILE${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Review the configuration in $ENV_FILE"
echo "2. Run the installation script: sudo -E ./install.sh"
echo -e "\n${GREEN}Important credentials have been generated and saved. Keep them secure!${NC}"

# Show generated credentials
cat << EOF

${YELLOW}=== Generated Credentials ===${NC}
PostgreSQL Password: $POSTGRES_PASSWORD
Neo4j Password: $NEO4J_PASSWORD
MinIO Access Key: $MINIO_ROOT_USER
MinIO Secret Key: $MINIO_ROOT_PASSWORD
Grafana Admin Password: $GRAFANA_ADMIN_PASSWORD
n8n Admin Password: $N8N_ADMIN_PASSWORD
Flowise Admin Password: $FLOWISE_ADMIN_PASSWORD
${YELLOW}============================${NC}

${RED}IMPORTANT: Save these credentials in a secure password manager!${NC}
EOF

exit 0
