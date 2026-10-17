#!/usr/bin/env bash
set -uo pipefail
# =============================================================================
# modules/database/commands/backup.sh — Respaldos cifrados de MariaDB
#
# Corre en la VM de la app y hace mariadb-dump CONTRA LA BD REMOTA usando
# ConnectionStrings__MariaDB de config.env — el dump queda en ESTA VM (la de la
# app), NO en la de la BD: eso ya es un "segundo medio" real (2 VMs distintas).
#
# Cifrado: AES-256 con Backup__EncryptionPassphrase, una passphrase separada
# de la clave RSA de la app (secrets/rsa-private-key.pem) — asi comprometer
# solo el archivo de backup, o solo esta VM, no alcanza para leerlo.
#
# Comportamiento (operador):
#   - SI el respaldo NO esta configurado -> ofrece configurarlo ahora: asegura
#     la passphrase (genera si falta), crea la carpeta y INSTALA el timer
#     systemd (cada 3 dias, 03:00). Confirma antes de tocar nada.
#   - SI ya esta configurado -> LISTA los respaldos existentes (fecha + tamano,
#     mas reciente primero) y muestra el estado de la programacion.
#
# Uso:
#   bash backup.sh --non-interactive   # lo llama backup.service (systemd timer)
#   bash backup.sh                     # manual, desde el menu (estado/config)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/db-common.sh"
source "$MODULE_DIR/lib/backup-schedule.sh"
source "$MODULE_DIR/lib/backup-db.sh"

NON_INTERACTIVE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive) NON_INTERACTIVE=1 ;;
    *) err "Opcion desconocida: $1"; exit 2 ;;
  esac
  shift
done

run_backup() {
  load_config "ConnectionStrings__MariaDB Backup__EncryptionPassphrase" || return 1

  if [[ "${Backup__EncryptionPassphrase}" == "CHANGE_ME" ]]; then
    err "Backup__EncryptionPassphrase sigue en CHANGE_ME. Corre 'deploy system setup' para autogenerarla."
    return 1
  fi

  local backup_dir
  backup_dir="$(backup_dir_path)"
  local retention_days
  retention_days="$(backup_retention_days)"

  mkdir -p "$backup_dir"
  chmod 700 "$backup_dir"

  if ! db_parse_mariadb_connection "$ConnectionStrings__MariaDB"; then
    err "No se pudo parsear ConnectionStrings__MariaDB (server/database/user vacios)."
    return 1
  fi

  local dump_client
  dump_client="$(db_dump_client)"
  if [[ -z "$dump_client" ]]; then
    err "mariadb-dump/mysqldump no disponible. Instalar mariadb-client."
    return 1
  fi

  local stamp enc_file
  stamp="$(date '+%Y%m%d-%H%M%S')"
  enc_file="$backup_dir/${DB_DATABASE}-${stamp}.sql.gz.enc"

  log "Iniciando backup de '$DB_DATABASE' desde $DB_SERVER:$DB_PORT (via $dump_client)..."

  db_create_encrypted_backup "$enc_file" || return 1
  ok "Backup cifrado: $enc_file ($(du -h "$enc_file" | cut -f1))"

  local deleted=0
  while IFS= read -r -d '' old; do
    rm -f "$old"
    (( deleted += 1 ))
  done < <(find "$backup_dir" -maxdepth 1 -name "${DB_DATABASE}-*.sql.gz.enc" -mtime "+${retention_days}" -print0 2>/dev/null)

  if [[ "$deleted" -gt 0 ]]; then
    log "Retencion ($retention_days dias): $deleted backup(s) viejo(s) eliminados."
  fi

  return 0
}

# ── Operador: estado (configurado) ───────────────────────────────────────────

