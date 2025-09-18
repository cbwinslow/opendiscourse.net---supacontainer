# OpenDiscourse Deployment Guide

This guide covers the deployment of OpenDiscourse with Supabase self-hosting and Next.js frontend.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deployment Options](#deployment-options)
- [One-Click Deployment](#one-click-deployment)
- [Manual Deployment](#manual-deployment)
- [Supabase Self-Hosting](#supabase-self-hosting)
- [Next.js Application](#nextjs-application)
- [Configuration](#configuration)
- [Accessing Services](#accessing-services)
- [Troubleshooting](#troubleshooting)

## Prerequisites

Before deploying OpenDiscourse, ensure you have the following installed:

- **Docker** and **Docker Compose**
- **Node.js** >= 18.17.0
- **pnpm** package manager
- **Git**
- **curl** and **jq**
- At least **4GB RAM** and **2 CPU cores** for Supabase services

For cloud deployments:
- **Terraform** (for Proxmox VE)
- **SSH tools**

## Deployment Options

OpenDiscourse offers several deployment options:

1. **One-Click Deployment**: Deploy the entire platform with a single command
2. **Supabase Only**: Deploy only the Supabase backend services
3. **Next.js Only**: Deploy only the Next.js frontend application
4. **Legacy Deployment**: Use the original deployment scripts

## One-Click Deployment

The recommended way to deploy OpenDiscourse is using the one-click deployment script:

```bash
# Clone the repository
git clone https://github.com/yourorg/opendiscourse.git
cd opendiscourse

# Run one-click deployment
./scripts/one-click-deploy.sh
```

This script will:
1. Check all prerequisites
2. Deploy Supabase services using Docker Compose
3. Set up the Next.js application
4. Build the Next.js application
5. Show deployment status and access information

After deployment, you can access:
- **Supabase Studio**: http://localhost:3000
- **Next.js Application**: http://localhost:3001 (development server)

## Manual Deployment

If you prefer to deploy services manually, follow these steps:

### 1. Deploy Supabase Services

```bash
# Generate secure environment variables
python3 scripts/generate_supabase_env.py --output supabase-docker/.env --force

# Start Supabase services
./scripts/deploy-supabase.sh start

# Check service status
./scripts/deploy-supabase.sh status
```

### 2. Set Up Next.js Application

```bash
# Install dependencies and configure the application
./scripts/setup-nextjs.sh setup

# Start development server
./scripts/setup-nextjs.sh dev
```

## Supabase Self-Hosting

OpenDiscourse uses Supabase self-hosting for backend services. The deployment includes:

- **PostgreSQL Database**: Core database with required extensions
- **Authentication Service**: User management and JWT token issuance
- **REST API**: RESTful interface for database operations
- **Realtime Service**: WebSocket server for live updates
- **Storage Service**: File storage with S3-compatible API
- **Studio**: Web-based dashboard for management
- **Supavisor**: Connection pooler for database connections

### Supabase Deployment Commands

```bash
# Start Supabase services
./scripts/deploy-supabase.sh start

# Stop Supabase services
./scripts/deploy-supabase.sh stop

# Restart Supabase services
./scripts/deploy-supabase.sh restart

# Check service status
./scripts/deploy-supabase.sh status

# View service logs
./scripts/deploy-supabase.sh logs
```

### Supabase Environment Variables

The Supabase deployment uses a `.env` file for configuration. The platform includes a script to generate secure environment variables:

```bash
python3 scripts/generate_supabase_env.py --output supabase-docker/.env --force
```

This generates:
- Secure database passwords
- JWT secrets
- API keys
- Service configuration

## Next.js Application

The frontend is built with Next.js and includes:

- **Authentication**: Integrated Supabase auth with session management
- **Responsive UI**: Mobile-friendly interface using Tailwind CSS
- **User Management**: Account pages for profile management
- **Modern Development**: TypeScript, ESLint, and Prettier

### Next.js Setup Commands

```bash
# Set up the Next.js application (install dependencies, create .env.local)
./scripts/setup-nextjs.sh setup

# Build the Next.js application
./scripts/setup-nextjs.sh build

# Start the development server
./scripts/setup-nextjs.sh dev
```

### Next.js Development

For active development:

```bash
# Navigate to the Next.js directory
cd nextjs

# Install dependencies
pnpm install

# Start development server
pnpm run dev

# Build for production
pnpm run build

# Start production server
pnpm run start
```

## Configuration

### Environment Variables

#### Supabase Configuration

The `supabase-docker/.env` file contains all Supabase configuration:

```bash
# Database
POSTGRES_PASSWORD=your-super-secret-password
POSTGRES_HOST=db
POSTGRES_DB=postgres
POSTGRES_PORT=5432

# Security
JWT_SECRET=your-super-secret-jwt-token
ANON_KEY=your-public-anon-key
SERVICE_ROLE_KEY=your-service-role-key

# Studio
DASHBOARD_USERNAME=supabase
DASHBOARD_PASSWORD=your-dashboard-password
```

#### Next.js Configuration

The `nextjs/.env.local` file contains Next.js configuration:

```bash
NEXT_PUBLIC_SUPABASE_URL=http://localhost:8000
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
```

### Generating Secure Configuration

Use the provided scripts to generate secure environment variables:

```bash
# Generate Supabase .env file
python3 scripts/generate_supabase_env.py --output supabase-docker/.env --force

# Generate application .env file
python3 scripts/generate_env.py --domain opendiscourse.net --email blaine.winslow@gmail.com --force
```

## Accessing Services

After deployment, the following services will be available:

### Supabase Services

- **Studio Dashboard**: http://localhost:3000
- **REST API**: http://localhost:8000/rest/v1/
- **Auth API**: http://localhost:8000/auth/v1/
- **Storage API**: http://localhost:8000/storage/v1/
- **Realtime API**: http://localhost:8000/realtime/v1/

### Next.js Application

- **Development Server**: http://localhost:3001
- **Production Build**: http://localhost:3002 (after deployment)

## Troubleshooting

### Common Issues

#### Supabase Services Not Starting

1. Check Docker and Docker Compose installation:
   ```bash
   docker --version
   docker-compose --version
   ```

2. Verify environment variables in `supabase-docker/.env`

3. Check available system resources:
   ```bash
   free -h
   nproc
   ```

4. Review logs:
   ```bash
   ./scripts/deploy-supabase.sh logs
   ```

#### Next.js Development Server Not Starting

1. Ensure Node.js and pnpm are installed:
   ```bash
   node --version
   pnpm --version
   ```

2. Check dependencies:
   ```bash
   cd nextjs
   pnpm install
   ```

3. Verify environment variables in `nextjs/.env.local`

4. Check for port conflicts:
   ```bash
   lsof -i :3001
   ```

#### Authentication Issues

1. Verify Supabase ANON_KEY and SERVICE_ROLE_KEY match between services

2. Check JWT_SECRET consistency:
   ```bash
   grep JWT_SECRET supabase-docker/.env
   ```

3. Ensure user has proper permissions in Supabase Studio

#### Database Connection Issues

1. Verify PostgreSQL is accessible:
   ```bash
   docker-compose -f supabase-docker/docker-compose.yml exec db pg_isready
   ```

2. Check database credentials in `supabase-docker/.env`

3. Ensure required database extensions are installed

### Getting Help

For additional support:
1. Check the logs for error messages
2. Review the documentation
3. Open an issue on our [GitHub repository](https://github.com/yourorg/opendiscourse/issues)

### Log Files

Log files are stored in the `logs/` directory:
- `supabase-deploy.log`: Supabase deployment logs
- `nextjs-setup.log`: Next.js setup logs
- `one-click-deploy.log`: One-click deployment logs

View logs:
```bash
tail -f logs/supabase-deploy.log
```