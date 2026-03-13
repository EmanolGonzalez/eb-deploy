#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_MODE=install bash "$SCRIPT_DIR/deploy.sh" "$@"
