#!/bin/bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Configuration
STACK_DIR="/opt/opendiscourse"
ENV_FILE="$STACK_DIR/.env"

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found in $STACK_DIR"
    exit 1
fi

# Generate JWT secret if not exists
if ! grep -q '^JWT_SECRET=' "$ENV_FILE"; then
    JWT_SECRET=$(openssl rand -hex 32)
    echo "JWT_SECRET=$JWT_SECRET" >> "$ENV_FILE"
    echo -e "${GREEN}Generated JWT_SECRET${NC}"
fi

# Generate anon key if not exists
if ! grep -q '^ANON_KEY=' "$ENV_FILE"; then
    ANON_KEY=$(openssl rand -hex 32)
    echo "ANON_KEY=$ANON_KEY" >> "$ENV_FILE"
    echo -e "${GREEN}Generated ANON_KEY${NC}"
fi

# Generate service role key if not exists
if ! grep -q '^SERVICE_ROLE_KEY=' "$ENV_FILE"; then
    SERVICE_ROLE_KEY=$(openssl rand -hex 32)
    echo "SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY" >> "$ENV_FILE"
    echo -e "${GREEN}Generated SERVICE_ROLE_KEY${NC}"
fi

# Generate admin API key if not exists
if ! grep -q '^SUPABASE_ADMIN_API_KEY=' "$ENV_FILE"; then
    SUPABASE_ADMIN_API_KEY=$(openssl rand -hex 32)
    echo "SUPABASE_ADMIN_API_KEY=$SUPABASE_ADMIN_API_KEY" >> "$ENV_FILE"
    echo -e "${GREEN}Generated SUPABASE_ADMIN_API_KEY${NC}"
fi

echo -e "${GREEN}Supabase keys have been generated and added to $ENV_FILE${NC}"

# Set proper permissions
chmod 600 "$ENV_FILE"
chown $SUDO_USER:$SUDO_USER "$ENV_FILE"

echo -e "\n${GREEN}Next steps:${NC}"
echo "1. Review the generated keys in $ENV_FILE"
echo "2. Run the Supabase setup script:"
echo "   sudo -E $STACK_DIR/deploy/setup_supabase.sh"
echo "3. Restart your OpenDiscourse stack"
