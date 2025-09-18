"""
End-to-end workflow tests for OpenDiscourse.
"""

import pytest
import os
import subprocess
import tempfile
from pathlib import Path

class TestDeploymentWorkflows:
    """Test complete deployment workflows."""
    
    def test_one_click_deploy_script_exists(self):
        """Test that one-click deployment script exists."""
        script_file = Path("scripts/one-click-deploy.sh")
        assert script_file.exists(), "One-click deployment script not found"
        
        # Check that script is executable
        assert os.access(script_file, os.X_OK), "One-click deployment script is not executable"
    
    def test_supabase_deploy_script_exists(self):
        """Test that Supabase deployment script exists."""
        script_file = Path("scripts/deploy-supabase.sh")
        assert script_file.exists(), "Supabase deployment script not found"
        
        # Check that script is executable
        assert os.access(script_file, os.X_OK), "Supabase deployment script is not executable"
    
    def test_nextjs_setup_script_exists(self):
        """Test that Next.js setup script exists."""
        script_file = Path("scripts/setup-nextjs.sh")
        assert script_file.exists(), "Next.js setup script not found"
        
        # Check that script is executable
        assert os.access(script_file, os.X_OK), "Next.js setup script is not executable"
    
    def test_env_generator_scripts_exist(self):
        """Test that environment generator scripts exist."""
        supabase_gen = Path("scripts/generate_supabase_env.py")
        app_gen = Path("scripts/generate_env.py")
        
        assert supabase_gen.exists(), "Supabase env generator script not found"
        assert app_gen.exists(), "Application env generator script not found"
        
        # Check that scripts are executable
        assert os.access(supabase_gen, os.X_OK), "Supabase env generator script is not executable"
        assert os.access(app_gen, os.X_OK), "Application env generator script is not executable"

class TestEnvironmentSetup:
    """Test environment setup workflows."""
    
    def test_supabase_env_generation(self):
        """Test Supabase environment generation."""
        # Test that we can generate a Supabase .env file
        with tempfile.TemporaryDirectory() as tmpdir:
            env_file = Path(tmpdir) / ".env"
            result = subprocess.run([
                "python3", "scripts/generate_supabase_env.py",
                "--output", str(env_file),
                "--force"
            ], capture_output=True, text=True)
            
            assert result.returncode == 0, f"Supabase env generation failed: {result.stderr}"
            assert env_file.exists(), "Supabase .env file was not created"
    
    def test_app_env_generation(self):
        """Test application environment generation."""
        # Test that we can generate an application .env file
        with tempfile.TemporaryDirectory() as tmpdir:
            env_file = Path(tmpdir) / ".env"
            result = subprocess.run([
                "python3", "scripts/generate_env.py",
                "--domain", "test.example.com",
                "--email", "test@example.com",
                "--output", str(env_file),
                "--force"
            ], capture_output=True, text=True)
            
            assert result.returncode == 0, f"Application env generation failed: {result.stderr}"
            assert env_file.exists(), "Application .env file was not created"