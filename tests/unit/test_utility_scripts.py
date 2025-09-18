"""
Tests for utility scripts.
"""

import pytest
import os
import sys
from pathlib import Path

class TestUtilityScripts:
    """Test utility scripts."""
    
    def test_generate_env_script_exists(self):
        """Test that generate_env.py script exists."""
        script_path = Path("scripts/generate_env.py")
        assert script_path.exists(), "generate_env.py script not found"
    
    def test_generate_supabase_env_script_exists(self):
        """Test that generate_supabase_env.py script exists."""
        script_path = Path("scripts/generate_supabase_env.py")
        assert script_path.exists(), "generate_supabase_env.py script not found"
    
    def test_verify_env_script_exists(self):
        """Test that verify_env.py script exists."""
        script_path = Path("scripts/verify_env.py")
        assert script_path.exists(), "verify_env.py script not found"
    
    def test_scripts_are_executable(self):
        """Test that utility scripts are executable."""
        scripts = [
            "scripts/generate_env.py",
            "scripts/generate_supabase_env.py",
            "scripts/verify_env.py"
        ]
        
        for script in scripts:
            script_path = Path(script)
            assert script_path.exists(), f"{script} not found"
            
            # Check if script is executable
            import stat
            st = os.stat(script_path)
            assert bool(st.st_mode & stat.S_IEXEC), f"{script} is not executable"
    
    def test_scripts_have_proper_shebang(self):
        """Test that utility scripts have proper shebang."""
        scripts = [
            "scripts/generate_env.py",
            "scripts/generate_supabase_env.py",
            "scripts/verify_env.py"
        ]
        
        for script in scripts:
            script_path = Path(script)
            assert script_path.exists(), f"{script} not found"
            
            with open(script_path, 'r') as f:
                first_line = f.readline().strip()
            
            assert first_line == "#!/usr/bin/env python3", f"{script} doesn't have proper shebang"
    
    def test_scripts_can_be_imported(self):
        """Test that utility scripts can be imported."""
        # Add scripts directory to path
        scripts_dir = Path("scripts").resolve()
        sys.path.insert(0, str(scripts_dir))
        
        try:
            # Try importing the modules
            import generate_env
            import generate_supabase_env
            import verify_env
        finally:
            # Clean up sys.path
            if str(scripts_dir) in sys.path:
                sys.path.remove(str(scripts_dir))
    
    def test_generate_env_script_has_main_function(self):
        """Test that generate_env.py has main function."""
        script_path = Path("scripts/generate_env.py")
        assert script_path.exists(), "generate_env.py not found"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        assert "def main():" in content, "generate_env.py missing main function"
        assert "if __name__" in content, "generate_env.py missing entry point"
    
    def test_generate_supabase_env_script_has_main_function(self):
        """Test that generate_supabase_env.py has main function."""
        script_path = Path("scripts/generate_supabase_env.py")
        assert script_path.exists(), "generate_supabase_env.py not found"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        assert "def main():" in content, "generate_supabase_env.py missing main function"
        assert "if __name__" in content, "generate_supabase_env.py missing entry point"
    
    def test_verify_env_script_has_main_function(self):
        """Test that verify_env.py has main function."""
        script_path = Path("scripts/verify_env.py")
        assert script_path.exists(), "verify_env.py not found"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        assert "def main():" in content, "verify_env.py missing main function"
        assert "if __name__" in content, "verify_env.py missing entry point"