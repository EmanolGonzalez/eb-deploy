#!/usr/bin/env bash
# =============================================================================
# modules/observability/menu.sh — Observability module menu
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$MODULE_DIR/../../core/logger.sh"
source "$MODULE_DIR/../../core/input.sh"

while true; do
  echo
  divider
  echo "  OBSERVABILITY MENU"
  divider
  menu_select "Selecciona una accion:" \
    "Install (Grafana/Prometheus/Loki/Alloy)" \
    "Status" \
    "Upgrade" \
    "Volver al menu principal"

  case "$MENU_SELECTION" in
    "Install (Grafana/Prometheus/Loki/Alloy)") bash "$MODULE_DIR/commands/install.sh" ;;
    "Status")                                  bash "$MODULE_DIR/commands/status.sh" ;;
    "Upgrade")                                 bash "$MODULE_DIR/commands/upgrade.sh" ;;
    *) exit 0 ;;
  esac

  echo
  read -rp "Presiona Enter para continuar..." _
done
