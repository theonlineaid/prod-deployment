#!/bin/bash
# Installs this VM's cron schedule (stack auto-start + DB backups) into the
# current user's crontab, using this checkout's actual absolute path.
# Safe to re-run: replaces the previously-installed block instead of
# duplicating it.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MARKER_START="# >>> prod-infra-vm cron (managed by scripts/install-cron.sh) >>>"
MARKER_END="# <<< prod-infra-vm cron <<<"

BLOCK="$MARKER_START
50 7 * * * $ROOT_DIR/scripts/up.sh >> $ROOT_DIR/logs/up.log 2>&1
0 8 * * * cd $ROOT_DIR && ./scripts/backup-mongo.sh >> logs/backup-mongo.log 2>&1
5 8 * * * cd $ROOT_DIR && ./scripts/backup-postgres.sh >> logs/backup-postgres.log 2>&1
$MARKER_END"

mkdir -p "$ROOT_DIR/logs"

EXISTING="$(crontab -l 2>/dev/null || true)"
WITHOUT_BLOCK="$(echo "$EXISTING" | awk -v s="$MARKER_START" -v e="$MARKER_END" '
    $0 == s { skip=1; next }
    $0 == e { skip=0; next }
    skip != 1 { print }
')"

{ echo "$WITHOUT_BLOCK"; echo "$BLOCK"; } | awk 'NF' | crontab -

echo "Installed for $(whoami)@$(hostname) at $ROOT_DIR:"
echo ""
crontab -l
