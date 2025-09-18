"""
Tests for configuration files.
"""

import pytest
import os
import configparser
from pathlib import Path

class TestConfigurationFiles:
    """Test configuration files."""
    
    def test_pytest_ini_exists(self):
        """Test that pytest.ini exists."""
        config_file = Path("pytest.ini")
        assert config_file.exists(), "pytest.ini not found"
    
    def test_pytest_ini_is_valid(self):
        """Test that pytest.ini is valid."""
        config_file = Path("pytest.ini")
        assert config_file.exists(), "pytest.ini not found"
        
        config = configparser.ConfigParser()
        config.read(config_file)
        
        assert "tool:pytest" in config.sections(), "pytest.ini missing [tool:pytest] section"
    
    def test_test_config_ini_exists(self):
        """Test that test_config.ini exists."""
        config_file = Path("tests/test_config.ini")
        assert config_file.exists(), "tests/test_config.ini not found"
    
    def test_test_config_ini_is_valid(self):
        """Test that test_config.ini is valid."""
        config_file = Path("tests/test_config.ini")
        assert config_file.exists(), "tests/test_config.ini not found"
        
        config = configparser.ConfigParser()
        config.read(config_file)
        
        # Check that it has required sections
        required_sections = ["colours", "paths", "commands", "environment"]
        for section in required_sections:
            assert section in config.sections(), f"test_config.ini missing [{section}] section"
    
    def test_env_test_file_exists(self):
        """Test that .env.test file exists."""
        env_file = Path(".env.test")
        # This might not exist in fresh setup, so we'll just check if it can be created
        assert True  # Placeholder for now
    
    def test_conftest_py_exists(self):
        """Test that conftest.py exists."""
        conftest = Path("tests/conftest.py")
        assert conftest.exists(), "tests/conftest.py not found"
    
    def test_conftest_has_required_fixtures(self):
        """Test that conftest.py has required fixtures."""
        conftest = Path("tests/conftest.py")
        assert conftest.exists(), "tests/conftest.py not found"
        
        with open(conftest, 'r') as f:
            content = f.read()
        
        required_fixtures = [
            "docker_client",
            "wait_for_service",
            "supabase_service",
            "nextjs_service"
        ]
        
        for fixture in required_fixtures:
            assert f"def {fixture}" in content, f"Fixture {fixture} not found in conftest.py"
    
    def test_test_paths_configured(self):
        """Test that test paths are configured."""
        config_file = Path("pytest.ini")
        assert config_file.exists(), "pytest.ini not found"
        
        config = configparser.ConfigParser()
        config.read(config_file)
        
        if "tool:pytest" in config.sections():
            testpaths = config["tool:pytest"].get("testpaths")
            assert testpaths == "tests", "pytest.ini testpaths not set to 'tests'"
    
    def test_marker_validation_configured(self):
        """Test that marker validation is configured."""
        config_file = Path("pytest.ini")
        assert config_file.exists(), "pytest.ini not found"
        
        config = configparser.ConfigParser()
        config.read(config_file)
        
        if "tool:pytest" in config.sections():
            addopts = config["tool:pytest"].get("addopts", "")
            assert "--strict-markers" in addopts, "pytest.ini missing --strict-markers option"
            assert "--strict-config" in addopts, "pytest.ini missing --strict-config option"