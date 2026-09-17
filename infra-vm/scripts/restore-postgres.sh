#!/bin/bash
# Restores a PostgreSQL dump produced by scripts/backup-postgres.sh.
# Usage: scripts/restore-postgres.sh <path-to-.sql.gz>
#
# WARNING: this overwrites data in the target database. Confirm before
# running against real data.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1090
source "$ROOT_DIR/env/infra.env"

[ $# -eq 1 ] || { echo "Usage: $0 <backup-file>" >&2; exit 1; }
FILE="$1"
[ -f "$FILE" ] || { echo "Error: file not found: $FILE" >&2; exit 1; }

POSTGRES_CONTAINER="${OMS_DB_HOST}"
echo "Restoring PostgreSQL from $FILE into container '$POSTGRES_CONTAINER' database '$OMS_DB_NAME'..."
read -rp "This will overwrite data in database '$OMS_DB_NAME'. Continue? [y/N] " confirm
[ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || { echo "Aborted."; exit 1; }

gunzip -c "$FILE" | docker exec -i -e PGPASSWORD="$OMS_DB_PASSWORD" "$POSTGRES_CONTAINER" \
    psql -U "$OMS_DB_USER_NAME" -d "$OMS_DB_NAME"

echo "PostgreSQL restore complete."
