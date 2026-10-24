#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/system/commands/update-runtimes.sh — Update patched runtimes only
#
# A diferencia de 'deploy system setup' (pensado para la primera instalacion:
# crea el usuario de servicio, genera config.env/secretos, configura nginx y
# systemd), este comando SOLO trae el runtime (.NET) a la version parcheada
# esperada. No toca config.env, secretos, usuarios ni la configuracion de
# nginx/systemd. Pensado para correrse en un servidor ya desplegado cuando
# se publica un parche de seguridad para el SDK .NET.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_BASE="$(cd "$MODULE_DIR/../.." && pwd)"
source "$MODULE_DIR/lib/system-common.sh"

ASSETS_DIR="$DEPLOY_BASE/assets"
# shellcheck source=/dev/null
source "$MODULE_DIR/lib/runtime-install.sh"

require_root

echo -e "\n========================================"
echo -e "  EB Deploy — Actualizar runtimes"
echo -e "========================================\n"

BEFORE_VERSION="$(command -v dotnet &>/dev/null && dotnet --version 2>/dev/null || echo "no instalado")"

install_dotnet

AFTER_VERSION="$(command -v dotnet &>/dev/null && dotnet --version 2>/dev/null || echo "no instalado")"

echo ""
if [[ "$BEFORE_VERSION" != "$AFTER_VERSION" ]]; then
  ok "Runtime .NET actualizado: $BEFORE_VERSION -> $AFTER_VERSION"
  if systemctl is-active --quiet backend 2>/dev/null; then
    warn "backend.service sigue corriendo con el runtime viejo en memoria."
    warn "Para que tome el nuevo runtime: systemctl restart backend"
  fi
else
  ok "Runtime .NET ya estaba en la version esperada ($AFTER_VERSION). Nada que hacer."
fi
