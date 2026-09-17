#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=./compose-files.sh
source "$SCRIPT_DIR/compose-files.sh"

if [ "$1" = "-v" ] || [ "$1" = "--volumes" ]; then
    echo "!!! WARNING: this will also DELETE Kafka's data volume !!!"
    read -r -p "Type 'yes' to confirm: " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
    EXTRA_ARGS=(-v)
else
    EXTRA_ARGS=()
fi

echo "======================================"
echo " Stopping prod app-vm stack"
echo "======================================"

echo ""
echo "[1/3] Stopping nginx reverse proxy..."
docker compose -f docker-compose.nginx.yml down

echo ""
echo "[2/3] Stopping monitoring agents..."
docker compose -f docker-compose.monitoring-agent.yml down

echo ""
echo "[3/3] Stopping app + kafka stack..."
docker compose "${COMPOSE_FILES[@]}" down "${EXTRA_ARGS[@]}"

echo ""
echo "======================================"
echo " app-vm stack stopped"
echo "======================================"
