#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/system/commands/edit-config.sh — Editar config.env
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../core/logger.sh"
source "$SCRIPT_DIR/../../../core/input.sh"   # P3: para usar confirm() estandar
source "$SCRIPT_DIR/../../../core/config.sh"

CONFIG_FILE="/app/config/config.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
  err "No se encontro: $CONFIG_FILE"
  err "Primero corre: deploy system setup"
  exit 1
fi

# Detectar editor disponible
editor=""
for candidate in "${EDITOR:-}" nano vim vi; do
  if command -v "$candidate" &>/dev/null; then
    editor="$candidate"
    break
  fi
done

if [[ -z "$editor" ]]; then
  err "No se encontro un editor (nano, vim, vi)."
  err "Editá manualmente: nano $CONFIG_FILE"
  exit 1
fi

echo ""
divider
echo "  EDITANDO $CONFIG_FILE"
echo "  Editor: $editor"
divider
echo ""
warn "CERRAR el editor una vez que termines."
warn "El backend necesita un restart para aplicar los cambios:"
warn "  deploy system services (o desde el menu)"
echo ""

"$editor" "$CONFIG_FILE"

echo ""
if [[ -f "$CONFIG_FILE" ]]; then
  ok "config.env guardado."

  # Revalidar SSL tras la edicion: el operador pudo sacar TrustServerCertificate
  # o poner SslMode estricto -> avisamos ANTES de que el backend falle.
  load_config 2>/dev/null || true
  warn_db_ssl_config

  # Ofrecer reinicio del backend aca mismo (los cambios de config.env solo
  # toman efecto al reiniciar el servicio, que lee config.env via EnvironmentFile).
  if [[ -L "/app/backend/current" ]]; then
    echo ""
    log "El backend lee config.env al arrancar — los cambios necesitan un reinicio."
    # P3: usa el confirm() estandar (maneja Ctrl+C/EOF de forma controlada).
    if confirm "¿Reiniciar el servicio backend ahora?"; then
      if systemctl restart backend; then
        ok "Backend reiniciado. Nuevas variables activas."
      else
        err "No se pudo reiniciar backend. Revisa: journalctl -u backend -n 50 --no-pager"
      fi
    else
      log "Sin reiniciar. Para aplicar despues: deploy system services (o systemctl restart backend)"
    fi
  else
    echo ""
    log "Backend aun no desplegado. Los cambios aplicaran cuando lo instales/reinicies."
  fi
else
  err "Algo salio mal. El archivo no existe."
  exit 1
fi
echo ""
