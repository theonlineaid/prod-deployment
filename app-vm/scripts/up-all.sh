#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=./compose-files.sh
source "$SCRIPT_DIR/compose-files.sh"

echo "======================================"
echo " Starting prod app-vm stack"
echo "======================================"

echo ""
echo "[1/3] Starting Kafka + apps..."
docker compose "${COMPOSE_FILES[@]}" --profile fix up -d --pull missing --wait

echo ""
echo "[2/3] Starting local monitoring agents..."
docker compose -f docker-compose.monitoring-agent.yml up -d --pull missing --wait

echo ""
echo "[3/3] Starting nginx reverse proxy..."
docker compose -f docker-compose.nginx.yml up -d --pull missing --wait

echo ""
echo "======================================"
echo " app-vm stack started"
echo "======================================"
