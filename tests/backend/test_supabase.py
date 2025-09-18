"""
Backend service tests for OpenDiscourse Supabase integration.
"""

import pytest
import os
from pathlib import Path

class TestSupabaseConfiguration:
    """Test Supabase configuration files."""
    
    def test_supabase_env_file_exists(self):
        """Test that Supabase .env file exists."""
        env_file = Path("supabase-docker/.env")
        assert env_file.exists(), "Supabase .env file not found"
    
    def test_supabase_required_variables(self):
        """Test that required Supabase variables are defined."""
        env_file = Path("supabase-docker/.env")
        with open(env_file, 'r') as f:
            content = f.read()
        
        required_vars = [
            "POSTGRES_PASSWORD",
            "JWT_SECRET",
            "ANON_KEY",
            "SERVICE_ROLE_KEY",
            "DASHBOARD_USERNAME",
            "DASHBOARD_PASSWORD"
        ]
        
        for var in required_vars:
            assert f"{var}=" in content, f"Required variable {var} not found in .env file"
    
    def test_supabase_docker_compose_exists(self):
        """Test that Supabase Docker Compose file exists."""
        compose_file = Path("supabase-docker/docker-compose.yml")
        assert compose_file.exists(), "Supabase Docker Compose file not found"
    
    def test_supabase_services_defined(self):
        """Test that required Supabase services are defined."""
        compose_file = Path("supabase-docker/docker-compose.yml")
        with open(compose_file, 'r') as f:
            content = f.read()
        
        required_services = [
            "studio",
            "kong",
            "auth",
            "rest",
            "realtime",
            "storage"
        ]
        
        for service in required_services:
            assert f"container_name: supabase-{service}" in content or f"{service}:" in content, \
                f"Service {service} not properly defined in Docker Compose"

class TestDatabaseConfiguration:
    """Test database configuration."""
    
    def test_postgres_service_defined(self):
        """Test that PostgreSQL service is defined."""
        compose_file = Path("supabase-docker/docker-compose.yml")
        with open(compose_file, 'r') as f:
            content = f.read()
        
        assert "db:" in content, "PostgreSQL service not defined"
        assert "supabase/postgres" in content, "Supabase PostgreSQL image not used"
    
    def test_supavisor_service_defined(self):
        """Test that Supavisor service is defined."""
        compose_file = Path("supabase-docker/docker-compose.yml")
        with open(compose_file, 'r') as f:
            content = f.read()
        
        assert "supavisor:" in content, "Supavisor service not defined"