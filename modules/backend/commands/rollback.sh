#!/usr/bin/env bash
set -euo pipefail
# modules/backend/commands/rollback.sh — Roll backend back one step

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_BASE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$DEPLOY_BASE/core/deployment.sh"

rollback_component "backend"
