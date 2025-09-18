"""
Test configuration and fixtures for OpenDiscourse tests.
"""
import os
import pytest
import docker
import time
from dotenv import load_dotenv

# Load environment variables from .env.test file
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env.test'))

# Test configuration
TEST_PREFIX = "test_"
TIMEOUT = 30  # seconds

@pytest.fixture(scope="session")
def docker_client():
    """Create a Docker client."""
    return docker.from_env()

@pytest.fixture(scope="session")
def wait_for_service():
    """Wait for a service to become available."""
    def _wait_for_service(host, port, timeout=TIMEOUT):
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
    return _wait_for_service

@pytest.fixture(scope="session")
def supabase_service(wait_for_service):
    """Ensure Supabase service is running."""
    host = os.getenv("TEST_SUPABASE_HOST", "localhost")
    port = int(os.getenv("TEST_SUPABASE_PORT", 8001))
    try:
        wait_for_service(host, port)
        return f"http://{host}:{port}"
    except TimeoutError:
        pytest.skip("Supabase service not available")

@pytest.fixture(scope="session")
def nextjs_service(wait_for_service):
    """Ensure Next.js service is running."""
    host = os.getenv("TEST_NEXTJS_HOST", "localhost")
    port = int(os.getenv("TEST_NEXTJS_PORT", 3002))
    try:
        wait_for_service(host, port)
        return f"http://{host}:{port}"
    except TimeoutError:
        pytest.skip("Next.js service not available")

@pytest.fixture
def temp_env_file(tmp_path):
    """Create a temporary .env.test file for testing."""
    env_file = tmp_path / ".env.test"
    env_content = """
TEST_DOMAIN=test.opendiscourse.net
TEST_EMAIL=test@opendiscourse.net
TEST_POSTGRES_PASSWORD=testpassword123
TEST_JWT_SECRET=test-jwt-secret-with-at-least-32-characters
"""
    env_file.write_text(env_content)
    return env_file

@pytest.fixture
def mock_supabase_client():
    """Create a mock Supabase client for testing."""
    from unittest.mock import Mock
    
    mock_client = Mock()
    mock_client.auth = Mock()
    mock_client.from_ = Mock()
    mock_client.rpc = Mock()
    
    return mock_client