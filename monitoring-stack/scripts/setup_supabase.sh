#!/bin/bash
set -e

# Create required directories
mkdir -p supabase/init supabase/functions supabase/storage

# Generate random secrets if not set
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$(openssl rand -base64 32)}
export JWT_SECRET=${JWT_SECRET:-$(openssl rand -base64 32)}
export ANON_KEY=${ANON_KEY:-$(openssl rand -base64 32)}
export SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY:-$(openssl rand -base64 32)}
export SECRET_KEY_BASE=${SECRET_KEY_BASE:-$(openssl rand -base64 64)}

# Create .env file
cat > .env <<EOL
# Supabase Environment Variables
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_USER=postgres
POSTGRES_DB=postgres
JWT_SECRET=${JWT_SECRET}
ANON_KEY=${ANON_KEY}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}
SECRET_KEY_BASE=${SECRET_KEY_BASE}

# For client applications
NEXT_PUBLIC_SUPABASE_URL=http://localhost:8000
NEXT_PUBLIC_SUPABASE_ANON_KEY=${ANON_KEY}
NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}
EOL

echo "✅ Supabase environment setup complete!"
echo "🔑 Generated secrets have been saved to .env"
echo "🚀 Start the stack with: docker-compose -f docker-compose.supabase.yml up -d"
