"""
Tests for one-click deployment script.
"""

import pytest
import os
import stat
from pathlib import Path

class TestOneClickDeploymentScript:
    """Test one-click deployment script."""
    
    def test_script_exists(self):
        """Test that one-click deployment script exists."""
        script_path = Path("scripts/one-click-deploy.sh")
        assert script_path.exists(), "One-click deployment script not found"
    
    def test_script_is_executable(self):
        """Test that one-click deployment script is executable."""
        script_path = Path("scripts/one-click-deploy.sh")
        assert script_path.exists(), "One-click deployment script not found"
        
        # Check if script is executable
        st = os.stat(script_path)
        assert bool(st.st_mode & stat.S_IEXEC), "One-click deployment script is not executable"
    
    def test_script_has_proper_shebang(self):
        """Test that one-click deployment script has proper shebang."""
        script_path = Path("scripts/one-click-deploy.sh")
        assert script_path.exists(), "One-click deployment script not found"
        
        with open(script_path, 'r') as f:
            first_line = f.readline().strip()
        
        assert first_line == "#!/bin/bash", "One-click deployment script doesn't have proper shebang"
    
    def test_script_has_help_command(self):
        """Test that one-click deployment script has help command."""
        script_path = Path("scripts/one-click-deploy.sh")
        assert script_path.exists(), "One-click deployment script not found"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        assert "help" in content, "One-click deployment script doesn't have help command"
        assert "--help" in content, "One-click deployment script doesn't have --help option"
        assert "-h" in content, "One-click deployment script doesn't have -h option"
    
    def test_script_has_main_functions(self):
        """Test that one-click deployment script has main functions."""
        script_path = Path("scripts/one-click-deploy.sh")
        assert script_path.exists(), "One-click deployment script not found"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        # Check for main deployment functions
        assert "check_prerequisites" in content, "One-click deployment script missing check_prerequisites function"
        assert "deploy_supabase" in content, "One-click deployment script missing deploy_supabase function"
        assert "setup_nextjs" in content, "One-click deployment script missing setup_nextjs function"
        assert "build_nextjs" in content, "One-click deployment script missing build_nextjs function"