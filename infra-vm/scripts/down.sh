#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

EXTRA_ARGS=()
if [ "$1" = "-v" ] || [ "$1" = "--volumes" ]; then
    echo "!!! WARNING: this will also DELETE all data volumes (Mongo/Postgres/Redis) !!!"
    read -r -p "Type 'yes' to confirm: " CONFIRM
    [ "$CONFIRM" = "yes" ] || { echo "Aborted."; exit 1; }
    EXTRA_ARGS=(-v)
fi

docker compose --env-file env/infra.env -f compose.yml down "${EXTRA_ARGS[@]}"
