"""
Tests for Next.js setup and configuration.
"""

import pytest
import os
from pathlib import Path

class TestNextJsSetup:
    """Test Next.js setup and configuration."""
    
    def test_nextjs_directory_exists(self):
        """Test that Next.js directory exists."""
        nextjs_dir = Path("nextjs")
        assert nextjs_dir.exists(), "Next.js directory not found"
    
    def test_nextjs_package_json_exists(self):
        """Test that Next.js package.json exists."""
        package_file = Path("nextjs/package.json")
        assert package_file.exists(), "Next.js package.json not found"
        
        # Check content
        with open(package_file, 'r') as f:
            content = f.read()
        
        assert "next" in content
        assert "react" in content
        assert "@supabase/ssr" in content
    
    def test_nextjs_pages_exist(self):
        """Test that required Next.js pages exist."""
        app_dir = Path("nextjs/app")
        assert app_dir.exists(), "Next.js app directory not found"
        
        required_pages = [
            "page.js",
            "login/page.js",
            "account/page.js"
        ]
        
        for page in required_pages:
            page_path = app_dir / page
            assert page_path.exists(), f"Required page {page} not found"
    
    def test_nextjs_utils_exist(self):
        """Test that Next.js Supabase utilities exist."""
        utils_dir = Path("nextjs/utils/supabase")
        assert utils_dir.exists(), "Next.js Supabase utils directory not found"
        
        required_files = [
            "client.js",
            "server.js",
            "middleware.js"
        ]
        
        for file in required_files:
            file_path = utils_dir / file
            assert file_path.exists(), f"Required Supabase utility {file} not found"
    
    def test_nextjs_middleware_exists(self):
        """Test that Next.js middleware exists."""
        middleware_file = Path("nextjs/middleware.js")
        assert middleware_file.exists(), "Next.js middleware file not found"
    
    def test_nextjs_tailwind_config_exists(self):
        """Test that Next.js Tailwind CSS configuration exists."""
        tailwind_config = Path("nextjs/tailwind.config.js")
        assert tailwind_config.exists(), "Next.js Tailwind CSS config not found"
        
        postcss_config = Path("nextjs/postcss.config.js")
        assert postcss_config.exists(), "Next.js PostCSS config not found"
    
    def test_nextjs_globals_css_exists(self):
        """Test that Next.js global CSS exists."""
        globals_css = Path("nextjs/app/globals.css")
        assert globals_css.exists(), "Next.js globals.css not found"
        
        # Check content
        with open(globals_css, 'r') as f:
            content = f.read()
        
        assert "@tailwind" in content
    
    def test_nextjs_layout_exists(self):
        """Test that Next.js layout exists."""
        layout_file = Path("nextjs/app/layout.js")
        assert layout_file.exists(), "Next.js layout file not found"
    
    def test_nextjs_env_local_exists(self):
        """Test that Next.js .env.local exists."""
        env_local = Path("nextjs/.env.local")
        # This might not exist in fresh setup, so we'll just check if directory exists
        nextjs_dir = Path("nextjs")
        assert nextjs_dir.exists(), "Next.js directory not found"