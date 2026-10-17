#!/usr/bin/env bash
# =============================================================================
# modules/database/lib/db-common.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_BASE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$DB_BASE/core/logger.sh"
source "$DB_BASE/core/input.sh"
source "$DB_BASE/core/config.sh"
source "$DB_BASE/core/db.sh"
source "$DB_BASE/core/system.sh"

# Respetar un CONFIG_FILE pre-establecido (mismo patron que core/config.sh);
# en el server va sin definir y queda el default de produccion.
CONFIG_FILE="${CONFIG_FILE:-/app/config/config.env}"
