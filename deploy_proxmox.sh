#!/bin/bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check for required commands
for cmd in terraform ssh-keygen ssh-keyscan ssh-copy-id; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd is required but not installed.${NC}"
        exit 1
    fi
done

# Load configuration
if [ ! -f "terraform/proxmox/terraform.tfvars" ]; then
    echo -e "${YELLOW}Creating terraform.tfvars from example...${NC}"
    cp terraform/proxmox/terraform.tfvars.example terraform/proxmox/terraform.tfvars
    echo -e "${YELLOW}Please edit terraform/proxmox/terraform.tfvars with your configuration and run this script again.${NC}"
    exit 1
fi

# Generate SSH key if it doesn't exist
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    echo -e "${YELLOW}Generating SSH key...${NC}"
    ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
    chmod 600 "$HOME/.ssh/id_rsa"
    chmod 644 "$HOME/.ssh/id_rsa.pub"
fi

# Initialize Terraform
cd terraform/proxmox
echo -e "${GREEN}Initializing Terraform...${NC}"
terraform init

# Apply Terraform configuration
echo -e "${GREEN}Creating Proxmox VM...${NC}"
terraform apply -auto-approve

# Get VM IP from Terraform output
VM_IP=$(terraform output -raw vm_ip)
VM_USER=$(terraform output -raw vm_username)

# Wait for VM to be ready
echo -e "${YELLOW}Waiting for VM to be ready...${NC}"
until nc -z $VM_IP 22; do
    sleep 5
done

# Add VM to known hosts
echo -e "${YELLOW}Adding VM to known hosts...${NC}"
ssh-keyscan -H $VM_IP >> ~/.ssh/known_hosts

# Copy SSH key to VM
echo -e "${YELLOW}Copying SSH key to VM...${NC}"
ssh-copy-id -i ~/.ssh/id_rsa.pub $VM_USER@$VM_IP

# Install required packages on VM
echo -e "${GREEN}Installing required packages on VM...${NC}"
ssh $VM_USER@$VM_IP "sudo apt-get update && sudo apt-get install -y git curl jq docker.io docker-compose"

# Clone OpenDiscourse repository
echo -e "${GREEN}Cloning OpenDiscourse repository...${NC}"
ssh $VM_USER@$VM_IP "rm -rf /tmp/opendiscourse && git clone https://github.com/yourusername/opendiscourse.git /tmp/opendiscourse"

# Copy deployment files
echo -e "${GREEN}Copying deployment files...${NC}"
scp -r ../.. $VM_USER@$VM_IP:/tmp/opendiscourse

# Run deployment
echo -e "${GREEN}Starting OpenDiscourse deployment...${NC}"
ssh $VM_USER@$VM_IP "cd /tmp/opendiscourse && sudo ./deploy_remote.sh --ip=$VM_IP --domain=opendiscourse.net --email=admin@opendiscourse.net"

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${YELLOW}Access the following services:${NC}"
echo -e "- Dashboard: https://opendiscourse.net"
echo -e "- Supabase Studio: https://supabase.opendiscourse.net"
echo -e "- Neo4j Browser: https://neo4j.opendiscourse.net"
echo -e "- Weaviate Console: https://weaviate.opendiscourse.net"
echo -e "- MinIO Console: https://minio.opendiscourse.net"
echo -e "- LocalAI: https://localai.opendiscourse.net"
echo -e "- OpenWebUI: https://chat.opendiscourse.net"
echo -e "- n8n: https://n8n.opendiscourse.net"
echo -e "- Flowise: https://flowise.opendiscourse.net"
echo -e "- Grafana: https://grafana.opendiscourse.net"
