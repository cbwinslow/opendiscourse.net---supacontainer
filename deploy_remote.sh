#!/bin/bash
set -euo pipefail

# =============================================================================
# OpenDiscourse Remote Deployment Script
# =============================================================================
# This script deploys OpenDiscourse to a remote server via SSH

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
REMOTE_USER="root"
REMOTE_IP=""
SSH_KEY=""
DOMAIN=""
EMAIL=""
GITHUB_CLIENT_ID=""
GITHUB_CLIENT_SECRET=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user=*)
            REMOTE_USER="${1#*=}"
            shift
            ;;
        --ip=*)
            REMOTE_IP="${1#*=}"
            shift
            ;;
        --ssh-key=*)
            SSH_KEY="-i ${1#*=}"
            shift
            ;;
        --domain=*)
            DOMAIN="${1#*=}"
            shift
            ;;
        --email=*)
            EMAIL="${1#*=}"
            shift
            ;;
        --github-client-id=*)
            GITHUB_CLIENT_ID="${1#*=}"
            shift
            ;;
        --github-client-secret=*)
            GITHUB_CLIENT_SECRET="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$REMOTE_IP" || -z "$DOMAIN" || -z "$EMAIL" ]]; then
    echo -e "${RED}Error: Missing required parameters${NC}"
    echo "Usage: $0 --ip=REMOTE_IP --domain=DOMAIN --email=EMAIL [--user=USER] [--ssh-key=KEY_PATH] [--github-client-id=ID] [--github-client-secret=SECRET]"
    exit 1
fi

# Function to execute command on remote server
remote_exec() {
    echo -e "${YELLOW}Executing: $1${NC}"
    ssh -o StrictHostKeyChecking=no $SSH_KEY "$REMOTE_USER@$REMOTE_IP" "$1"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error executing command: $1${NC}"
        exit 1
    fi
}

# Function to copy files to remote server
remote_copy() {
    echo -e "${YELLOW}Copying $1 to $REMOTE_IP:${2:-.}${NC}"
    scp -r $SSH_KEY "$1" "$REMOTE_USER@$REMOTE_IP:${2:-.}"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error copying file: $1${NC}"
        exit 1
    fi
}

# Start deployment
echo -e "${GREEN}Starting OpenDiscourse deployment to $REMOTE_IP${NC}"

# 1. Install required dependencies on remote server
echo -e "${GREEN}Installing dependencies on remote server...${NC}"
remote_exec "apt-get update && apt-get install -y git curl jq"

# 2. Clone the repository on remote server
echo -e "${GREEN}Cloning OpenDiscourse repository...${NC}"
remote_exec "rm -rf /tmp/opendiscourse && git clone https://github.com/yourusername/opendiscourse.git /tmp/opendiscourse"

# 3. Copy necessary files
remote_copy "install.sh" "/tmp/opendiscourse/"
remote_copy "deploy.sh" "/tmp/opendiscourse/"
remote_copy "configure.sh" "/tmp/opendiscourse/"
remote_copy "deploy/generate_supabase_keys.sh" "/tmp/opendiscourse/deploy/"
remote_copy "deploy/setup_supabase.sh" "/tmp/opendiscourse/deploy/"

# 4. Create environment file on remote
remote_exec "cat > /tmp/opendiscourse/.env << EOL
DOMAIN=$DOMAIN
EMAIL=$EMAIL
GITHUB_CLIENT_ID=$GITHUB_CLIENT_ID
GITHUB_CLIENT_SECRET=$GITHUB_CLIENT_SECRET
EOL"

# 5. Make scripts executable
remote_exec "chmod +x /tmp/opendiscourse/*.sh /tmp/opendiscourse/deploy/*.sh"

# 6. Run configuration
remote_exec "cd /tmp/opendiscourse && ./configure.sh"

# 7. Run installation
remote_exec "cd /tmp/opendiscourse && ./install.sh"

# 8. Start services
remote_exec "cd /tmp/opendiscourse && ./deploy.sh start"

# 9. Display completion message
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${YELLOW}Access the following services:${NC}"
echo -e "- Dashboard: https://$DOMAIN"
echo -e "- Supabase Studio: https://supabase.$DOMAIN"
echo -e "- Neo4j Browser: https://neo4j.$DOMAIN"
echo -e "- Weaviate Console: https://weaviate.$DOMAIN"
echo -e "- MinIO Console: https://minio.$DOMAIN"
echo -e "- LocalAI: https://localai.$DOMAIN"
echo -e "- OpenWebUI: https://chat.$DOMAIN"
echo -e "- n8n: https://n8n.$DOMAIN"
echo -e "- Flowise: https://flowise.$DOMAIN"
echo -e "- Grafana: https://grafana.$DOMAIN (admin/password from .env)"
