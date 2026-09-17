# Shared compose file list for the App VM stack (Kafka + apps).
# Sourced by up-all.sh and down-all.sh so the two never drift apart.
# Not executable on its own — must be sourced with ROOT_DIR already set.

COMPOSE_FILES=(
    -f "$ROOT_DIR/kafka/compose.yml"
    -f "$ROOT_DIR/apps/fix-initiator/compose.yml"
    -f "$ROOT_DIR/apps/itch-service/compose.yml"
    -f "$ROOT_DIR/apps/itch-chart-service/compose.yml"
    -f "$ROOT_DIR/apps/oms-admin/compose.yml"
    -f "$ROOT_DIR/apps/frontend/compose.yml"
    -f "$ROOT_DIR/apps/oms-admin-front/compose.yml"
)
