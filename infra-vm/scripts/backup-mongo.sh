#!/bin/bash
# Backs up the MongoDB container defined in ../compose.yml.
# Usage: scripts/backup-mongo.sh
# Env overrides: BACKUP_ROOT (default ../backups), RETENTION_DAYS (default 7)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1090
source "$ROOT_DIR/env/infra.env"

BACKUP_ROOT="${BACKUP_ROOT:-$ROOT_DIR/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

MONGO_CONTAINER="prod-mongodb"
MONGO_DIR="$BACKUP_ROOT/mongodb"
mkdir -p "$MONGO_DIR"

if ! docker ps --format '{{.Names}}' | grep -qx "$MONGO_CONTAINER"; then
    echo "Error: container '$MONGO_CONTAINER' is not running. Start it first:" >&2
    echo "  scripts/up.sh" >&2
    exit 1
fi

echo "Dumping MongoDB ($MONGO_CONTAINER)..."
MONGO_OUT="$MONGO_DIR/mongo_${TIMESTAMP}.archive.gz"
docker exec "$MONGO_CONTAINER" mongodump \
    --username "$MONGODB_USERNAME" \
    --password "$MONGODB_PASSWORD" \
    --authenticationDatabase admin \
    --archive --gzip > "$MONGO_OUT"
echo "  -> $MONGO_OUT"

echo "Pruning MongoDB backups older than ${RETENTION_DAYS} days..."
find "$MONGO_DIR" -name '*.archive.gz' -mtime "+${RETENTION_DAYS}" -print -delete

echo "MongoDB backup complete."
