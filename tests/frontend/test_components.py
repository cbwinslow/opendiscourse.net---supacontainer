"""
Frontend component tests for OpenDiscourse Next.js application.
"""

import pytest
import os
from pathlib import Path

class TestFrontendComponents:
    """Test React components in the Next.js application."""
    
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
    
    def test_supabase_utils_exist(self):
        """Test that Supabase utility files exist."""
        utils_dir = Path("nextjs/utils/supabase")
        assert utils_dir.exists(), "Supabase utils directory not found"
        
        required_files = [
            "client.js",
            "server.js",
            "middleware.js"
        ]
        
        for file in required_files:
            file_path = utils_dir / file
            assert file_path.exists(), f"Required Supabase utility {file} not found"
    
    def test_middleware_exists(self):
        """Test that Next.js middleware exists."""
        middleware_file = Path("nextjs/middleware.js")
        assert middleware_file.exists(), "Next.js middleware file not found"
    
    def test_tailwind_config_exists(self):
        """Test that Tailwind CSS configuration exists."""
        tailwind_config = Path("nextjs/tailwind.config.js")
        assert tailwind_config.exists(), "Tailwind CSS config not found"
        
        postcss_config = Path("nextjs/postcss.config.js")
        assert postcss_config.exists(), "PostCSS config not found"

class TestFrontendBuild:
    """Test Next.js build process."""
    
    def test_package_json_exists(self):
        """Test that package.json exists."""
        package_file = Path("nextjs/package.json")
        assert package_file.exists(), "Next.js package.json not found"
    
    def test_dependencies_defined(self):
        """Test that required dependencies are defined."""
        package_file = Path("nextjs/package.json")
        with open(package_file, 'r') as f:
            content = f.read()
        
        required_deps = [
            "next",
            "react",
            "react-dom",
            "@supabase/ssr",
            "@supabase/supabase-js"
        ]
        
        for dep in required_deps:
            assert dep in content, f"Required dependency {dep} not found in package.json"