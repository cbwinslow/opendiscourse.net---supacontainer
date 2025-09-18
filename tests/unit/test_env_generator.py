"""
Tests for the environment file generator.
"""
import os
import tempfile
from scripts.generate_env import generate_secure_password, generate_env_content

def test_generate_secure_password():
    """Test that secure passwords are generated correctly."""
    # Test default length
    password = generate_secure_password()
    assert len(password) == 32
    
    # Test custom length
    password = generate_secure_password(16)
    assert len(password) == 16
    
    # Test that passwords only contain alphanumeric characters when avoid_symbols=True
    password = generate_secure_password(50, avoid_symbols=True)
    assert password.isalnum()
    
    # Test that passwords are different each time
    password1 = generate_secure_password()
    password2 = generate_secure_password()
    assert password1 != password2

def test_generate_env_content():
    """Test that env content is generated correctly."""
    content = generate_env_content("test.example.com", "test@example.com")
    
    # Check that content contains required variables
    assert "DOMAIN=\"test.example.com\"" in content
    assert "EMAIL=\"test@example.com\"" in content
    
    # Check that passwords are present and properly formatted
    assert "POSTGRES_PASSWORD=\"" in content
    assert "JWT_SECRET=\"" in content
    assert "ANON_KEY=\"" in content
    
    # Check that all passwords avoid problematic symbols
    lines = content.split('\n')
    password_lines = [line for line in lines if ('_PASSWORD="' in line or '_KEY="' in line or '_SECRET="' in line) and '=' in line and line.split('=', 1)[1].strip().strip('"')]
    
    for line in password_lines:
        # Extract the password value
        if '=' in line:
            value = line.split('=', 1)[1].strip().strip('"')
            # Skip empty values
            if value:
                # Check that it only contains alphanumeric characters
                assert value.isalnum(), f"Password contains problematic characters: {value}"

def test_generate_env_file():
    """Test that we can generate an env file."""
    with tempfile.TemporaryDirectory() as tmpdir:
        env_file = os.path.join(tmpdir, ".env")
        
        # Generate content
        content = generate_env_content("opendiscourse.net", "blaine.winslow@gmail.com")
        
        # Write to file
        with open(env_file, "w") as f:
            f.write(content)
        
        # Verify file exists
        assert os.path.exists(env_file)
        
        # Read and verify content
        with open(env_file, "r") as f:
            file_content = f.read()
        
        assert "DOMAIN=\"opendiscourse.net\"" in file_content
        assert "EMAIL=\"blaine.winslow@gmail.com\"" in file_content