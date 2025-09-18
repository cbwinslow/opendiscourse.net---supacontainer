#!/usr/bin/env python3
"""
Environment file generator for OpenDiscourse.
Generates a robust .env file with strong secrets and proper configuration.
"""

import os
import secrets
import string
import argparse
from pathlib import Path

def generate_secure_password(length=32, avoid_symbols=True):
    """
    Generate a secure password.
    
    Args:
        length (int): Length of the password
        avoid_symbols (bool): If True, avoid symbols that might cause issues in some contexts
    
    Returns:
        str: Generated password
    """
    if avoid_symbols:
        # Use only alphanumeric characters to avoid issues with shell interpretation
        alphabet = string.ascii_letters + string.digits
    else:
        # Include some safe symbols
        alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    
    return ''.join(secrets.choice(alphabet) for _ in range(length))

def generate_env_content(domain="opendiscourse.net", email="blaine.winslow@gmail.com"):
    """
    Generate the content for the .env file.
    
    Args:
        domain (str): Domain for the deployment
        email (str): Email for Let's Encrypt and other services
    
    Returns:
        str: Content for the .env file
    """
    # Generate secure passwords and keys
    postgres_password = generate_secure_password(32, avoid_symbols=True)
    neo4j_password = generate_secure_password(32, avoid_symbols=True)
    jwt_secret = generate_secure_password(64, avoid_symbols=True)
    anon_key = generate_secure_password(64, avoid_symbols=True)
    service_role_key = generate_secure_password(64, avoid_symbols=True)
    secret_key_base = generate_secure_password(64, avoid_symbols=True)
    
    minio_root_user = generate_secure_password(16, avoid_symbols=True)
    minio_root_password = generate_secure_password(32, avoid_symbols=True)
    minio_access_key = generate_secure_password(16, avoid_symbols=True)
    minio_secret_key = generate_secure_password(32, avoid_symbols=True)
    
    redis_password = generate_secure_password(32, avoid_symbols=True)
    
    grafana_admin_password = generate_secure_password(16, avoid_symbols=True)
    n8n_encryption_key = generate_secure_password(32, avoid_symbols=True)
    flowise_password = generate_secure_password(16, avoid_symbols=True)
    
    localai_api_key = generate_secure_password(64, avoid_symbols=True)
    
    # Create the .env content
    env_content = f"""# OpenDiscourse Environment Configuration
# Generated on demand

# Core Configuration
DOMAIN="{domain}"
EMAIL="{email}"
SITE_URL="https://{domain}"

# Database Configuration
POSTGRES_PASSWORD="{postgres_password}"
POSTGRES_DB="postgres"
NEO4J_PASSWORD="{neo4j_password}"

# Supabase Configuration
JWT_SECRET="{jwt_secret}"
ANON_KEY="{anon_key}"
SERVICE_ROLE_KEY="{service_role_key}"
SECRET_KEY_BASE="{secret_key_base}"

# MinIO Configuration
MINIO_ROOT_USER="{minio_root_user}"
MINIO_ROOT_PASSWORD="{minio_root_password}"
MINIO_ACCESS_KEY="{minio_access_key}"
MINIO_SECRET_KEY="{minio_secret_key}"

# Redis Configuration
REDIS_PASSWORD="{redis_password}"

# Service Passwords
GRAFANA_ADMIN_PASSWORD="{grafana_admin_password}"
N8N_ENCRYPTION_KEY="{n8n_encryption_key}"
FLOWISE_PASSWORD="{flowise_password}"

# AI Services
LOCALAI_API_KEY="{localai_api_key}"

# OAuth2 Proxy (if needed)
OAUTH2_PROXY_CLIENT_ID=""
OAUTH2_PROXY_CLIENT_SECRET=""
OAUTH2_PROXY_COOKIE_SECRET="{generate_secure_password(32, avoid_symbols=True)}"

# Traefik Configuration
TRAEFIK_HTTP_PORT=80
TRAEFIK_HTTPS_PORT=443

# Backup Configuration
BACKUP_RETENTION_DAYS=30

# Feature Flags
ENABLE_MONITORING=true
ENABLE_LOGGING=true
"""
    
    return env_content

def main():
    """Main function to generate the .env file."""
    parser = argparse.ArgumentParser(description="Generate .env file for OpenDiscourse")
    parser.add_argument("--domain", default="opendiscourse.net", help="Domain for the deployment")
    parser.add_argument("--email", default="blaine.winslow@gmail.com", help="Email for services")
    parser.add_argument("--output", default=".env", help="Output file path")
    parser.add_argument("--force", action="store_true", help="Overwrite existing file")
    
    args = parser.parse_args()
    
    # Check if file exists
    output_path = Path(args.output)
    if output_path.exists() and not args.force:
        print(f"File {args.output} already exists. Use --force to overwrite.")
        return 1
    
    # Generate the content
    env_content = generate_env_content(args.domain, args.email)
    
    # Write to file
    with open(args.output, "w") as f:
        f.write(env_content)
    
    print(f"Generated {args.output} with secure credentials")
    print(f"Domain: {args.domain}")
    print(f"Email: {args.email}")
    
    return 0

if __name__ == "__main__":
    exit(main())