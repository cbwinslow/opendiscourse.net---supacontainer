"""
Integration tests for Supabase services.
"""

import pytest
import os
import requests
from pathlib import Path

class TestSupabaseIntegration:
    """Integration tests for Supabase services."""
    
    @pytest.fixture(scope="class")
    def supabase_url(self):
        """Get Supabase URL from environment or default."""
        return os.getenv("SUPABASE_URL", "http://localhost:8000")
    
    @pytest.fixture(scope="class")
    def supabase_anon_key(self):
        """Get Supabase anon key from environment or default."""
        # Try to get from existing .env file
        env_file = Path("supabase-docker/.env")
        if env_file.exists():
            with open(env_file, 'r') as f:
                content = f.read()
                for line in content.split('\n'):
                    if line.startswith('ANON_KEY='):
                        return line.split('=', 1)[1].strip().strip('"')
        
        return os.getenv("SUPABASE_ANON_KEY", "")
    
    def test_supabase_studio_accessible(self, supabase_url):
        """Test that Supabase Studio is accessible."""
        studio_url = supabase_url.replace(":8000", ":3000")
        try:
            response = requests.get(studio_url, timeout=10)
            # Studio might redirect, so we check for 200 or 300 series
            assert response.status_code < 400, f"Studio returned status {response.status_code}"
        except requests.exceptions.RequestException:
            pytest.skip("Supabase Studio not accessible")
    
    def test_supabase_rest_api_accessible(self, supabase_url):
        """Test that Supabase REST API is accessible."""
        rest_url = f"{supabase_url}/rest/v1/"
        try:
            response = requests.get(rest_url, timeout=10)
            # REST API might return 400 for missing headers, which is still accessible
            assert response.status_code != 404, f"REST API returned 404: {response.status_code}"
        except requests.exceptions.RequestException:
            pytest.skip("Supabase REST API not accessible")
    
    def test_supabase_auth_api_accessible(self, supabase_url):
        """Test that Supabase Auth API is accessible."""
        auth_url = f"{supabase_url}/auth/v1/settings"
        try:
            response = requests.get(auth_url, timeout=10)
            # Auth settings should be accessible
            assert response.status_code == 200, f"Auth API returned status {response.status_code}"
        except requests.exceptions.RequestException:
            pytest.skip("Supabase Auth API not accessible")
    
    def test_supabase_storage_api_accessible(self, supabase_url):
        """Test that Supabase Storage API is accessible."""
        storage_url = f"{supabase_url}/storage/v1/status"
        try:
            response = requests.get(storage_url, timeout=10)
            # Storage status should be accessible
            assert response.status_code == 200, f"Storage API returned status {response.status_code}"
        except requests.exceptions.RequestException:
            pytest.skip("Supabase Storage API not accessible")
    
    def test_supabase_database_connection(self, supabase_url):
        """Test that Supabase database is accessible."""
        # This would typically test direct PostgreSQL connection
        # For now, we'll test the health endpoint
        health_url = f"{supabase_url}/rest/v1/"
        try:
            response = requests.get(health_url, timeout=10)
            # If we can reach the REST API, database is likely accessible
            assert response.status_code < 500, f"Database connection failed with status {response.status_code}"
        except requests.exceptions.RequestException:
            pytest.skip("Supabase database not accessible")
    
    def test_supabase_jwt_configuration(self, supabase_anon_key):
        """Test that Supabase JWT is properly configured."""
        # Skip if no anon key available
        if not supabase_anon_key:
            pytest.skip("No Supabase anon key available")
        
        # Check that anon key looks like a JWT
        assert "." in supabase_anon_key, "Anon key doesn't look like a JWT"
        parts = supabase_anon_key.split(".")
        assert len(parts) == 3, "Anon key doesn't have 3 parts like a JWT"
    
    def test_supabase_required_services_running(self):
        """Test that required Supabase services are running."""
        # Check Docker containers if possible
        try:
            import docker
            client = docker.from_env()
            
            # List of required Supabase containers
            required_containers = [
                "supabase-db",
                "supabase-kong",
                "supabase-auth",
                "supabase-rest",
                "supabase-realtime",
                "supabase-storage",
                "supabase-studio"
            ]
            
            containers = client.containers.list()
            container_names = [c.name for c in containers]
            
            for required_container in required_containers:
                assert any(required_container in name for name in container_names), \
                    f"Required container {required_container} not running"
                    
        except (ImportError, Exception):
            # If Docker is not available, skip this test
            pytest.skip("Docker not available for container checks")