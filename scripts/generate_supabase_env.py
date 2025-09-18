#!/usr/bin/env python3
"""
Supabase Environment File Generator
Generates a robust .env file for Supabase self-hosting with secure credentials.
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

def generate_supabase_env_content():
    """
    Generate the content for the Supabase .env file.
    
    Returns:
        str: Content for the .env file
    """
    # Generate secure passwords and keys
    postgres_password = generate_secure_password(32, avoid_symbols=True)
    jwt_secret = generate_secure_password(64, avoid_symbols=True)
    anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtZGVtbyIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE"
    service_role_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q"
    dashboard_password = generate_secure_password(16, avoid_symbols=True)
    secret_key_base = generate_secure_password(64, avoid_symbols=True)
    vault_enc_key = generate_secure_password(32, avoid_symbols=True)
    logflare_public_token = generate_secure_password(32, avoid_symbols=True)
    logflare_private_token = generate_secure_password(32, avoid_symbols=True)
    
    # Create the .env content
    env_content = f"""############
# Secrets
# YOU MUST CHANGE THESE BEFORE GOING INTO PRODUCTION
############

POSTGRES_PASSWORD={postgres_password}
JWT_SECRET={jwt_secret}
ANON_KEY={anon_key}
SERVICE_ROLE_KEY={service_role_key}
DASHBOARD_USERNAME=supabase
DASHBOARD_PASSWORD={dashboard_password}
SECRET_KEY_BASE={secret_key_base}
VAULT_ENC_KEY={vault_enc_key}


############
# Database - You can change these to any PostgreSQL database that has logical replication enabled.
############

POSTGRES_HOST=db
POSTGRES_DB=postgres
POSTGRES_PORT=5432


############
# Supavisor -- Database pooler
############
# Port Supavisor listens on for transaction pooling connections
POOLER_PROXY_PORT_TRANSACTION=6543
# Maximum number of PostgreSQL connections Supavisor opens per pool
POOLER_DEFAULT_POOL_SIZE=20
# Maximum number of client connections Supavisor accepts per pool
POOLER_MAX_CLIENT_CONN=100
# Unique tenant identifier
POOLER_TENANT_ID=opendiscourse-tenant
# Pool size for internal metadata storage used by Supavisor
# This is separate from client connections and used only by Supavisor itself
POOLER_DB_POOL_SIZE=5


############
# API Proxy - Configuration for the Kong Reverse proxy.
############

KONG_HTTP_PORT=8000
KONG_HTTPS_PORT=8443


############
# API - Configuration for PostgREST.
############

PGRST_DB_SCHEMAS=public,storage,graphql_public


############
# Auth - Configuration for the GoTrue authentication server.
############

## General
SITE_URL=http://localhost:3000
ADDITIONAL_REDIRECT_URLS=
JWT_EXPIRY=3600
DISABLE_SIGNUP=false
API_EXTERNAL_URL=http://localhost:8000

## Mailer Config
MAILER_URLPATHS_CONFIRMATION="/auth/v1/verify"
MAILER_URLPATHS_INVITE="/auth/v1/verify"
MAILER_URLPATHS_RECOVERY="/auth/v1/verify"
MAILER_URLPATHS_EMAIL_CHANGE="/auth/v1/verify"

## Email auth
ENABLE_EMAIL_SIGNUP=true
ENABLE_EMAIL_AUTOCONFIRM=false
SMTP_ADMIN_EMAIL=admin@example.com
SMTP_HOST=supabase-mail
SMTP_PORT=2500
SMTP_USER=fake_mail_user
SMTP_PASS=fake_mail_password
SMTP_SENDER_NAME=fake_sender
ENABLE_ANONYMOUS_USERS=false

## Phone auth
ENABLE_PHONE_SIGNUP=true
ENABLE_PHONE_AUTOCONFIRM=true


############
# Studio - Configuration for the Dashboard
############

STUDIO_DEFAULT_ORGANIZATION=OpenDiscourse Organization
STUDIO_DEFAULT_PROJECT=OpenDiscourse Project

STUDIO_PORT=3000
# replace if you intend to use Studio outside of localhost
SUPABASE_PUBLIC_URL=http://localhost:8000

# Enable webp support
IMGPROXY_ENABLE_WEBP_DETECTION=true

# Add your OpenAI API key to enable SQL Editor Assistant
OPENAI_API_KEY=


############
# Functions - Configuration for Functions
############
# NOTE: VERIFY_JWT applies to all functions. Per-function VERIFY_JWT is not supported yet.
FUNCTIONS_VERIFY_JWT=false


############
# Logs - Configuration for Analytics
# Please refer to https://supabase.com/docs/reference/self-hosting-analytics/introduction
############

# Change vector.toml sinks to reflect this change
# these cannot be the same value
LOGFLARE_PUBLIC_ACCESS_TOKEN={logflare_public_token}
LOGFLARE_PRIVATE_ACCESS_TOKEN={logflare_private_token}

# Docker socket location - this value will differ depending on your OS
DOCKER_SOCKET_LOCATION=/var/run/docker.sock

# Google Cloud Project details
GOOGLE_PROJECT_ID=GOOGLE_PROJECT_ID
GOOGLE_PROJECT_NUMBER=GOOGLE_PROJECT_NUMBER
"""
    
    return env_content

def main():
    """Main function to generate the Supabase .env file."""
    parser = argparse.ArgumentParser(description="Generate .env file for Supabase self-hosting")
    parser.add_argument("--output", default=".env", help="Output file path")
    parser.add_argument("--force", action="store_true", help="Overwrite existing file")
    
    args = parser.parse_args()
    
    # Check if file exists
    output_path = Path(args.output)
    if output_path.exists() and not args.force:
        print(f"File {args.output} already exists. Use --force to overwrite.")
        return 1
    
    # Generate the content
    env_content = generate_supabase_env_content()
    
    # Write to file
    with open(args.output, "w") as f:
        f.write(env_content)
    
    print(f"Generated {args.output} with secure credentials for Supabase")
    
    return 0

if __name__ == "__main__":
    exit(main())