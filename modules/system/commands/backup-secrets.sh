#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/system/commands/backup-secrets.sh — Respaldo cifrado de secretos
# =============================================================================
# Los respaldos de BD son ilegibles sin las claves que viven en ESTA VM. Este
# comando empaqueta las dos fuentes de claves y las cifra con la MISMA
# primitiva de los respaldos de base de datos (openssl enc -aes-256-cbc
# -pbkdf2 con Backup__EncryptionPassphrase, ver modules/database/lib/
# backup-db.sh) para que respaldo y claves se puedan restaurar juntos:
#
#   - /app/config/config.env  (PiiEncryption__HashKeyBase64,
#     Backup__EncryptionPassphrase, password de BD)
#   - /app/secrets/           (rsa-private-key.pem)
#
# DOC-23: el respaldo debe quedar FUERA del servidor (nunca en la misma VM,
# nunca en un repositorio). El destino por defecto es /root/secrets-backups
# (se crea con modo 700) y --out bajo /app exige confirmacion: mismo disco es
# el mismo punto de falla.
#
# Uso:
#   deploy system backup-secrets [--out <dir>]
#   deploy system backup-secrets --verify <archivo.tar.gz.enc>
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../core/logger.sh"
source "$SCRIPT_DIR/../../../core/input.sh"
source "$SCRIPT_DIR/../../../core/config.sh"

# Fuentes del respaldo. CONFIG_FILE ya respeta override de entorno en
# core/config.sh; SECRETS_DIR sigue el mismo patron (overridable en tests).
SECRETS_DIR="${SECRETS_DIR:-/app/secrets}"
DEFAULT_OUT_DIR="/root/secrets-backups"

# Temporales que limpia el trap de EXIT (si algo falla a mitad de camino).
RAW_TMP=""
VERIFY_TMP=""
cleanup() {
  if [[ -n "$RAW_TMP" ]]; then rm -f "$RAW_TMP"; fi
  if [[ -n "$VERIFY_TMP" ]]; then rm -rf "$VERIFY_TMP"; fi
}
trap cleanup EXIT

show_help() {
  cat <<EOF
backup-secrets.sh — Respaldo cifrado de secretos (DOC-23)

Uso:
  deploy system backup-secrets [--out <dir>]
  deploy system backup-secrets --verify <archivo.tar.gz.enc>

Opciones:
  --out <dir>      Directorio de salida (default: $DEFAULT_OUT_DIR, se crea con modo 700)
  --verify <file>  Verifica un respaldo: SHA-256 + prueba de descifrado (lista nombres)
  --help           Muestra esta ayuda

Que respalda:
  - /app/config/config.env   (PiiEncryption__HashKeyBase64, Backup__EncryptionPassphrase, password de BD)
  - /app/secrets/            (rsa-private-key.pem)

Cifrado: openssl enc -aes-256-cbc -pbkdf2 con Backup__EncryptionPassphrase —
la MISMA primitiva de los respaldos de base de datos, asi el respaldo de
secretos y el de BD se restauran con el mismo comando.

DOC-23: el respaldo debe vivir FUERA del servidor (nunca en la misma VM,
nunca en un repositorio). Guarda junto al archivo la passphrase de respaldo.
EOF
}

# is_under_app <ruta> — 0 si la ruta (sin slashes finales) es /app o esta bajo /app.
is_under_app() {
  local p
  p="$(printf '%s' "$1" | sed 's:/*$::')"
  [[ "$p" == "/app" || "$p" == "/app/"* ]]
}

