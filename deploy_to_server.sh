#!/bin/bash

# Configuration
SERVER_IP="95.217.106.172"
DOMAIN="opendiscourse.net"
EMAIL="blaine.winslow@gmail.com"
CF_TOKEN="TBgXhv6-N0zK1i_ypolqA_ThcAzreP9hR3tQ_Byy"
STACK_DIR="/opt/opendiscourse"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to run commands with error handling
run_ssh() {
    echo -e "${YELLOW}Running:${NC} $1"
    ssh -o "StrictHostKeyChecking=no" root@$SERVER_IP "$1"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error executing command: $1${NC}"
        exit 1
    fi
}

# Function to transfer files
transfer_file() {
    local src=$1
    local dest=$2
    echo -e "${YELLOW}Transferring $src to $SERVER_IP:$dest${NC}"
    scp -o "StrictHostKeyChecking=no" "$src" "root@$SERVER_IP:$dest"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error transferring file: $src${NC}"
        exit 1
    fi
}

# Check if SSH key exists, generate if not
if [ ! -f ~/.ssh/id_ed25519 ]; then
    echo -e "${YELLOW}Generating SSH key...${NC}"
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
    echo -e "${YELLOW}Please add the following public key to $SERVER_IP:/root/.ssh/authorized_keys:${NC}"
    cat ~/.ssh/id_ed25519.pub
    echo -e "${YELLOW}Press Enter to continue after adding the key...${NC}"
    read -r
fi

# Test SSH connection
echo -e "${YELLOW}Testing SSH connection...${NC}"
if ! ssh -o "StrictHostKeyChecking=no" -q root@$SERVER_IP exit; then
    echo -e "${RED}SSH connection failed. Please ensure you can connect to the server as root.${NC}"
    exit 1
fi

# Update the system and install prerequisites
echo -e "${YELLOW}Updating system and installing prerequisites...${NC}"
run_ssh "apt-get update && apt-get upgrade -y"
run_ssh "apt-get install -y curl git jq unzip"

# Install Docker if not installed
echo -e "${YELLOW}Installing Docker...${NC}"
run_ssh "if ! command -v docker &> /dev/null; then curl -fsSL https://get.docker.com | sh; fi"
run_ssh "systemctl enable --now docker"
run_ssh "usermod -aG docker $USER || true"

# Create directory structure
echo -e "${YELLOW}Creating directory structure...${NC}"
run_ssh "mkdir -p $STACK_DIR/{letsencrypt,traefik,services/{rag-api,graphrag-api,admin-portal,pdf-worker},monitoring,scripts,tests/api,tests/k6,data/inbox,supabase}"
run_ssh "chmod 700 $STACK_DIR/letsencrypt"
run_ssh "touch $STACK_DIR/letsencrypt/acme.json && chmod 600 $STACK_DIR/letsencrypt/acme.json"
run_ssh "chmod 755 $STACK_DIR/data $STACK_DIR/data/inbox"

# Copy the installation files
echo -e "${YELLOW}Copying installation files...${NC}"
transfer_file "opendiscourse_install.sh" "/tmp/opendiscourse_install.sh"
run_ssh "chmod +x /tmp/opendiscourse_install.sh"

# Run the installation script
echo -e "${YELLOW}Running OpenDiscourse installation...${NC}"
run_ssh "cd /tmp && DOMAIN=$DOMAIN EMAIL=$EMAIL CF_TOKEN=$CF_TOKEN STACK_DIR=$STACK_DIR \
  ./opendiscourse_install.sh --domain $DOMAIN --email $EMAIL --cf-token '$CF_TOKEN' --non-interactive"

# Start the services
echo -e "${YELLOW}Starting OpenDiscourse services...${NC}"
run_ssh "cd $STACK_DIR && docker compose up -d"

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Configure DNS records in Cloudflare to point to $SERVER_IP"
echo "2. Access the admin panel at: https://admin.$DOMAIN"
echo "3. Check service status with: ssh root@$SERVER_IP 'cd $STACK_DIR && docker compose ps'"
