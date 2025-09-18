# OpenDiscourse Test Fixtures and Configuration

This document describes the test fixtures and configuration for the OpenDiscourse platform.

## Test Fixtures

### Pytest Fixtures
Located in `tests/conftest.py`:

```python
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
```

### Database Fixtures
```python
# Database connection fixtures
@pytest.fixture
def test_db_connection():
    """Create a test database connection."""
    import psycopg2
    
    conn = psycopg2.connect(
        host=os.getenv("TEST_POSTGRES_HOST", "localhost"),
        port=int(os.getenv("TEST_POSTGRES_PORT", 5433)),
        database=os.getenv("TEST_POSTGRES_DB", "testdb"),
        user="postgres",
        password=os.getenv("TEST_POSTGRES_PASSWORD", "testpassword123")
    )
    
    yield conn
    
    conn.close()

@pytest.fixture
def test_db_cursor(test_db_connection):
    """Create a test database cursor."""
    cursor = test_db_connection.cursor()
    yield cursor
    cursor.close()

@pytest.fixture
def clean_test_db(test_db_connection):
    """Clean the test database before each test."""
    cursor = test_db_connection.cursor()
    
    # Clear all tables
    cursor.execute("""
        DO $$ 
        DECLARE 
            r RECORD; 
        BEGIN 
            FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP 
                EXECUTE 'DELETE FROM ' || quote_ident(r.tablename); 
            END LOOP; 
        END $$;
    """)
    
    test_db_connection.commit()
    cursor.close()
    
    yield test_db_connection
    
    # Rollback any changes after test
    test_db_connection.rollback()
```

### HTTP Client Fixtures
```python
# HTTP client fixtures
@pytest.fixture
def http_client():
    """Create an HTTP client for API testing."""
    import requests
    
    class TestHttpClient:
        def __init__(self):
            self.session = requests.Session()
            self.base_url = f"http://localhost:{os.getenv('TEST_SUPABASE_PORT', 8001)}"
        
        def get(self, path, **kwargs):
            return self.session.get(f"{self.base_url}{path}", **kwargs)
        
        def post(self, path, **kwargs):
            return self.session.post(f"{self.base_url}{path}", **kwargs)
        
        def put(self, path, **kwargs):
            return self.session.put(f"{self.base_url}{path}", **kwargs)
        
        def delete(self, path, **kwargs):
            return self.session.delete(f"{self.base_url}{path}", **kwargs)
    
    return TestHttpClient()

@pytest.fixture
def async_http_client():
    """Create an async HTTP client for API testing."""
    import httpx
    
    return httpx.AsyncClient(
        base_url=f"http://localhost:{os.getenv('TEST_SUPABASE_PORT', 8001)}"
    )
```

## Test Configuration

### Configuration Files
Located in `tests/test_config.ini`:

```ini
[colours]
; ANSI colour codes for formatted output
green = \033[0;32m
yellow = \033[1;33m
red = \033[0;31m
reset = \033[0m

[paths]
; Test-related paths
test_dir = tests
unit_tests = tests/unit
integration_tests = tests/integration
e2e_tests = tests/e2e
docker_tests = tests/docker
network_tests = tests/network
frontend_tests = tests/frontend
backend_tests = tests/backend

[commands]
; Test execution commands
run_all_tests = pytest
run_unit_tests = pytest tests/unit/
run_integration_tests = pytest tests/integration/
run_e2e_tests = pytest tests/e2e/
run_docker_tests = pytest tests/docker/
run_network_tests = pytest tests/network/
run_frontend_tests = pytest tests/frontend/
run_backend_tests = pytest tests/backend/
run_tests_with_coverage = pytest --cov=.
generate_coverage_report = pytest --cov=. --cov-report=html

[environment]
; Test environment settings
test_env_file = .env.test
default_test_domain = test.opendiscourse.net
default_test_email = test@opendiscourse.net

[reporting]
; Test reporting settings
html_report = report.html
coverage_report = htmlcov/index.html
junit_report = report.xml

[docker]
; Docker test settings
docker_compose_test_file = docker-compose.test.yml
test_network = opendiscourse-test-network
test_volume = opendiscourse-test-data

[services]
; Test service settings
supabase_test_port = 8001
nextjs_test_port = 3002
```

### Environment Variables
Located in `.env.test`:

```env
# Test domain and email
TEST_DOMAIN=test.opendiscourse.net
TEST_EMAIL=test@opendiscourse.net

# Test database configuration
TEST_POSTGRES_HOST=localhost
TEST_POSTGRES_PORT=5433
TEST_POSTGRES_DB=testdb
TEST_POSTGRES_PASSWORD=testpassword123

# Test Supabase configuration
TEST_SUPABASE_HOST=localhost
TEST_SUPABASE_PORT=8001
TEST_JWT_SECRET=test-jwt-secret-with-at-least-32-characters
TEST_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtdGVzdCIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.1234567890
TEST_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS10ZXN0IiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.1234567890

# Test service ports
TEST_NEXTJS_HOST=localhost
TEST_NEXTJS_PORT=3002

# Test credentials
TEST_DASHBOARD_USERNAME=supabase
TEST_DASHBOARD_PASSWORD=testdashboard123
```

## Custom Pytest Markers

### Marker Definitions
Defined in `pytest.ini`:

