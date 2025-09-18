# OpenDiscourse Test Suite

This directory contains the complete test suite for the OpenDiscourse platform.

## Test Structure

- `unit/` - Unit tests for individual functions and components
- `integration/` - Integration tests for service interactions
- `e2e/` - End-to-end tests for complete workflows
- `docker/` - Docker-specific tests
- `network/` - Network connectivity and communication tests
- `frontend/` - Frontend component tests
- `backend/` - Backend service tests

## Running Tests

### Setup

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install test dependencies
pip install -r requirements-test.txt
```

### Run All Tests

```bash
# Run entire test suite
pytest

# Run with coverage
pytest --cov=.

# Run with HTML report
pytest --html=report.html
```

### Run Specific Test Categories

```bash
# Unit tests
pytest tests/unit/

# Integration tests
pytest tests/integration/

# End-to-end tests
pytest tests/e2e/

# Docker tests
pytest tests/docker/

# Network tests
pytest tests/network/

# Frontend tests
pytest tests/frontend/

# Backend tests
pytest tests/backend/
```

## Test Categories

### Unit Tests
Test individual functions and components in isolation with mocked dependencies.

### Integration Tests
Test interactions between services and components.

### End-to-End Tests
Test complete user workflows and system behavior.

### Docker Tests
Test Docker image builds, container deployments, and service configurations.

### Network Tests
Test network connectivity, service communication, and API endpoints.

### Frontend Tests
Test frontend components, user interfaces, and client-side functionality.

### Backend Tests
Test backend services, APIs, and server-side functionality.

## Test Configuration

The test suite uses configuration files and environment variables:

- `pytest.ini` - pytest configuration
- `conftest.py` - pytest fixtures and configuration
- `.env.test` - test environment variables
- `docker-compose.test.yml` - Docker Compose for testing

## Continuous Integration

Tests are automatically run in CI/CD pipelines to ensure code quality and prevent regressions.