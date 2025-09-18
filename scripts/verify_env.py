#!/usr/bin/env python3
"""
Verification script for OpenDiscourse .env file.
Checks that generated passwords don't contain problematic symbols.
"""

import os
import sys
from pathlib import Path

def verify_env_file(env_path=".env"):
    """
    Verify that the .env file contains only safe passwords.
    
    Args:
        env_path (str): Path to the .env file
    
    Returns:
        bool: True if all passwords are safe, False otherwise
    """
    env_file = Path(env_path)
    if not env_file.exists():
        print(f"Error: {env_path} not found")
        return False
    
    # Read the .env file
    with open(env_file, "r") as f:
        content = f.read()
    
    # Check each line for passwords/keys
    lines = content.split('\n')
    password_lines = [
        line for line in lines 
        if ('_PASSWORD=' in line or '_KEY=' in line or '_SECRET=' in line) 
        and '=' in line 
        and line.split('=', 1)[1].strip().strip('"')
    ]
    
    all_safe = True
    problematic_symbols = ['"', "'", "`", "$", "\\\\", " ", "\t", "\n", "\r"]
    
    # JWT tokens are expected to have special characters, so we'll skip them
    jwt_keys = ['ANON_KEY', 'SERVICE_ROLE_KEY']
    
    for line in password_lines:
        if '=' in line:
            # Extract key and value
            key, value = line.split('=', 1)
            key = key.strip()
            value = value.strip().strip('"')
            
            # Skip empty values
            if not value:
                continue
            
            # Skip JWT tokens as they're expected to have special characters
            if key in jwt_keys:
                print(f"OK: {key} is a JWT token (expected to have special characters)")
                continue
            
            # Check for problematic symbols
            found_symbols = [sym for sym in problematic_symbols if sym in value]
            if found_symbols:
                print(f"WARNING: {key} contains problematic symbols: {found_symbols}")
                all_safe = False
            elif not value.isalnum():
                print(f"WARNING: {key} contains non-alphanumeric characters: {value}")
                all_safe = False
            else:
                print(f"OK: {key} is safe")
    
    return all_safe

def main():
    """Main function."""
    env_path = sys.argv[1] if len(sys.argv) > 1 else ".env"
    
    print(f"Verifying {env_path}...")
    
    if verify_env_file(env_path):
        print("All passwords are safe!")
        return 0
    else:
        print("Some passwords contain problematic characters!")
        return 1

if __name__ == "__main__":
    exit(main())