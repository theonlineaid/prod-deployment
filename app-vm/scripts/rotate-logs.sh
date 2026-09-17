#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LOGROTATE_CONF="$ROOT_DIR/logs/.logrotate.generated.conf"
mkdir -p "$ROOT_DIR/logs"
cat > "$LOGROTATE_CONF" << EOF
$ROOT_DIR/logs/oms-admin/*.log
$ROOT_DIR/logs/itch-service/*.log
$ROOT_DIR/logs/fix-initiator/message.log
$ROOT_DIR/logs/fix-initiator/message_order.log
$ROOT_DIR/logs/fix-initiator/queue.log
$ROOT_DIR/logs/fix-initiator/all.log
{
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF

logrotate --state "$ROOT_DIR/logs/.logrotate-state" "$LOGROTATE_CONF"

# oms-admin (Django TimedRotatingFileHandler) and itch-cpp rotate their own
# active log file on their own schedule, producing dated/numbered copies
# alongside the live file logrotate above already handles. Prune those
# down to the same 7-day window here.
find "$ROOT_DIR/logs" -type f -mtime +7 \( -name "*.log.*" -o -name "*.gz" \) -delete
