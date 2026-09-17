#!/bin/bash
# Backs up the PostgreSQL container defined in ../compose.yml.
# Usage: scripts/backup-postgres.sh
# Env overrides: BACKUP_ROOT (default ../backups), RETENTION_DAYS (default 7)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1090
source "$ROOT_DIR/env/infra.env"

BACKUP_ROOT="${BACKUP_ROOT:-$ROOT_DIR/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

POSTGRES_CONTAINER="${OMS_DB_HOST}"
POSTGRES_DIR="$BACKUP_ROOT/postgres"
mkdir -p "$POSTGRES_DIR"

if ! docker ps --format '{{.Names}}' | grep -qx "$POSTGRES_CONTAINER"; then
    echo "Error: container '$POSTGRES_CONTAINER' is not running. Start it first:" >&2
    echo "  scripts/up.sh" >&2
    exit 1
fi

echo "Dumping PostgreSQL ($POSTGRES_CONTAINER)..."
POSTGRES_OUT="$POSTGRES_DIR/postgres_${TIMESTAMP}.sql.gz"
docker exec -e PGPASSWORD="$OMS_DB_PASSWORD" "$POSTGRES_CONTAINER" \
    pg_dump -U "$OMS_DB_USER_NAME" -d "$OMS_DB_NAME" | gzip > "$POSTGRES_OUT"
echo "  -> $POSTGRES_OUT"

echo "Pruning PostgreSQL backups older than ${RETENTION_DAYS} days..."
find "$POSTGRES_DIR" -name '*.sql.gz' -mtime "+${RETENTION_DAYS}" -print -delete

echo "PostgreSQL backup complete."
