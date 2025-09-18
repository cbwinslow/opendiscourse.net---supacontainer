"""
Tests for environment verification script.
"""

import pytest
import os
import tempfile
from pathlib import Path
from scripts.verify_env import verify_env_file

class TestEnvironmentVerification:
    """Test environment verification script."""
    
    def test_verify_env_file_with_safe_passwords(self):
        """Test verifying env file with safe passwords."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
            f.write("""
POSTGRES_PASSWORD=testpassword123
JWT_SECRET=testsecretkeywithatleast32characterslong
DASHBOARD_PASSWORD=testdashboard123
VAULT_ENC_KEY=testencryptionkey32chars
""")
            f.flush()
            
            result = verify_env_file(f.name)
            assert result == True
            
            # Clean up
            os.unlink(f.name)
    
    def test_verify_env_file_with_problematic_symbols(self):
        """Test verifying env file with problematic symbols."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
            f.write("""
POSTGRES_PASSWORD=test"password123
JWT_SECRET=test$ecretkey
DASHBOARD_PASSWORD=test'dashboard123
""")
            f.flush()
            
            result = verify_env_file(f.name)
            assert result == False
            
            # Clean up
            os.unlink(f.name)
    
    def test_verify_env_file_with_jwt_tokens(self):
        """Test verifying env file with JWT tokens."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
            f.write("""
POSTGRES_PASSWORD=testpassword123
JWT_SECRET=testsecretkeywithatleast32characterslong
ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtZGVtbyIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE
SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q
""")
            f.flush()
            
            result = verify_env_file(f.name)
            assert result == True  # JWT tokens are expected to have special characters
            
            # Clean up
            os.unlink(f.name)
    
    def test_verify_env_file_empty_values(self):
        """Test verifying env file with empty values."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
            f.write("""
POSTGRES_PASSWORD=testpassword123
EMPTY_VALUE=
JWT_SECRET=testsecretkeywithatleast32characterslong
""")
            f.flush()
            
            result = verify_env_file(f.name)
            assert result == True  # Empty values should be skipped
            
            # Clean up
            os.unlink(f.name)