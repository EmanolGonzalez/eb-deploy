#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/system/commands/setup.sh — Initial server setup
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/system-common.sh"

# Delegate to the standalone setup script
bash "/app/deploy/setup/setup-server.sh"
