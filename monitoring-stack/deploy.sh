#!/bin/bash

# Exit on error
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Monitoring Stack Deployment ===${NC}"

# Check for required commands
for cmd in docker docker-compose openssl; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is required but not installed."
        exit 1
    fi
done

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}Creating .env file from .env.example...${NC}"
    cp .env.example .env
    echo -e "${GREEN}Please edit the .env file with your configuration and run this script again.${NC}"
    exit 0
fi

# Generate self-signed certificates if they don't exist
if [ ! -f "./certs/cert.pem" ] || [ ! -f "./certs/key.pem" ]; then
    echo -e "${YELLOW}Generating self-signed SSL certificates...${NC}"
    mkdir -p ./certs
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout ./certs/key.pem \
        -out ./certs/cert.pem \
        -subj "/CN=monitoring.local"
fi

# Create required directories
echo -e "${YELLOW}Creating required directories...${NC}"
mkdir -p ./data/grafana
mkdir -p ./data/prometheus
mkdir -p ./data/loki
mkdir -p ./data/opensearch
mkdir -p ./data/rabbitmq
mkdir -p ./backups

# Set proper permissions
echo -e "${YELLOW}Setting permissions...${NC}"
chmod -R 777 ./data
chmod -R 777 ./backups
chmod +x ./backup_scripts/*.sh

# Pull latest images
echo -e "${YELLOW}Pulling latest Docker images...${NC}"
docker-compose pull

# Start services
echo -e "${YELLOW}Starting services...${NC}"
docker-compose up -d

echo -e "\n${GREEN}=== Deployment Complete ===${NC}"
echo -e "Services are starting up. This may take a few minutes."
echo -e "\nAccess the following services:"
echo -e "- Grafana:              http://localhost:3000"
echo -e "- Prometheus:           http://localhost:9090"
echo -e "- RabbitMQ Management:  http://localhost:15672"
echo -e "- OpenSearch:           http://localhost:9200"
echo -e "- AI Orchestrator API:  http://localhost:8000"
echo -e "\nDefault credentials:"
echo -e "- Grafana:              admin / (check .env for password)"
echo -e "- RabbitMQ:             (check .env for credentials)"

echo -e "\n${YELLOW}To stop the stack, run: docker-compose down${NC}"
echo -e "${YELLOW}To view logs, run: docker-compose logs -f${NC}"