```ini
[tool:pytest]
# Directories to search for tests
testpaths = tests

# Python files to consider as tests
python_files = test_*.py *_test.py

# Python functions and classes to consider as tests
python_functions = test_*
python_classes = Test*

# Add options to ignore certain warnings
filterwarnings =
    ignore::DeprecationWarning
    ignore::PendingDeprecationWarning

# Set the minimum pytest version
minversion = 7.0

# Add markers for custom test categories
markers =
    slow: marks tests as slow
    integration: marks tests as integration tests
    e2e: marks tests as end-to-end tests
    skipci: marks tests that should be skipped in CI
    docker: marks tests that require Docker
    network: marks tests that require network connectivity
    frontend: marks tests that require frontend services
    backend: marks tests that require backend services
    security: marks security-related tests
    performance: marks performance tests
```

### Using Custom Markers
```python
# Mark tests with custom markers
@pytest.mark.integration
@pytest.mark.docker
def test_supabase_integration():
    """Test Supabase integration with Docker."""
    pass

@pytest.mark.e2e
@pytest.mark.frontend
@pytest.mark.backend
def test_complete_user_flow():
    """Test complete user flow from frontend to backend."""
    pass

@pytest.mark.slow
@pytest.mark.performance
def test_large_document_processing():
    """Test processing of large documents."""
    pass

@pytest.mark.security
def test_password_strength_validation():
    """Test password strength validation."""
    pass
```

## Test Configuration Classes

### Configuration Management
```python
# tests/config/test_config.py
"""
Test configuration management.
"""
import configparser
import os
from pathlib import Path

class TestConfig:
    """Manage test configuration."""
    
    def __init__(self, config_file="tests/test_config.ini"):
        self.config = configparser.ConfigParser()
        self.config_file = Path(config_file)
        
        if self.config_file.exists():
            self.config.read(self.config_file)
        else:
            self._create_default_config()
    
    def _create_default_config(self):
        """Create default configuration."""
        # Add default sections and values
        self.config['paths'] = {
            'test_dir': 'tests',
            'unit_tests': 'tests/unit',
            'integration_tests': 'tests/integration'
        }
        
        self.config['environment'] = {
            'test_env_file': '.env.test'
        }
        
        # Write default config
        with open(self.config_file, 'w') as f:
            self.config.write(f)
    
    def get(self, section, key, fallback=None):
        """Get configuration value."""
        return self.config.get(section, key, fallback=fallback)
    
    def getint(self, section, key, fallback=0):
        """Get integer configuration value."""
        return self.config.getint(section, key, fallback=fallback)
    
    def getboolean(self, section, key, fallback=False):
        """Get boolean configuration value."""
        return self.config.getboolean(section, key, fallback=fallback)

# Global test configuration instance
test_config = TestConfig()
```

## Test Environment Setup

### Environment Initialization
```python
# tests/setup/test_environment.py
"""
Test environment setup and initialization.
"""
import os
import pytest
from pathlib import Path

class TestEnvironmentSetup:
    """Setup and manage test environment."""
    
    @pytest.fixture(scope="session", autouse=True)
    def setup_test_environment(self):
        """Automatically setup test environment for all tests."""
        # Ensure test directories exist
        test_dirs = [
            "tests/unit",
            "tests/integration",
            "tests/e2e",
            "tests/docker",
            "tests/network",
            "tests/frontend",
            "tests/backend"
        ]
        
        for dir_path in test_dirs:
            Path(dir_path).mkdir(parents=True, exist_ok=True)
        
        # Ensure test environment file exists
        env_file = Path(".env.test")
        if not env_file.exists():
            self._create_default_env_file(env_file)
        
        yield
        
        # Cleanup after all tests
        self._cleanup_test_environment()
    
    def _create_default_env_file(self, env_file):
        """Create default test environment file."""
        default_env_content = """
# Test Environment Configuration
TEST_DOMAIN=test.opendiscourse.net
TEST_EMAIL=test@opendiscourse.net
TEST_POSTGRES_PASSWORD=testpassword123
TEST_JWT_SECRET=test-jwt-secret-with-at-least-32-characters
"""
        env_file.write_text(default_env_content.strip())
    
    def _cleanup_test_environment(self):
        """Cleanup test environment after tests."""
        # This could remove temporary files, reset databases, etc.
        pass
```

## Best Practices

### Fixture Design
1. **Scope appropriately**: Use proper fixture scopes (function, class, module, session)
2. **Minimize setup**: Keep fixture setup minimal and focused
3. **Handle cleanup**: Always clean up resources in fixtures
4. **Share when possible**: Share expensive setup across tests

### Configuration Management
1. **Separate environments**: Keep test configs separate from dev/prod
2. **Secure credentials**: Never commit real credentials
3. **Environment variables**: Use environment variables for sensitive data
4. **Validation**: Validate configuration at startup

### Performance Optimization
1. **Session-scoped fixtures**: Use for expensive setup that can be shared
2. **Caching**: Cache computed values in fixtures
3. **Lazy loading**: Load resources only when needed
4. **Parallel execution**: Design fixtures for parallel test execution

### Maintainability
1. **Clear naming**: Use descriptive names for fixtures
2. **Documentation**: Document complex fixtures
3. **Consistent patterns**: Follow consistent patterns for similar fixtures
4. **Regular cleanup**: Remove unused fixtures periodically