backup_show_status() {
  echo ""
  divider
  echo "  RESPALDOS"
  divider
  echo ""
  echo "  Ubicacion    : $(backup_dir_path)"
  echo "  Cifrado      : AES-256 · Retencion: $(backup_retention_days) dias"
  echo ""
  backup_schedule_state
  echo ""
  echo "  Respaldos existentes (mas reciente primero):"
  backup_list
  echo ""
  echo "  Para forzar un respaldo ahora: systemctl start backup.service"
  divider
  return 0
}

# ── Operador: configurar (no configurado) ────────────────────────────────────

backup_configure() {
  local dir
  dir="$(backup_dir_path)"

  echo ""
  divider
  echo "  RESPALDOS — CONFIGURACION"
  divider
  echo ""
  log "Estado detectado:"
  if backup_passphrase_set; then
    echo "  - Clave de cifrado : configurada"
  else
    echo "  - Clave de cifrado : FALTA (se generara)"
  fi
  if [[ -d "$dir" ]]; then
    echo "  - Carpeta          : $dir (existe)"
  else
    echo "  - Carpeta          : $dir (se creara)"
  fi
  if backup_schedule_installed; then
    echo "  - Programacion     : timer instalado"
  else
    echo "  - Programacion     : FALTA (se instalara)"
  fi
  echo ""
  log "Se va a configurar:"
  echo "  - Clave de cifrado (AES-256) para proteger los respaldos."
  echo "  - Carpeta de respaldos: $dir"
  echo "  - Respaldo automatico cada 3 dias a las 03:00 (servicio del sistema)."
  echo ""

  confirm "Configurar los respaldos ahora?" || { log "Cancelado. No se hizo ningun cambio."; return 0; }

  if [[ ! -f "$(backup_config_file)" ]]; then
    err "No existe $(backup_config_file). Corre 'deploy system setup' primero."
    return 1
  fi

  if ! backup_passphrase_set; then
    if ! command -v openssl &>/dev/null; then
      err "openssl no disponible para generar la clave. Corre 'deploy system setup'."
      return 1
    fi
    local new_key
    new_key="$(openssl rand -base64 32 | tr -d '\n')"
    update_config_value "Backup__EncryptionPassphrase" "$new_key"
    Backup__EncryptionPassphrase="$new_key"
    ok "Clave de cifrado generada y guardada en config.env."
    warn "RESPALDALA fuera del servidor: si se pierde, los respaldos quedan ilegibles."
    log "(Esto mismo lo hace 'deploy system setup'; lo hicimos ahora.)"
  else
    ok "Clave de cifrado ya configurada (se reutiliza la existente)."
  fi

  mkdir -p "$dir"
  chmod 700 "$dir"
  # El timer corre como el usuario del servicio (no root): la carpeta debe
  # pertenecerle para poder escribir el dump.
  local svc_user svc_group
  svc_user="$(backup_service_user)"; svc_group="$(backup_service_group)"
  if id "$svc_user" &>/dev/null; then
    chown "$svc_user:$svc_group" "$dir" 2>/dev/null || true
  fi
  ok "Carpeta de respaldos lista: $dir"

  backup_schedule_install || return 1

  echo ""
  ok "Respaldos configurados."
  log "  Respaldo automatico : cada 3 dias a las 03:00 (± 10 min)."
  log "  Ubicacion           : $dir (cifrado AES-256, retencion $(backup_retention_days) dias)."
  log "  Ver los respaldos   : deploy database backup"
  log "  Forzar uno ahora    : systemctl start backup.service"
  divider
  return 0
}

# ── Main ─────────────────────────────────────────────────────────────────────

if [[ "$NON_INTERACTIVE" == "1" ]]; then
  if run_backup; then
    ok "Backup completado."
    exit 0
  else
    err "Backup fallido — revisar 'journalctl -u backup.service' o la salida de arriba."
    exit 1
  fi
fi

# Manual (menu): estado/config. config.env puede no existir todavia.
load_config 2>/dev/null || true

if backup_is_configured; then
  backup_show_status
  exit 0
fi

backup_configure
exit $?
