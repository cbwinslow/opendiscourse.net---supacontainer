"""
Tests for test requirements.
"""

import pytest
import os
from pathlib import Path

class TestTestRequirements:
    """Test test requirements."""
    
    def test_requirements_file_exists(self):
        """Test that test requirements file exists."""
        req_file = Path("tests/requirements-test.txt")
        assert req_file.exists(), "tests/requirements-test.txt not found"
    
    def test_requirements_file_has_content(self):
        """Test that test requirements file has content."""
        req_file = Path("tests/requirements-test.txt")
        assert req_file.exists(), "tests/requirements-test.txt not found"
        
        with open(req_file, 'r') as f:
            content = f.read()
        
        assert len(content.strip()) > 0, "tests/requirements-test.txt is empty"
    
    def test_requirements_include_pytest(self):
        """Test that test requirements include pytest."""
        req_file = Path("tests/requirements-test.txt")
        assert req_file.exists(), "tests/requirements-test.txt not found"
        
        with open(req_file, 'r') as f:
            content = f.read()
        
        assert "pytest" in content, "pytest not found in test requirements"
    
    def test_requirements_include_test_dependencies(self):
        """Test that test requirements include necessary dependencies."""
        req_file = Path("tests/requirements-test.txt")
        assert req_file.exists(), "tests/requirements-test.txt not found"
        
        with open(req_file, 'r') as f:
            content = f.read()
        
        required_deps = [
            "pytest",
            "pytest-cov",
            "pytest-asyncio",
            "pytest-html",
            "pytest-xdist",
            "pytest-mock",
            "requests",
            "python-dotenv",
            "httpx",
            "docker"
        ]
        
        for dep in required_deps:
            assert dep in content, f"{dep} not found in test requirements"
    
    def test_pytest_ini_exists(self):
        """Test that pytest.ini exists."""
        pytest_ini = Path("pytest.ini")
        assert pytest_ini.exists(), "pytest.ini not found"
    
    def test_pytest_ini_has_content(self):
        """Test that pytest.ini has content."""
        pytest_ini = Path("pytest.ini")
        assert pytest_ini.exists(), "pytest.ini not found"
        
        with open(pytest_ini, 'r') as f:
            content = f.read()
        
        assert len(content.strip()) > 0, "pytest.ini is empty"
        assert "[tool:pytest]" in content, "pytest.ini doesn't have proper section"
    
    def test_pytest_ini_has_markers(self):
        """Test that pytest.ini has custom markers."""
        pytest_ini = Path("pytest.ini")
        assert pytest_ini.exists(), "pytest.ini not found"
        
        with open(pytest_ini, 'r') as f:
            content = f.read()
        
        required_markers = [
            "slow",
            "integration",
            "e2e",
            "docker",
            "network",
            "frontend",
            "backend"
        ]
        
        for marker in required_markers:
            assert marker in content, f"Marker {marker} not found in pytest.ini"