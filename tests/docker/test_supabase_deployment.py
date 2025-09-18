"""
Tests for Supabase deployment script.
"""

import pytest
import os
import stat
from pathlib import Path

class TestSupabaseDeploymentScript:
    """Test Supabase deployment script."""
    
    def test_script_exists(self):
        """Test that Supabase deployment script exists."""
        script_path = Path("scripts/deploy-supabase.sh")
        assert script_path.exists(), "Supabase deployment script not found"
    
    def test_script_is_executable(self):
        """Test that Supabase deployment script is executable."""
        script_path = Path("scripts/deploy-supabase.sh")
        assert script_path.exists(), "Supabase deployment script not found"
        
        # Check if script is executable
        st = os.stat(script_path)
        assert bool(st.st_mode & stat.S_IEXEC), "Supabase deployment script is not executable"
    
    def test_script_has_proper_shebang(self):
        """Test that Supabase deployment script has proper shebang."""
        script_path = Path("scripts/deploy-supabase.sh")
        assert script_path.exists(), "Supabase deployment script not found"
        
        with open(script_path, 'r') as f:
            first_line = f.readline().strip()
        
        assert first_line == "#!/bin/bash", "Supabase deployment script doesn't have proper shebang"
    
    def test_script_has_help_command(self):
        """Test that Supabase deployment script has help command."""
        script_path = Path("scripts/deploy-supabase.sh")
        assert script_path.exists(), "Supabase deployment script not found"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        assert "help" in content, "Supabase deployment script doesn't have help command"
        assert "--help" in content, "Supabase deployment script doesn't have --help option"
        assert "-h" in content, "Supabase deployment script doesn't have -h option"