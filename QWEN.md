# OpenDiscourse Project Context

## Project Overview

OpenDiscourse is a comprehensive, containerized platform that provides a full-stack environment for discourse analysis and AI-powered content processing. The project integrates multiple services including databases (PostgreSQL via Supabase self-hosting, Neo4j, Weaviate), AI/ML services (LocalAI, OpenWebUI), workflow automation (n8n, Flowise), object storage (MinIO), and monitoring (Prometheus, Grafana) within a Docker-based deployment orchestrated by Docker Compose and optionally Terraform for cloud deployments.

The platform is designed to process documents, generate embeddings, perform retrieval-augmented generation (RAG), manage knowledge graphs, and provide a complete infrastructure for AI-driven discourse analysis. It now includes a modern web interface built with Next.js and pnpm.

## Key Technologies

- **Containerization**: Docker, Docker Compose
- **Orchestration**: Terraform (for Proxmox deployments)
- **Reverse Proxy**: Traefik
- **Databases**: 
  - PostgreSQL (via Supabase self-hosting)
  - Neo4j (Graph Database)
  - Weaviate (Vector Database)
  - MinIO (Object Storage)
- **Authentication**: Supabase Auth, OAuth2 Proxy
- **AI/ML Services**: LocalAI, OpenWebUI, Flowise
- **Workflow Automation**: n8n
- **Monitoring**: Prometheus, Grafana, cAdvisor
- **Frontend**: Next.js with React and Tailwind CSS
- **Package Management**: pnpm
- **Scripting**: Bash, Python

## Project Structure

The repository contains deployment scripts for different environments, configuration files, and documentation:

- `deploy_proxmox.sh`: Main deployment script for Proxmox VE
- `deploy_remote.sh`: Script for remote server deployment
- `install.sh`: Installation script that sets up the stack directory and core services
- `configure.sh`: Configuration script for environment variables
- `deploy.sh`: Management script for starting/stopping services
- `supabase-docker/`: Supabase self-hosting Docker setup
- `nextjs/`: Next.js web application
- `scripts/`: Utility scripts for deployment and management
- `README.md`, `DEPLOYMENT_GUIDE.md`: Documentation
- `AGENTS.md`: Details about the agent-based architecture
- `TASKS.md`: Information about task definitions and workflows

## Building and Running

### Prerequisites

- Docker and Docker Compose
- Git
- curl, jq
- Node.js >= 18.17.0
- pnpm package manager
- For Proxmox deployment: Terraform, SSH tools

### Deployment Process

1.  **One-Click Deployment** (Recommended):
    - Run `./scripts/one-click-deploy.sh`
    - This script will deploy Supabase services and set up the Next.js application.

2.  **Supabase Self-Hosting**:
    - Run `./scripts/deploy-supabase.sh start`
    - This script manages the Supabase Docker Compose deployment.

3.  **Next.js Application Setup**:
    - Run `./scripts/setup-nextjs.sh setup`
    - This script installs dependencies and configures the Next.js application.

4.  **Proxmox Deployment**:
    - Run `./deploy_proxmox.sh`
    - This script uses Terraform to create a VM, installs dependencies, and deploys the full stack.

5.  **Remote Server Deployment**:
    - Run `./deploy_remote.sh` with appropriate parameters (`--ip`, `--domain`, `--email`).
    - This script copies necessary files to a remote server and executes the installation and deployment.

6.  **Manual Deployment**:
    - Run `sudo -E ./install.sh` to install and configure the stack.
    - Run `sudo -E ./deploy.sh start` to start the services.

### Management Commands

#### Supabase Management (via `scripts/deploy-supabase.sh`)

- `./scripts/deploy-supabase.sh start`: Start Supabase services
- `./scripts/deploy-supabase.sh stop`: Stop Supabase services
- `./scripts/deploy-supabase.sh restart`: Restart Supabase services
- `./scripts/deploy-supabase.sh status`: Show service status
- `./scripts/deploy-supabase.sh logs`: Show service logs

#### Next.js Management (via `scripts/setup-nextjs.sh`)

- `./scripts/setup-nextjs.sh setup`: Set up the Next.js application
- `./scripts/setup-nextjs.sh build`: Build the Next.js application
- `./scripts/setup-nextjs.sh dev`: Start the development server

#### Legacy Management (via `deploy.sh`)

- `./deploy.sh start`: Start all services
- `./deploy.sh stop`: Stop all services
- `./deploy.sh restart`: Restart all services
- `./deploy.sh status`: Show service status
- `./deploy.sh update`: Update to the latest version
- `./deploy.sh backup`: Create a backup of all data

## Development Conventions

- Bash scripts follow strict error handling (`set -euo pipefail`)
- Configuration is managed through environment variables in `.env` files
- Services are defined in `docker-compose.yml` with appropriate labels for Traefik routing
- Scripts use colored output for better visibility
- All services run in isolated Docker networks
- Data persistence is managed through Docker volumes
- Security considerations include generating strong random passwords and using secure configurations for services
- Next.js application follows modern React development practices with Server Components
- Supabase integration uses the official Supabase JavaScript client libraries

## Key Services and Access Points

After deployment, the following services are accessible:

### Supabase Services
- Supabase Studio: http://localhost:3000
- Supabase API: http://localhost:8000
  - REST API: http://localhost:8000/rest/v1/
  - Auth API: http://localhost:8000/auth/v1/
  - Storage API: http://localhost:8000/storage/v1/
  - Realtime API: http://localhost:8000/realtime/v1/

### Next.js Application
- Development server: http://localhost:3001
- Production build: http://localhost:3002 (after deployment)

### Legacy Services (if using deploy.sh)
These services are accessible via subdomains:
- Dashboard: https://yourdomain.com
- Supabase Studio: https://supabase.yourdomain.com
- Neo4j Browser: https://neo4j.yourdomain.com
- Weaviate Console: https://weaviate.yourdomain.com
- MinIO Console: https://minio.yourdomain.com
- LocalAI: https://localai.yourdomain.com
- OpenWebUI (Chat): https://chat.yourdomain.com
- n8n (Workflow): https://n8n.yourdomain.com
- Flowise: https://flowise.yourdomain.com
- Grafana: https://grafana.yourdomain.com