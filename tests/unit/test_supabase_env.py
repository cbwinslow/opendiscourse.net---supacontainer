"""
Tests for Supabase environment generation.
"""

import pytest
import os
import tempfile
from pathlib import Path
from scripts.generate_supabase_env import generate_secure_password, generate_supabase_env_content

class TestSupabaseEnvironmentGeneration:
    """Test Supabase environment generation."""
    
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
        assert "SECRET_KEY_BASE=" in content
        assert "VAULT_ENC_KEY=" in content
    
    def test_generate_supabase_env_file(self):
        """Test that we can generate a Supabase env file."""
        with tempfile.TemporaryDirectory() as tmpdir:
            env_file = Path(tmpdir) / ".env"
            content = generate_supabase_env_content()
            
            with open(env_file, "w") as f:
                f.write(content)
            
            assert env_file.exists()
            
            with open(env_file, "r") as f:
                file_content = f.read()
            
            # Check required variables in file
            assert "POSTGRES_PASSWORD=" in file_content
            assert "JWT_SECRET=" in file_content
            assert "ANON_KEY=" in file_content
            assert "SERVICE_ROLE_KEY=" in file_content
    
    def test_supabase_env_password_security(self):
        """Test that Supabase env passwords are secure."""
        content = generate_supabase_env_content()
        
        # Extract passwords from content
        lines = content.split('\n')
        password_lines = [line for line in lines if '=' in line and line.split('=', 1)[1].strip()]
        
        # Define which variables should be checked as passwords
        password_keys = [
            'POSTGRES_PASSWORD',
            'JWT_SECRET',
            'DASHBOARD_PASSWORD',
            'SECRET_KEY_BASE',
            'VAULT_ENC_KEY'
        ]
        
        # Define which variables are JWT tokens (expected to have special characters)
        jwt_keys = ['ANON_KEY', 'SERVICE_ROLE_KEY']
        
        # Define which variables are identifiers (can contain hyphens)
        identifier_keys = ['POOLER_TENANT_ID']
        
        for line in password_lines:
            if '=' in line:
                key, value = line.split('=', 1)
                value = value.strip().strip('"')
                
                # Skip empty values
                if not value:
                    continue
                
                # Skip JWT tokens as they're expected to have special characters
                if key in jwt_keys:
                    continue
                
                # Skip identifiers that can contain hyphens
                if key in identifier_keys:
                    continue
                
                # Skip variables that are comma-separated lists or other non-password values
                if ',' in value or key in ['PGRST_DB_SCHEMAS', 'SITE_URL']:
                    continue
                
                # Check password-like variables
                if key in password_keys:
                    # Check that passwords are alphanumeric
                    assert value.isalnum(), f"Password for {key} contains non-alphanumeric characters: {value}"
                    
                    # Check minimum length
                    assert len(value) >= 16, f"Password for {key} is too short: {len(value)} characters"
                
                # For other variables that look like passwords, check if they're alphanumeric
                elif 'PASSWORD' in key or 'SECRET' in key or 'KEY' in key:
                    # These might be JWT tokens or other special values, so we'll be more lenient
                    # Just make sure they're not obviously problematic
                    assert '"' not in value, f"Value for {key} contains quotes: {value}"
                    assert "'" not in value, f"Value for {key} contains single quotes: {value}"
                    assert "$" not in value, f"Value for {key} contains dollar sign: {value}"
                    assert "\\" not in value, f"Value for {key} contains backslash: {value}"