#!/usr/bin/env bash
set -euo pipefail
# modules/system/commands/audit.sh — View deploy audit log

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_BASE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$DEPLOY_BASE/core/logger.sh"
source "$DEPLOY_BASE/core/audit.sh"

MODE="${1:-recent}"

case "$MODE" in
  recent) 
    divider
    audit_recent 
    divider
    ;;
  full)   
    divider
    audit_full 
    divider
    ;;
  *)
    echo "Uso: deploy system audit [recent|full]"
    echo "  recent — Ultimas 10 entradas (default)"
    echo "  full   — Log completo"
    ;;
esac
