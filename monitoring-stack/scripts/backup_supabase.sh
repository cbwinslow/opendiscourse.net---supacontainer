#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Set default values
BACKUP_DIR="./backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/supabase_backup_${TIMESTAMP}.sql"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Check if required environment variables are set
if [ -z "${POSTGRES_USER}" ] || [ -z "${POSTGRES_PASSWORD}" ] || [ -z "${POSTGRES_DB}" ]; then
    echo "Error: Required environment variables not set. Please check your .env file."
    exit 1
fi

# Create backup
echo "Creating backup of Supabase database..."
PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
    -h localhost \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    -F c \
    -f "${BACKUP_FILE}" \
    --exclude-table-data='storage.objects' \
    --exclude-table-data='storage.migrations' \
    --exclude-table-data='auth.audit_log_entries' \
    --exclude-table-data='auth.flow_state' \
    --exclude-table-data='auth.identities' \
    --exclude-table-data='auth.refresh_tokens' \
    --exclude-table-data='auth.sessions' \
    --exclude-table-data='realtime.subscription' \
    --exclude-table-data='realtime.events' \
    --exclude-table-data='realtime.metrics' \
    --exclude-table-data='realtime.subscription' \
    --exclude-table-data='realtime.wal_rls'

# Backup storage bucket
STORAGE_BACKUP_DIR="${BACKUP_DIR}/storage_${TIMESTAMP}"
mkdir -p "${STORAGE_BACKUP_DIR}"

echo "Backing up storage bucket..."
# This requires the supabase CLI to be installed
if command -v supabase &> /dev/null; then
    supabase storage download "agent-data" "${STORAGE_BACKUP_DIR}" --recursive
else
    echo "Warning: supabase CLI not found. Skipping storage backup."
fi

# Create a checksum of the backup
sha256sum "${BACKUP_FILE}" > "${BACKUP_FILE}.sha256"

# Compress the backup
gzip "${BACKUP_FILE}"

echo "Backup created: ${BACKUP_FILE}.gz"

# Clean up old backups (keep last 7 days)
find "${BACKUP_DIR}" -name "supabase_backup_*.sql.gz" -type f -mtime +7 -delete
find "${BACKUP_DIR}" -name "storage_*" -type d -mtime +7 -exec rm -rf {} +