# validate_sources — falla (exit 1) si falta alguna fuente, con la ruta.
validate_sources() {
  if [[ "$CONFIG_FILE" != /* || "$SECRETS_DIR" != /* ]]; then
    err "CONFIG_FILE y SECRETS_DIR deben ser rutas absolutas (recibido: $CONFIG_FILE, $SECRETS_DIR)."
    exit 1
  fi
  if [[ ! -f "$CONFIG_FILE" ]]; then
    err "No existe el archivo de configuracion: $CONFIG_FILE"
    exit 1
  fi
  if [[ ! -d "$SECRETS_DIR" ]]; then
    err "No existe el directorio de secretos: $SECRETS_DIR"
    exit 1
  fi
  if [[ ! -f "$SECRETS_DIR/rsa-private-key.pem" ]]; then
    warn "$SECRETS_DIR/rsa-private-key.pem no esta — revisa que $SECRETS_DIR tenga las claves esperadas."
  fi
}

# secrets_passphrase_ready — 0 si hay passphrase util para descifrar.
# Silencioso: --verify sin config.env (p.ej. off-site) debe degradar, no abortar.
secrets_passphrase_ready() {
  load_config 2>/dev/null || return 1
  [[ -n "${Backup__EncryptionPassphrase:-}" && "${Backup__EncryptionPassphrase:-}" != "CHANGE_ME" ]]
}

# ── backup ───────────────────────────────────────────────────────────────────

cmd_backup() {
  local out_arg="${1:-}"
  local out_dir="${out_arg:-$DEFAULT_OUT_DIR}"

  echo
  divider
  echo "  RESPALDO DE SECRETOS (DOC-23)"
  divider
  echo

  validate_sources

  # Misma clave que los respaldos de BD: el respaldo de secretos y el de la
  # base se cifran con Backup__EncryptionPassphrase (mismo gate que backup.sh).
  load_config "Backup__EncryptionPassphrase" || exit 1
  if [[ "${Backup__EncryptionPassphrase}" == "CHANGE_ME" ]]; then
    err "Backup__EncryptionPassphrase sigue en CHANGE_ME. Corre 'deploy system setup' para autogenerarla."
    exit 1
  fi

  # Resolver destino. El rechazo a /app se hace ANTES de crear nada.
  if [[ "$out_dir" != /* ]]; then
    out_dir="$PWD/$out_dir"
  fi
  local app_confirmed=0
  if is_under_app "$out_dir"; then
    warn "--out apunta bajo /app: mismo disco que lo que se respalda (mismo punto de falla)."
    if confirm "Forzar de todos modos? (DOC-23: el respaldo debe vivir fuera del servidor)"; then
      app_confirmed=1
    else
      err "Cancelado: usa --out fuera de /app (idealmente fuera del servidor)."
      exit 1
    fi
  fi

  if ! mkdir -p "$out_dir"; then
    err "No se pudo crear el directorio de salida: $out_dir"
    exit 1
  fi
  out_dir="$(cd "$out_dir" && pwd -P)"
  # Re-chequeo post-resolucion: un symlink pudo desviar el destino a /app sin
  # que el usuario lo escribiera. Aca no se re-pregunta: se corta.
  if is_under_app "$out_dir" && [[ "$app_confirmed" != "1" ]]; then
    err "El directorio de salida resuelve a $out_dir (bajo /app). Usa otra ubicacion."
    exit 1
  fi
  if ! chmod 700 "$out_dir" 2>/dev/null; then
    warn "No se pudo ajustar el modo 700 en $out_dir."
  fi

  local stamp enc_file raw
  stamp="$(date '+%Y%m%d-%H%M%S')"
  enc_file="$out_dir/secrets-backup-$stamp.tar.gz.enc"
  raw="$(mktemp)"
  RAW_TMP="$raw"

  # Miembros del tar relativos a / (asi el restore con tar -xz -C / repone
  # cada archivo en su ruta original).
  local cfg_member sec_member
  cfg_member="${CONFIG_FILE#/}"
  sec_member="${SECRETS_DIR#/}"

  log "Empaquetando secretos (tar)..."
  if ! tar -C / -czf "$raw" "$cfg_member" "$sec_member"; then
    err "Fallo al crear el tarball de secretos."
    rm -f "$raw" "$enc_file"
    exit 1
  fi

  # Mismas flags que db_create_encrypted_backup (backup-db.sh) para que el
  # descifrado sea identico al de los respaldos de BD.
  log "Cifrando (AES-256, misma primitiva que los respaldos de BD)..."
  if ! openssl enc -aes-256-cbc -pbkdf2 -salt \
        -pass "pass:${Backup__EncryptionPassphrase}" \
        -in "$raw" -out "$enc_file"; then
    err "Fallo el cifrado del respaldo. Descartando archivo parcial."
    rm -f "$raw" "$enc_file"
    exit 1
  fi
  rm -f "$raw"
  RAW_TMP=""
  if ! chmod 600 "$enc_file"; then
    err "No se pudo ajustar el modo 600 en el respaldo. Descartando."
    rm -f "$enc_file"
    exit 1
  fi

  local hash
  hash="$(sha256sum "$enc_file" | awk '{print $1}')"

  echo
  ok "Respaldo de secretos cifrado: $enc_file ($(du -h "$enc_file" | cut -f1))"
  log "SHA-256:"
  echo "  $hash  $(basename "$enc_file")"
  echo
  warn "Copialo FUERA del servidor hoy mismo (DOC-23: nunca en la misma VM, nunca en un repo)."
  warn "Guarda junto al archivo la passphrase de respaldo (Backup__EncryptionPassphrase)."
  warn "Cuando el archivo este a salvo fuera del servidor, elimina la copia local."
  echo
  log "Verificar mas tarde (con el toolkit):"
  echo "  deploy system backup-secrets --verify $(basename "$enc_file")"
  echo
  log "Restaurar SIN el toolkit (VM nueva, como root). Reemplaza <PASSPHRASE> por el valor de Backup__EncryptionPassphrase:"
  echo "  openssl enc -d -aes-256-cbc -pbkdf2 -pass 'pass:<PASSPHRASE>' -in $(basename "$enc_file") | tar -xz -C /"
  log "Ver el contenido sin extraer:"
  echo "  openssl enc -d -aes-256-cbc -pbkdf2 -pass 'pass:<PASSPHRASE>' -in $(basename "$enc_file") | tar -tzf -"
  echo
  divider
}

# ── verify ───────────────────────────────────────────────────────────────────

cmd_verify() {
  local file="$1"

  echo
  divider
  echo "  VERIFICAR RESPALDO DE SECRETOS"
  divider
  echo

  if [[ ! -f "$file" ]]; then
    err "No existe el archivo: $file"
    exit 1
  fi
  if [[ ! -s "$file" ]]; then
    err "El archivo esta vacio: $file"
    exit 1
  fi

  local hash
  hash="$(sha256sum "$file" | awk '{print $1}')"
  log "SHA-256:"
  echo "  $hash  $(basename "$file")"

  # Con passphrase: prueba completa (descifrar + leer el tar). Sin ella
  # (p.ej. verificar off-site sin config.env): solo checksum y estructura,
  # y se avisa que el descifrado no se probo.
  if ! secrets_passphrase_ready; then
    echo
    warn "Verificacion limitada: sin passphrase (config.env sin Backup__EncryptionPassphrase) no se puede probar el descifrado."
    warn "Se verifico solo el checksum y que el archivo exista y no este vacio."
    echo
    return 0
  fi

  VERIFY_TMP="$(mktemp -d)"
  chmod 700 "$VERIFY_TMP"
  local dec
  dec="$VERIFY_TMP/backup.tar.gz"

  if ! openssl enc -d -aes-256-cbc -pbkdf2 \
        -pass "pass:${Backup__EncryptionPassphrase}" \
        -in "$file" -out "$dec" 2>/dev/null; then
    err "No se pudo descifrar: passphrase incorrecta o archivo corrupto."
    exit 1
  fi
  if ! tar -tzf "$dec" > "$VERIFY_TMP/listado.txt" 2>/dev/null; then
    err "El contenido no es un respaldo valido: passphrase incorrecta o archivo corrupto."
    exit 1
  fi

  echo
  ok "Descifrado OK — contenido del respaldo (solo nombres, nunca contenidos):"
  sed 's/^/  /' "$VERIFY_TMP/listado.txt"
  echo
  ok "Verificacion completa: checksum + descifrado + estructura del tar."
}

# ── Main ─────────────────────────────────────────────────────────────────────

OUT_DIR=""
VERIFY_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      [[ $# -ge 2 && -n "${2:-}" ]] || { err "--out requiere un directorio."; exit 2; }
      OUT_DIR="$2"
      shift 2
      ;;
    --verify)
      [[ $# -ge 2 && -n "${2:-}" ]] || { err "--verify requiere un archivo."; exit 2; }
      VERIFY_FILE="$2"
      shift 2
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      err "Opcion desconocida: $1"
      echo "Uso: deploy system backup-secrets [--out <dir>] | --verify <archivo> | --help"
      exit 2
      ;;
  esac
done

if [[ -n "$VERIFY_FILE" && -n "$OUT_DIR" ]]; then
  err "--out y --verify son excluyentes."
  exit 2
fi

if [[ -n "$VERIFY_FILE" ]]; then
  cmd_verify "$VERIFY_FILE"
else
  cmd_backup "$OUT_DIR"
fi
