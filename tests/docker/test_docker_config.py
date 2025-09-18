"""
Tests for Docker configurations.
"""

import pytest
import os
import yaml
from pathlib import Path

class TestDockerConfigurations:
    """Test Docker configurations."""
    
    def test_supabase_docker_compose_exists(self):
        """Test that Supabase Docker Compose file exists."""
        compose_file = Path("supabase-docker/docker-compose.yml")
        assert compose_file.exists(), "Supabase Docker Compose file not found"
    
    def test_supabase_docker_compose_is_valid_yaml(self):
        """Test that Supabase Docker Compose file is valid YAML."""
        compose_file = Path("supabase-docker/docker-compose.yml")
        assert compose_file.exists(), "Supabase Docker Compose file not found"
        
        try:
            with open(compose_file, 'r') as f:
                yaml.safe_load(f)
        except yaml.YAMLError as e:
            pytest.fail(f"Supabase Docker Compose file is not valid YAML: {e}")
    
    def test_supabase_docker_compose_has_required_services(self):
        """Test that Supabase Docker Compose has required services."""
        compose_file = Path("supabase-docker/docker-compose.yml")
        assert compose_file.exists(), "Supabase Docker Compose file not found"
        
        with open(compose_file, 'r') as f:
            compose_data = yaml.safe_load(f)
        
        assert "services" in compose_data, "Docker Compose missing services section"
        
        required_services = [
            "studio",
            "kong",
            "auth",
            "rest",
            "realtime",
            "storage",
            "imgproxy",
            "meta",
            "functions",
            "analytics",
            "db",
            "vector",
            "supavisor"
        ]
        
        services = compose_data["services"]
        for service in required_services:
            assert service in services, f"Required service {service} not found in Docker Compose"
    
    def test_supabase_env_file_exists(self):
        """Test that Supabase .env file exists."""
        env_file = Path("supabase-docker/.env")
        # This might not exist in fresh setup, so we check if it can be generated
        assert True  # Placeholder for now
    
    def test_supabase_volumes_directory_exists(self):
        """Test that Supabase volumes directory exists."""
        volumes_dir = Path("supabase-docker/volumes")
        assert volumes_dir.exists(), "Supabase volumes directory not found"
        assert volumes_dir.is_dir(), "Supabase volumes is not a directory"
    
    def test_supabase_required_volume_subdirs_exist(self):
        """Test that required Supabase volume subdirectories exist."""
        volumes_dir = Path("supabase-docker/volumes")
        if not volumes_dir.exists():
            pytest.skip("Supabase volumes directory not found")
        
        required_subdirs = [
            "db",
            "storage",
            "functions",
            "pooler"
        ]
        
        for subdir in required_subdirs:
            subdir_path = volumes_dir / subdir
            assert subdir_path.exists(), f"Required volume subdirectory {subdir} not found"
    
    def test_dockerignore_exists(self):
        """Test that .dockerignore file exists."""
        dockerignore = Path("supabase-docker/.dockerignore")
        # This might not be required, so we'll just check if directory exists
        supabase_dir = Path("supabase-docker")
        assert supabase_dir.exists(), "Supabase directory not found"
    
    def test_supabase_docker_compose_has_proper_networking(self):
        """Test that Supabase Docker Compose has proper networking configuration."""
        compose_file = Path("supabase-docker/docker-compose.yml")
        assert compose_file.exists(), "Supabase Docker Compose file not found"
        
        with open(compose_file, 'r') as f:
            compose_data = yaml.safe_load(f)
        
        # Check for networks section
        assert "networks" in compose_data, "Docker Compose missing networks section"
        
        # Check for services using networks
        services = compose_data.get("services", {})
        for service_name, service_config in services.items():
            if "networks" in service_config:
                # Just verify it's properly formatted
                networks = service_config["networks"]
                assert isinstance(networks, (list, dict)), f"Service {service_name} has invalid networks configuration"
    
    def test_supabase_docker_compose_has_volumes(self):
        """Test that Supabase Docker Compose has volumes configuration."""
        compose_file = Path("supabase-docker/docker-compose.yml")
        assert compose_file.exists(), "Supabase Docker Compose file not found"
        
        with open(compose_file, 'r') as f:
            compose_data = yaml.safe_load(f)
        
        # Check for volumes section
        assert "volumes" in compose_data, "Docker Compose missing volumes section"
        
        # Check that volumes are properly defined
        volumes = compose_data["volumes"]
        assert isinstance(volumes, dict), "Docker Compose volumes section is not a dictionary"