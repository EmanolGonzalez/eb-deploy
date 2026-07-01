#!/usr/bin/env bash
set -euo pipefail
# modules/backend/commands/install.sh — Install backend from /app/artifacts/backend.rar

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_BASE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$DEPLOY_BASE/core/deployment.sh"

install_component "backend"
