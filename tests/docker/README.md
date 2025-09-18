# OpenDiscourse Docker Tests

This directory contains tests specifically for Docker deployments and container configurations.

## Test Categories

- `test_docker_images.py` - Test Docker image builds and configurations
- `test_docker_compose.py` - Test Docker Compose configurations
- `test_container_services.py` - Test individual container services
- `test_volume_mounts.py` - Test volume configurations and mounts
- `test_networking.py` - Test Docker networking configurations

## Running Docker Tests

```bash
# Run all Docker tests
pytest tests/docker/

# Run specific Docker test
pytest tests/docker/test_docker_images.py

# Run with Docker in Docker (DinD) support
pytest tests/docker/ --docker-compose
```

## Test Environment

Docker tests require:
- Docker daemon running
- Docker Compose installed
- Sufficient system resources (CPU, memory, disk)

## Test Data

Docker tests use:
- Test Docker images built from local Dockerfiles
- Temporary containers that are cleaned up after tests
- Isolated networks for testing service communication