#!/usr/bin/env bash
set -uo pipefail
# =============================================================================
# modules/database/commands/restore.sh — Restaurar un respaldo cifrado
#
# Restaura un dump cifrado (AES-256, Backup__EncryptionPassphrase) sobre la base
# actual. Mecanica compartida con backup.sh via lib/backup-db.sh (una sola copia
# de la logica de conexion/descifrado).
#
# Seguridad: SIEMPRE toma un respaldo "pre-restore" del estado ACTUAL antes de
# tocar la base, y exige confirmacion explicita (o --yes para automatizacion).
#
# Uso:
#   deploy database restore                 # lista y deja elegir
#   deploy database restore --last           # el mas reciente
#   deploy database restore --file <ruta>    # un archivo especifico
#   deploy database restore --yes ...        # sin confirmacion interactiva
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/db-common.sh"
source "$MODULE_DIR/lib/backup-schedule.sh"
source "$MODULE_DIR/lib/backup-db.sh"

ASSUME_YES=0
USE_LAST=0
BACKUP_FILE=""

usage() {
  cat <<'EOF'
Uso: deploy database restore [opciones]

Restaura un respaldo cifrado sobre la base de datos actual.

  (sin opciones)      Muestra los respaldos disponibles y deja elegir uno.
  --last              Restaura el respaldo mas reciente (excluye pre-restore).
  --file <ruta>       Restaura un archivo especifico.
  --yes, -y           Confirma la accion destructiva (obligatorio sin terminal).
  --help, -h          Muestra esta ayuda.

Antes de restaurar se guarda un respaldo de seguridad del estado ACTUAL
(pre-restore-...) en el mismo directorio de respaldos; nunca queda sin red.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --last)    USE_LAST=1 ;;
    --file)    BACKUP_FILE="${2:-}"; [[ -n "$BACKUP_FILE" ]] || { err "Falta el valor de --file"; exit 2; }; shift ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --help|-h) usage; exit 0 ;;
    *)         err "Opcion desconocida: $1"; usage >&2; exit 2 ;;
  esac
  shift
done

# ── Configuracion ────────────────────────────────────────────────────────────
load_config 2>/dev/null || true

if ! backup_passphrase_set; then
  err "No hay clave de cifrado configurada (Backup__EncryptionPassphrase)."
  err "Configura los respaldos primero: deploy database backup"
  exit 1
fi

if ! db_parse_mariadb_connection "${ConnectionStrings__MariaDB:-}"; then
  err "No hay cadena de conexion valida (ConnectionStrings__MariaDB)."
  err "Corre 'deploy system setup' para configurarla."
  exit 1
fi

echo ""
divider
echo "  RESTAURAR UN RESPALDO"
divider
echo ""
echo "  Base de datos : $DB_DATABASE"
echo "  Servidor      : $DB_SERVER:$DB_PORT"
echo "  Respaldos en  : $(backup_dir_path)"
echo ""

# ── Elegir el respaldo ───────────────────────────────────────────────────────
CHOSEN=""
if [[ -n "$BACKUP_FILE" ]]; then
  if [[ ! -f "$BACKUP_FILE" ]]; then
    err "No existe el archivo indicado: $BACKUP_FILE"
    exit 1
  fi
  CHOSEN="$BACKUP_FILE"
elif [[ "$USE_LAST" == 1 ]]; then
  CHOSEN="$(db_latest_regular_backup_for "$DB_DATABASE")"
  if [[ -z "$CHOSEN" ]]; then
    err "No hay respaldos de '$DB_DATABASE' en $(backup_dir_path)."
    exit 1
  fi
  log "Respaldo mas reciente: $(basename "$CHOSEN")"
else
  mapfile -t FILES < <(db_backup_files_for "$DB_DATABASE")
  if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "  No hay respaldos disponibles de '$DB_DATABASE'."
    echo "  Configura/crea respaldos con: deploy database backup"
    exit 0
  fi
  echo "  Respaldos disponibles (mas reciente primero):"
  i=0
  for f in "${FILES[@]}"; do
    i=$((i + 1))
    when="$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')"
    size="$(du -h "$f" 2>/dev/null | cut -f1)"
    printf '    %d) %s   %s   (%s)\n' "$i" "$when" "$size" "$(basename "$f")"
  done
  echo ""
  if [[ ! -t 0 ]]; then
    echo "  Elegi uno con: deploy database restore --file <ruta>  (o --last)"
    exit 0
  fi
  read -rp "  Numero a restaurar (Enter para cancelar): " n
  if [[ ! "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#FILES[@]} )); then
    log "No se eligio ningun respaldo. No se hizo ningun cambio."
    exit 0
  fi
  CHOSEN="${FILES[$((n - 1))]}"
fi

# ── Confirmacion explicita ───────────────────────────────────────────────────
if [[ "$ASSUME_YES" != 1 ]]; then
  if [[ ! -t 0 ]]; then
    err "Restauracion destructiva: requiere confirmacion explicita."
    err "En modo no-interactivo pasa --yes (junto con --last o --file)."
    exit 1
  fi
  warn "=============================================================="
  warn "  ATENCION: RESTAURACION DESTRUCTIVA"
  warn "  Se va a REEMPLAZAR el contenido actual de la base '$DB_DATABASE'"
  warn "  con el respaldo: $(basename "$CHOSEN")"
  warn "  Los datos actuales que no esten en ese respaldo se PIERDEN."
  warn "  (Igual se guarda un respaldo pre-restore del estado actual.)"
  warn "=============================================================="
  echo ""
  read -rp "  Escribi RESTAURAR para confirmar: " confirm_word
  if [[ "$confirm_word" != "RESTAURAR" ]]; then
    log "Cancelado. No se hizo ningun cambio."
    exit 0
  fi
fi

# ── Respaldo de seguridad del estado actual (OBLIGATORIO) ────────────────────
backup_dir="$(backup_dir_path)"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
stamp="$(date '+%Y%m%d-%H%M%S')"
pre_file="$backup_dir/pre-restore-${DB_DATABASE}-${stamp}.sql.gz.enc"

log "Tomando respaldo de seguridad del estado ACTUAL (pre-restore)..."
if ! db_create_encrypted_backup "$pre_file"; then
  err "No se pudo tomar el respaldo pre-restore. ABORTANDO la restauracion por seguridad."
  exit 1
fi
ok "Respaldo pre-restore guardado: $pre_file"

# ── Restaurar ────────────────────────────────────────────────────────────────
echo ""
log "Restaurando '$(basename "$CHOSEN")' sobre '$DB_DATABASE' en $DB_SERVER:$DB_PORT..."
db_restore_encrypted_backup "$CHOSEN"
rc=$?
echo ""
if [[ "$rc" -eq 0 ]]; then
  divider
  ok "Restauracion completada: $DB_DATABASE"
  log "  Verifica que la aplicacion este sana : deploy health simple"
  log "  Respaldo de seguridad previo         : $pre_file"
  divider
  exit 0
elif [[ "$rc" -eq 2 ]]; then
  err "No se pudo descifrar/descomprimir el respaldo (passphrase incorrecta o archivo corrupto)."
  err "La base de datos NO se modifico."
  exit 1
else
  err "La carga del respaldo FALLO a mitad: la base puede quedar incompleta."
  err "Respaldo de seguridad del estado previo: $pre_file"
  err "Para volver al estado anterior: deploy database restore --file $pre_file --yes"
  exit 1
fi
