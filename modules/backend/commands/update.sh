#!/usr/bin/env bash
set -euo pipefail
# modules/backend/commands/update.sh — Switch backend to any local version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_BASE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$DEPLOY_BASE/core/deployment.sh"

update_component "backend"
