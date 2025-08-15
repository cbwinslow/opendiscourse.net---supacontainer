# Self-Hosted Supabase for Monitoring Stack

This directory contains the configuration and scripts for running a self-hosted Supabase instance that serves as the backend for the monitoring stack.

## Features

- **Complete Supabase Stack**: Includes PostgreSQL, Auth, Storage, and Realtime
- **Database Schema**: Pre-configured with tables for agents, capabilities, resources, and metrics
- **Row Level Security**: Secure by default with proper RLS policies
- **Backup & Restore**: Scripts for backing up and restoring your data
- **Monitoring**: Tools to monitor the health and performance of your Supabase instance
- **Time-Series Data**: Optimized for time-series metrics with TimescaleDB

## Prerequisites

- Docker and Docker Compose
- At least 4GB of RAM (8GB recommended)
- At least 20GB of free disk space

## Quick Start

1. **Initialize the environment**:
   ```bash
   # Make the setup script executable
   chmod +x scripts/setup_supabase.sh
   
   # Run the setup script
   ./scripts/setup_supabase.sh
   
   # This will create a .env file with generated secrets
   # Review and edit the .env file if needed
   ```

2. **Start the services**:
   ```bash
   docker-compose -f docker-compose.supabase.yml up -d
   ```

3. **Access the services**:
   - **Supabase Studio**: http://localhost:3000
   - **API**: http://localhost:8000
   - **Database**: localhost:5432

## Database Schema

### Tables

#### `agents`
- `id`: UUID (primary key)
- `name`: Text
- `description`: Text (nullable)
- `status`: Text (default: 'offline')
- `last_seen_at`: Timestamp (nullable)
- `created_at`: Timestamp
- `updated_at`: Timestamp
- `metadata`: JSONB (for custom fields)

#### `agent_capabilities`
- `id`: UUID (primary key)
- `agent_id`: UUID (foreign key to agents.id)
- `name`: Text
- `description`: Text (nullable)
- `parameters`: JSONB (for capability-specific settings)
- `is_active`: Boolean (default: true)
- `created_at`: Timestamp
- `updated_at`: Timestamp

#### `agent_resources`
- `id`: UUID (primary key)
- `agent_id`: UUID (foreign key to agents.id)
- `name`: Text
- `description`: Text (nullable)
- `type`: Enum ('cpu', 'gpu', 'memory', 'storage', 'network')
- `capacity`: Float
- `used`: Float (default: 0)
- `unit`: Text
- `is_available`: Boolean (default: true)
- `created_at`: Timestamp
- `updated_at`: Timestamp

#### `agent_metrics`
- `id`: UUID (primary key)
- `agent_id`: UUID (foreign key to agents.id)
- `name`: Text
- `type`: Enum ('gauge', 'counter', 'histogram', 'summary')
- `value`: Float
- `timestamp`: Timestamp (default: now())
- `labels`: JSONB (for additional dimensions)
- `created_at`: Timestamp

## API Endpoints

### Authentication
- `POST /auth/v1/token` - Get JWT token
- `POST /auth/v1/signup` - Create a new user
- `GET /auth/v1/user` - Get current user

### REST API
- `GET /rest/v1/agents` - List all agents
- `GET /rest/v1/agents?select=*` - Get all agent details
- `POST /rest/v1/agents` - Create a new agent
- `GET /rest/v1/agent_metrics?agent_id=eq.<UUID>&select=*` - Get metrics for an agent

### Storage API
- `POST /storage/v1/bucket` - Create a new bucket
- `POST /storage/v1/upload/<bucket>` - Upload a file
- `GET /storage/v1/bucket/<bucket>` - List files in a bucket

## Backup and Restore

### Create a backup
```bash
# Make the backup script executable
chmod +x scripts/backup_supabase.sh

# Run the backup script
./scripts/backup_supabase.sh
```

### Restore from backup
```bash
# Stop the services
docker-compose -f docker-compose.supabase.yml down

# Restore the database
zcat backups/supabase_backup_*.sql.gz | docker exec -i supabase_db psql -U postgres

# Restart the services
docker-compose -f docker-compose.supabase.yml up -d
```

## Monitoring

### Run the monitoring script
```bash
# Install required Python packages
pip install -r requirements-supabase.txt

# Run the monitor
python scripts/monitor_supabase.py
```

### Example output
```json
{
  "timestamp": "2025-08-15T21:27:04.123456",
  "services": {
    "database": {
      "status": "healthy",
      "latency_ms": 12.34
    },
    "rest_api": {
      "status": "healthy",
      "status_code": 200,
      "latency_ms": 45.67
    },
    "auth_api": {
      "status": "healthy",
      "status_code": 200,
      "latency_ms": 34.56
    }
  },
  "metrics": {
    "database": {
      "status": "success",
      "database_size": "45.2 MB",
      "active_connections": 12,
      "table_sizes": [
        {"schema": "public", "table": "agent_metrics", "size": "25.1 MB"},
        {"schema": "public", "table": "agents", "size": "15.3 MB"},
        {"schema": "public", "table": "agent_resources", "size": "4.2 MB"},
        {"schema": "public", "table": "agent_capabilities", "size": "0.6 MB"}
      ],
      "long_running_queries": []
    },
    "storage": {
      "status": "success",
      "buckets": [
        {
          "name": "agent-data",
          "objects": 42,
          "size": 12345678,
          "size_formatted": "11.77 MB"
        }
      ]
    }
  },
  "status": "healthy"
}
```

## Security Considerations

1. **Secrets Management**:
   - Never commit the `.env` file to version control
   - Rotate the `JWT_SECRET`, `ANON_KEY`, and `SERVICE_ROLE_KEY` regularly
   - Use environment variables or a secrets manager in production

2. **Network Security**:
   - Expose only necessary ports to the internet
   - Use a reverse proxy with HTTPS (e.g., Nginx, Traefik)
   - Consider using a VPN for database access

3. **Backup Strategy**:
   - Set up regular automated backups
   - Test restore procedures regularly
   - Store backups in a secure, off-site location

## Troubleshooting

### Common Issues

1. **Port Conflicts**:
   - If ports 3000, 5432, or 8000 are already in use, update the ports in `docker-compose.supabase.yml`

2. **Permission Issues**:
   - If you see permission errors, ensure the Docker user has write access to mounted volumes:
     ```bash
     sudo chown -R $USER:$USER ./supabase
     ```

3. **Out of Memory**:
   - If containers are crashing, increase Docker's memory allocation
   - Adjust PostgreSQL's `shared_buffers` and `work_mem` in `docker-compose.supabase.yml`

### Viewing Logs
```bash
# View all logs
docker-compose -f docker-compose.supabase.yml logs -f

# View database logs
docker logs -f supabase_db

# View API logs
docker logs -f supabase_rest
```

## Scaling

### Vertical Scaling
- Increase CPU/memory allocation in `docker-compose.supabase.yml`
- Adjust PostgreSQL configuration for better performance

### Horizontal Scaling
- Set up read replicas for PostgreSQL
- Use connection pooling (e.g., PgBouncer)
- Consider separating services across multiple machines

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
