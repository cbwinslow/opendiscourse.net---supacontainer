# OpenDiscourse Test Environment Setup

This document describes how to set up the test environment for the OpenDiscourse platform.

## Prerequisites

### System Requirements
- **Operating System**: Linux, macOS, or Windows with WSL2
- **Memory**: Minimum 8GB RAM (16GB recommended)
- **Disk Space**: Minimum 20GB free space
- **CPU**: Minimum 4 cores (8 cores recommended)

### Software Requirements
- **Python**: 3.9 or higher
- **Node.js**: 18.17.0 or higher
- **Docker**: Latest stable version
- **Docker Compose**: Latest stable version
- **Git**: Latest stable version
- **pnpm**: Latest stable version

## Installation Steps

### 1. Clone the Repository
```bash
git clone https://github.com/yourorg/opendiscourse.git
cd opendiscourse
```

### 2. Set Up Python Environment
```bash
# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate  # On Linux/macOS
# or
venv\Scripts\activate     # On Windows

# Upgrade pip
pip install --upgrade pip

# Install test dependencies
pip install -r tests/requirements-test.txt
```

### 3. Install Node.js Dependencies
```bash
# Navigate to Next.js directory
cd nextjs

# Install dependencies
pnpm install

# Navigate back to project root
cd ..
```

### 4. Verify Docker Installation
```bash
# Check Docker version
docker --version

# Check Docker Compose version
docker-compose --version

# Verify Docker daemon is running
docker info
```

### 5. Set Up Test Environment Variables
```bash
# Copy test environment file
cp .env.example .env.test

# Edit test environment variables as needed
nano .env.test
```

## Test Environment Configuration

### Environment Variables
Create a `.env.test` file with the following variables:

```env
# Test domain and email
TEST_DOMAIN=test.opendiscourse.net
TEST_EMAIL=test@opendiscourse.net

# Test database configuration
TEST_POSTGRES_PASSWORD=test-password-123
TEST_POSTGRES_DB=testdb
TEST_POSTGRES_PORT=5433

# Test Supabase configuration
TEST_JWT_SECRET=test-jwt-secret-with-at-least-32-characters
TEST_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtdGVzdCIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.1234567890
TEST_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS10ZXN0IiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.1234567890

# Test service ports
TEST_SUPABASE_PORT=8001
TEST_NEXTJS_PORT=3002
```

### Docker Test Configuration
Create a `docker-compose.test.yml` file for test environments:

```yaml
version: '3.8'

services:
  test-db:
    image: supabase/postgres:15.1.0.76
    environment:
      POSTGRES_PASSWORD: ${TEST_POSTGRES_PASSWORD}
      POSTGRES_DB: ${TEST_POSTGRES_DB}
    ports:
      - "${TEST_POSTGRES_PORT}:5432"
    volumes:
      - test-db-data:/var/lib/postgresql/data

  test-supabase-auth:
    image: supabase/gotrue:v2.168.0
    environment:
      GOTRUE_DB_DRIVER: postgres
      GOTRUE_DB_DATABASE_URL: postgres://postgres:${TEST_POSTGRES_PASSWORD}@test-db:5432/${TEST_POSTGRES_DB}?sslmode=disable
      GOTRUE_SITE_URL: http://localhost:${TEST_SUPABASE_PORT}
      GOTRUE_JWT_SECRET: ${TEST_JWT_SECRET}
    ports:
      - "${TEST_SUPABASE_PORT}:9999"
    depends_on:
      - test-db

volumes:
  test-db-data:
```

## Test Data Setup

### Initialize Test Database
```bash
# Start test database
docker-compose -f docker-compose.test.yml up -d test-db

# Wait for database to be ready
sleep 10

# Run database migrations
# (Add your migration commands here)
```

### Seed Test Data
```bash
# Create test users
# (Add your user creation commands here)

# Insert sample data
# (Add your data seeding commands here)
```

## Test Service Setup

### Start Test Services
```bash
# Start all test services
docker-compose -f docker-compose.test.yml up -d

# Verify services are running
docker-compose -f docker-compose.test.yml ps
```

### Configure Service Endpoints
Update test configuration to point to test services:

```python
# In test configuration
SUPABASE_URL = f"http://localhost:{os.getenv('TEST_SUPABASE_PORT')}"
SUPABASE_KEY = os.getenv('TEST_ANON_KEY')
```

## Test Environment Verification

### Run Verification Tests
```bash
# Run environment verification tests
pytest tests/unit/test_environment.py -v
```

### Check Service Connectivity
```bash
# Check database connectivity
docker-compose -f docker-compose.test.yml exec test-db pg_isready

# Check Supabase auth service
curl -f http://localhost:${TEST_SUPABASE_PORT}/health
```

## Test Environment Teardown

### Stop Test Services
```bash
# Stop all test services
docker-compose -f docker-compose.test.yml down

# Remove test volumes (optional)
docker-compose -f docker-compose.test.yml down -v
```

### Clean Up Test Data
```bash
# Remove test database volume
docker volume rm opendiscourse_test-db-data

# Clean up test environment files
rm .env.test
```

## Troubleshooting

### Common Issues

#### Docker Permission Denied
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in
```

#### Port Conflicts
```bash
# Check which process is using the port
lsof -i :8000

# Kill the process
kill -9 <PID>
```

#### Insufficient Memory
```bash
# Stop unnecessary services
docker-compose -f docker-compose.test.yml down

# Free up memory
sudo sync && sudo sysctl vm.drop_caches=3
```

#### Network Issues
```bash
# Check Docker networks
docker network ls

# Remove unused networks
docker network prune
```

### Environment Reset
```bash
# Complete environment reset
docker-compose -f docker-compose.test.yml down -v --remove-orphans
docker system prune -f
rm -rf venv
python3 -m venv venv
source venv/bin/activate
pip install -r tests/requirements-test.txt
```

## Best Practices

### Environment Isolation
- Use separate environments for development, testing, and production
- Never use production data in test environments
- Regularly reset test environments

### Resource Management
- Monitor resource usage during tests
- Limit concurrent test execution if needed
- Clean up resources after tests

### Security
- Use secure test credentials
- Rotate test credentials regularly
- Never commit real credentials to version control

### Performance
- Optimize test execution time
- Use parallel test execution when possible
- Cache test dependencies