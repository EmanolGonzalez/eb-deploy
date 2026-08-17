#!/usr/bin/env bash
set -uo pipefail
# =============================================================================
# modules/database/commands/backup.sh — Backup cifrado de MariaDB
#
# Corre en la VM de la app (donde vive este toolkit), y hace mariadb-dump
# CONTRA LA BD REMOTA usando ConnectionStrings__MariaDB de config.env — igual
# que check.sh, pero sin prompts (para poder correr via systemd timer).
#
# El dump queda en ESTA VM (la de la app), NO en la de la BD: eso ya es un
# "segundo medio" real (2 VMs distintas), no una copia en el mismo disco.
#
# Cifrado: AES-256 con Backup__EncryptionPassphrase, una passphrase separada
# de la clave RSA de la app (secrets/rsa-private-key.pem) — asi comprometer
# solo el archivo de backup, o solo esta VM, no alcanza para leerlo.
#
# Uso:
#   bash backup.sh --non-interactive   # via systemd timer / cron
#   bash backup.sh                     # manual, desde el menu
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/db-common.sh"

run_backup() {
  load_config "ConnectionStrings__MariaDB Backup__EncryptionPassphrase" || return 1

  if [[ "${Backup__EncryptionPassphrase}" == "CHANGE_ME" ]]; then
    err "Backup__EncryptionPassphrase sigue en CHANGE_ME. Corre 'deploy system setup' para autogenerarla."
    return 1
  fi

  local backup_dir="${Backup__Dir:-/app/backups}"
  local retention_days="${Backup__RetentionDays:-14}"

  mkdir -p "$backup_dir"
  chmod 700 "$backup_dir"

  local cs="$ConnectionStrings__MariaDB"
  local server database user pass port
  server="$(echo "$cs"   | sed -nE 's/.*[Ss]erver=([^;]+).*/\1/p')"
  database="$(echo "$cs" | sed -nE 's/.*[Dd]atabase=([^;]+).*/\1/p')"
  user="$(echo "$cs"     | sed -nE 's/.*[Uu]ser=([^;]+).*/\1/p')"
  pass="$(echo "$cs"     | sed -nE 's/.*[Pp]assword=([^;]+).*/\1/p')"
  port="$(echo "$cs"     | sed -nE 's/.*[Pp]ort=([^;]+).*/\1/p')"
  port="${port:-3306}"

  if [[ -z "$server" || -z "$database" || -z "$user" ]]; then
    err "No se pudo parsear ConnectionStrings__MariaDB (server/database/user vacios)."
    return 1
  fi

  local client=""
  command -v mariadb-dump &>/dev/null && client="mariadb-dump"
  [[ -z "$client" ]] && command -v mysqldump &>/dev/null && client="mysqldump"
  if [[ -z "$client" ]]; then
    err "mariadb-dump/mysqldump no disponible. Instalar mariadb-client."
    return 1
  fi

  local stamp
  stamp="$(date '+%Y%m%d-%H%M%S')"
  local raw_file="$backup_dir/${database}-${stamp}.sql.gz"
  local enc_file="${raw_file}.enc"

  log "Iniciando backup de '$database' desde $server:$port (via $client)..."

  if ! "$client" -h "$server" -P "$port" -u"$user" -p"$pass" --ssl-verify-server-cert=0 \
        --single-transaction --quick --routines --triggers --events \
        "$database" | gzip > "$raw_file"; then
    err "mariadb-dump fallo. Descartando archivo parcial."
    rm -f "$raw_file"
    return 1
  fi

  if [[ ! -s "$raw_file" ]]; then
    err "El dump quedo vacio. Abortando."
    rm -f "$raw_file"
    return 1
  fi

  if ! openssl enc -aes-256-cbc -pbkdf2 -salt \
        -pass "pass:${Backup__EncryptionPassphrase}" \
        -in "$raw_file" -out "$enc_file"; then
    err "Cifrado del backup fallo."
    rm -f "$raw_file" "$enc_file"
    return 1
  fi

  rm -f "$raw_file"
  chmod 600 "$enc_file"
  ok "Backup cifrado: $enc_file ($(du -h "$enc_file" | cut -f1))"

  local deleted=0
  while IFS= read -r -d '' old; do
    rm -f "$old"
    (( deleted += 1 ))
  done < <(find "$backup_dir" -maxdepth 1 -name "${database}-*.sql.gz.enc" -mtime "+${retention_days}" -print0 2>/dev/null)

  if [[ "$deleted" -gt 0 ]]; then
    log "Retencion ($retention_days dias): $deleted backup(s) viejo(s) eliminados."
  fi

  return 0
}

if run_backup; then
  ok "Backup completado."
  exit 0
else
  err "Backup fallido — revisar 'journalctl -u backup.service' o la salida de arriba."
  exit 1
fi
