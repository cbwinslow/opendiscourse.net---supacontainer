"""
Pytest configuration and fixtures for OpenDiscourse tests.
"""
import os
import pytest
import docker
import time
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

# Test configuration
TEST_PREFIX = "test_"
TIMEOUT = 30  # seconds

@pytest.fixture(scope="session")
def docker_client():
    """Create a Docker client."""
    return docker.from_env()

@pytest.fixture(scope="session")
def wait_for_service(host, port, timeout=TIMEOUT):
    """Wait for a service to become available."""
    import socket
    import time
    
    start_time = time.time()
    while True:
        try:
            with socket.create_connection((host, port), timeout=1):
                return True
        except (socket.error, ConnectionRefusedError):
            if time.time() - start_time > timeout:
                raise TimeoutError(f"Service at {host}:{port} not available after {timeout} seconds")
            time.sleep(1)

@pytest.fixture(scope="session")
def n8n_service(wait_for_service):
    """Ensure n8n service is running."""
    host = os.getenv("N8N_HOST", "localhost")
    port = 5678
    wait_for_service(host, port)
    return f"http://{host}:{port}"

@pytest.fixture(scope="session")
def minio_service(wait_for_service):
    """Ensure MinIO service is running."""
    host = os.getenv("MINIO_ENDPOINT", "localhost").replace("https://", "").replace("http://", "")
    port = 9000
    wait_for_service(host, port)
    return f"http://{host}:{port}"
