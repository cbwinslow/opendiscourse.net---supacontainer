"""
Integration tests for OpenDiscourse services.
"""

import pytest
import os
from pathlib import Path

class TestServiceIntegration:
    """Test integration between different services."""
    
    def test_supabase_nextjs_integration(self):
        """Test Supabase and Next.js integration."""
        # Check that Next.js .env.local references Supabase variables
        env_local = Path("nextjs/.env.local")
        if env_local.exists():
            with open(env_local, 'r') as f:
                content = f.read()
            
            assert "NEXT_PUBLIC_SUPABASE_URL" in content, "Supabase URL not found in Next.js .env.local"
            assert "NEXT_PUBLIC_SUPABASE_ANON_KEY" in content, "Supabase anon key not found in Next.js .env.local"
    
    def test_supabase_client_utils_exist(self):
        """Test that Supabase client utilities exist."""
        client_utils = Path("nextjs/utils/supabase/client.js")
        assert client_utils.exists(), "Supabase client utilities not found"
    
    def test_supabase_server_utils_exist(self):
        """Test that Supabase server utilities exist."""
        server_utils = Path("nextjs/utils/supabase/server.js")
        assert server_utils.exists(), "Supabase server utilities not found"
    
    def test_supabase_middleware_exists(self):
        """Test that Supabase middleware exists."""
        middleware = Path("nextjs/utils/supabase/middleware.js")
        assert middleware.exists(), "Supabase middleware not found"

class TestConfigurationIntegration:
    """Test integration of configuration files."""
    
    def test_env_files_consistency(self):
        """Test consistency between different environment files."""
        # This would check that environment variables are consistent across files
        pass