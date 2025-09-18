"""
Unit tests for OpenDiscourse utility functions.
"""

import pytest
import os
import tempfile
from pathlib import Path
from unittest.mock import patch, mock_open

# Import our utility functions
from scripts.generate_env import generate_secure_password, generate_env_content
from scripts.generate_supabase_env import generate_supabase_env_content

class TestEnvironmentGeneration:
    """Test environment variable generation functions."""
    
    def test_generate_secure_password_default(self):
        """Test default secure password generation."""
        password = generate_secure_password()
        assert len(password) == 32
        assert password.isalnum()
    
    def test_generate_secure_password_custom_length(self):
        """Test custom length secure password generation."""
        password = generate_secure_password(16)
        assert len(password) == 16
        assert password.isalnum()
    
    def test_generate_secure_password_avoid_symbols(self):
        """Test secure password generation without symbols."""
        password = generate_secure_password(50, avoid_symbols=True)
        assert len(password) == 50
        assert password.isalnum()
    
    def test_generate_secure_password_unique(self):
        """Test that generated passwords are unique."""
        password1 = generate_secure_password()
        password2 = generate_secure_password()
        assert password1 != password2
    
    def test_generate_env_content_structure(self):
        """Test that env content has required structure."""
        content = generate_env_content("test.example.com", "test@example.com")
        
        # Check required variables
        assert "DOMAIN=\"test.example.com\"" in content
        assert "EMAIL=\"test@example.com\"" in content
        assert "POSTGRES_PASSWORD=" in content
        assert "JWT_SECRET=" in content
    
    def test_generate_supabase_env_content_structure(self):
        """Test that Supabase env content has required structure."""
        content = generate_supabase_env_content()
        
        # Check required variables
        assert "POSTGRES_PASSWORD=" in content
        assert "JWT_SECRET=" in content
        assert "ANON_KEY=" in content
        assert "SERVICE_ROLE_KEY=" in content
        assert "DASHBOARD_USERNAME=" in content
        assert "DASHBOARD_PASSWORD=" in content

class TestFileOperations:
    """Test file operations."""
    
    def test_env_file_generation(self):
        """Test that we can generate an env file."""
        with tempfile.TemporaryDirectory() as tmpdir:
            env_file = Path(tmpdir) / ".env"
            content = generate_env_content("test.example.com", "test@example.com")
            
            with open(env_file, "w") as f:
                f.write(content)
            
            assert env_file.exists()
            
            with open(env_file, "r") as f:
                file_content = f.read()
            
            assert "DOMAIN=\"test.example.com\"" in file_content
            assert "EMAIL=\"test@example.com\"" in file_content