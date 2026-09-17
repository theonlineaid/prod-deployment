#!/bin/bash
# Restores a MongoDB dump produced by scripts/backup-mongo.sh.
# Usage: scripts/restore-mongo.sh <path-to-.archive.gz>
#
# WARNING: this overwrites data in the running container (mongorestore --drop).
# Confirm before running against real data.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1090
source "$ROOT_DIR/env/infra.env"

[ $# -eq 1 ] || { echo "Usage: $0 <backup-file>" >&2; exit 1; }
FILE="$1"
[ -f "$FILE" ] || { echo "Error: file not found: $FILE" >&2; exit 1; }

MONGO_CONTAINER="prod-mongodb"
echo "Restoring MongoDB from $FILE into container '$MONGO_CONTAINER' (--drop)..."
read -rp "This will DROP existing collections before restoring. Continue? [y/N] " confirm
[ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || { echo "Aborted."; exit 1; }

docker exec -i "$MONGO_CONTAINER" mongorestore \
    --username "$MONGODB_USERNAME" \
    --password "$MONGODB_PASSWORD" \
    --authenticationDatabase admin \
    --archive --gzip --drop < "$FILE"

echo "MongoDB restore complete."
