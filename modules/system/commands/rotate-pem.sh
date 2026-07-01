#!/usr/bin/env bash
set -e
# =============================================================================
# modules/system/commands/rotate-pem.sh — Rotate RSA private key
# =============================================================================
# Generates a new RSA 4096-bit key, saves it to /app/secrets/rsa-private-key.pem,
# removes Cryptography__RsaPrivateKey from config.env (backend reads file directly),
# and restarts the backend service.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../core/logger.sh"
source "$SCRIPT_DIR/../../../core/input.sh"
source "$SCRIPT_DIR/../../../core/config.sh"
source "$SCRIPT_DIR/../../../core/service.sh"

SECRETS_DIR="/app/secrets"
PEM_PATH="$SECRETS_DIR/rsa-private-key.pem"
BACKUP_DIR="/app/deploy/storage/backups"
local_ts="$(date +%Y%m%d_%H%M%S)"
local_backup=""

# --- Main ---

if ! command -v openssl &>/dev/null; then
  err "openssl no disponible. No se puede generar la clave RSA."
  exit 1
fi

load_config || true

echo
divider
echo "  ROTAR CLAVE RSA"
divider
echo
warn "Esto generara una nueva clave RSA de 4096 bits."
warn "El servicio backend se reiniciara automaticamente."
echo

menu_select "Confirmar accion:" \
  "Cancelar" \
  "SI, deseo rotar la clave RSA y entiendo que se cerraran las sesiones"

if [[ "$MENU_SELECTION" != "SI, deseo rotar la clave RSA y entiendo que se cerraran las sesiones" ]]; then
  log "Operacion cancelada."
  exit 0
fi

# 1. Backup existing key
if [[ -f "$PEM_PATH" ]]; then
  mkdir -p "$BACKUP_DIR"
  local_backup="$BACKUP_DIR/rsa-private-key.pem.$local_ts"
  cp "$PEM_PATH" "$local_backup"
  chmod 400 "$local_backup"
  ok "Backup de clave anterior: $local_backup"
else
  log "No existe clave anterior. Se creara una nueva."
fi

# 2. Generate new RSA key
mkdir -p "$SECRETS_DIR"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$PEM_PATH" 2>/dev/null
if [[ $? -ne 0 ]]; then
  err "Fallo al generar la clave RSA."
  exit 1
fi

chmod 400 "$PEM_PATH"
ok "Nueva clave RSA generada en $PEM_PATH (chmod 400)"

# 3. Remove Cryptography__RsaPrivateKey from config.env (no longer needed)
if grep -q "^Cryptography__RsaPrivateKey=" "$CONFIG_FILE" 2>/dev/null; then
  # Replace with empty value to keep the key but remove the secret
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^Cryptography__RsaPrivateKey= ]]; then
      printf '%s\n' "# Cryptography__RsaPrivateKey removed — backend reads from $PEM_PATH" >> "$tmp"
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$CONFIG_FILE"
  mv "$tmp" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  ok "Cryptography__RsaPrivateKey eliminado de config.env"
else
  log "Cryptography__RsaPrivateKey ya no esta en config.env"
fi

# 4. Restart backend
echo
log "Reiniciando servicio backend..."
sudo systemctl restart backend
if [[ $? -eq 0 ]]; then
  ok "Servicio backend reiniciado"
else
  err "Fallo al reiniciar backend. Revisar con: deploy system services"
  exit 1
fi

# 5. Verify
sleep 2
if sudo systemctl is-active --quiet backend; then
  ok "Backend corriendo correctamente con la nueva clave"
else
  err "Backend no arranco. Revisar logs: deploy system services -> logs"
  if [[ -n "$local_backup" ]]; then
    warn "La clave anterior esta en: $local_backup"
  fi
  exit 1
fi

echo
divider
ok "Rotacion de clave RSA completada"
divider
echo
