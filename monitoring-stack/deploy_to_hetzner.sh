#!/bin/bash

# Exit on error
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Version
VERSION="1.0.0"

# Server details
SERVER_IP="95.217.106.172"
REMOTE_USER="root"
REMOTE_DIR="/root/monitoring-stack"

# Check if SSH key exists, generate if not
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    echo -e "${YELLOW}Generating SSH key pair...${NC}"
    ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
    echo -e "${GREEN}SSH key generated at $HOME/.ssh/id_rsa${NC}"
fi

# Copy public key to server if not already present
echo -e "${YELLOW}Setting up SSH access to ${SERVER_IP}...${NC}"
ssh-copy-id -i "$HOME/.ssh/id_rsa.pub" "${REMOTE_USER}@${SERVER_IP}"

# Create remote directory
echo -e "${YELLOW}Creating remote directory...${NC}"
ssh "${REMOTE_USER}@${SERVER_IP}" "mkdir -p ${REMOTE_DIR}/backup_scripts"

# Copy necessary files
echo -e "${YELLOW}Copying files to server...${NC}"
scp -r ./* "${REMOTE_USER}@${SERVER_IP}:${REMOTE_DIR}/"
scp -r ./backup_scripts/* "${REMOTE_USER}@${SERVER_IP}:${REMOTE_DIR}/backup_scripts/"

# Make scripts executable on remote server
echo -e "${YELLOW}Setting up permissions...${NC}"
ssh "${REMOTE_USER}@${SERVER_IP}" "chmod +x ${REMOTE_DIR}/*.sh"
ssh "${REMOTE_USER}@${SERVER_IP}" "chmod +x ${REMOTE_DIR}/backup_scripts/*.sh"

# Install Docker and dependencies
echo -e "${YELLOW}Installing Docker and dependencies...${NC}"
ssh "${REMOTE_USER}@${SERVER_IP}" "
    # Update package lists
    apt-get update -y
    
    # Install required packages
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Set up the stable repository
    echo \
        "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
"

# Copy .env.example to .env if it doesn't exist
echo -e "${YELLOW}Setting up environment...${NC}"
ssh "${REMOTE_USER}@${SERVER_IP}" "
    cd ${REMOTE_DIR}
    if [ ! -f .env ]; then
        cp .env.example .env
        echo -e "${YELLOW}Please edit the .env file with your configuration.${NC}"
    fi
"

# Install security tools
echo -e "${YELLOW}Installing security tools...${NC}"
scp install_security_tools.sh "${REMOTE_USER}@${SERVER_IP}:${REMOTE_DIR}/"
ssh "${REMOTE_USER}@${SERVER_IP}" "cd ${REMOTE_DIR} && chmod +x install_security_tools.sh && ./install_security_tools.sh"

# Start the monitoring stack
echo -e "${YELLOW}Starting monitoring stack...${NC}"
ssh "${REMOTE_USER}@${SERVER_IP}" "
    cd ${REMOTE_DIR}
    docker-compose up -d
"

# Generate documentation
echo -e "\n${BLUE}=== Generating Documentation ===${NC}"
./scripts/generate_api_docs.sh

# Set permissions for documentation
chmod -R 755 docs/
chown -R ${REMOTE_USER}:${REMOTE_USER} docs/

# Generate initial credentials file if it doesn't exist
if [ ! -f "credentials.env" ]; then
    echo -e "\n${YELLOW}Generating initial credentials...${NC}"
    cat > credentials.env << EOL
# Auto-generated credentials - KEEP THIS FILE SECURE
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
RABBITMQ_DEFAULT_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
OPENSEARCH_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
AI_ORCHESTRATOR_API_KEY=$(uuidgen)
EOL
    
    echo -e "${GREEN}Generated credentials saved to credentials.env${NC}"
    echo -e "${YELLOW}IMPORTANT: Backup this file in a secure location!${NC}"
fi

# Create a deployment summary
DEPLOYMENT_SUMMARY="deployment_summary_$(date +%Y%m%d_%H%M%S).txt"
{
    echo "=== OpenDiscourse Monitoring Stack Deployment Summary ==="
    echo "Deployment Time: $(date)"
    echo "Version: ${VERSION}"
    echo "Server: ${SERVER_IP}"
    echo ""
    echo "=== Service URLs ==="
    echo "- Cockpit:              http://${SERVER_IP}:9090"
    echo "- ntopng:               http://${SERVER_IP}:3001"
    echo "- Grafana:              http://${SERVER_IP}:3000"
    echo "- Prometheus:           http://${SERVER_IP}:9090"
    echo "- RabbitMQ Management:  http://${SERVER_IP}:15672"
    echo "- OpenSearch:           http://${SERVER_IP}:9200"
    echo "- AI Orchestrator API:  http://${SERVER_IP}:8000"
    echo ""
    echo "=== Credentials ==="
    echo "Grafana Admin: admin / $(grep GRAFANA_ADMIN_PASSWORD credentials.env | cut -d '=' -f2)"
    echo "RabbitMQ: guest / $(grep RABBITMQ_DEFAULT_PASS credentials.env | cut -d '=' -f2)"
    echo "OpenSearch: admin / $(grep OPENSEARCH_PASSWORD credentials.env | cut -d '=' -f2)"
    echo "API Key: $(grep AI_ORCHESTRATOR_API_KEY credentials.env | cut -d '=' -f2)"
    echo ""
    echo "=== Next Steps ==="
    echo "1. SSH into the server: ssh root@${SERVER_IP}"
    echo "2. Review the security check report: /usr/local/bin/security-check"
    echo "3. Configure Cloudflare WAF by running: cloudflared tunnel login"
    echo "4. Create a tunnel: cloudflared tunnel create monitoring-tunnel"
    echo "5. Configure the tunnel with your domain and start it"
    echo "6. Change all default passwords immediately"
    echo ""
    echo "=== Maintenance Commands ==="
    echo "To stop the stack: docker-compose down"
    echo "To view logs: docker-compose logs -f"
    echo "To update: git pull && docker-compose up -d --build"
    echo "To back up: ./backup_scripts/backup.sh"
} > "${DEPLOYMENT_SUMMARY}"

# Secure the credentials file
chmod 600 credentials.env
chown ${REMOTE_USER}:${REMOTE_USER} credentials.env

# Display deployment summary
echo -e "\n${GREEN}=== Deployment Complete ===${NC}"
cat "${DEPLOYMENT_SUMMARY}"

echo -e "\n${YELLOW}Deployment summary saved to: ${DEPLOYMENT_SUMMARY}${NC}"
echo -e "${RED}IMPORTANT: Backup the credentials.env file and keep it secure!${NC}"
