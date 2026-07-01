#!/usr/bin/env bash
# =============================================================================
# modules/system/lib/system-common.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_BASE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$SYSTEM_BASE/core/logger.sh"
source "$SYSTEM_BASE/core/input.sh"
source "$SYSTEM_BASE/core/config.sh"
source "$SYSTEM_BASE/core/service.sh"
source "$SYSTEM_BASE/core/system.sh"
