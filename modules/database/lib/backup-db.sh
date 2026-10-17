#!/usr/bin/env bash
# =============================================================================
# modules/database/lib/backup-db.sh
#
# MariaDB dump/restore mechanics shared by backup.sh and restore.sh:
#   - parse ConnectionStrings__MariaDB
#   - resolve the client binary (dump vs interactive)
#   - dump + encrypt (AES-256) / decrypt + gunzip + load
#   - list the backups that belong to a database
#
# ONE copy of the connection/crypto logic so backup and restore can never
# disagree about how a backup is written or read. No logs on the happy path:
# callers own the user-facing messages.
#
# Callers are expected to have sourced db-common.sh (load_config, logger) and
# backup-schedule.sh (backup_dir_path) already.
# =============================================================================

BACKUP_DB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DB_BASE="$(cd "$BACKUP_DB_LIB_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
if [[ -f "$BACKUP_DB_BASE/core/logger.sh" ]]; then
  source "$BACKUP_DB_BASE/core/logger.sh"
fi

# ── Connection ───────────────────────────────────────────────────────────────
# db_parse_mariadb_connection <connection-string>
#   Sets DB_SERVER DB_PORT DB_DATABASE DB_USER DB_PASS. Port defaults to 3306
#   (the historical backup.sh default). Returns 0 when server/db/user are set.
db_parse_mariadb_connection() {
  local cs="$1"
  DB_SERVER="$(echo "$cs"   | sed -nE 's/.*[Ss]erver=([^;]+).*/\1/p')"
  DB_DATABASE="$(echo "$cs" | sed -nE 's/.*[Dd]atabase=([^;]+).*/\1/p')"
  DB_USER="$(echo "$cs"     | sed -nE 's/.*[Uu]ser=([^;]+).*/\1/p')"
  DB_PASS="$(echo "$cs"     | sed -nE 's/.*[Pp]assword=([^;]+).*/\1/p')"
  DB_PORT="$(echo "$cs"     | sed -nE 's/.*[Pp]ort=([^;]+).*/\1/p')"
  DB_PORT="${DB_PORT:-3306}"
  [[ -n "$DB_SERVER" && -n "$DB_DATABASE" && -n "$DB_USER" ]]
}

# db_dump_client -> echoes mariadb-dump | mysqldump | (empty)
db_dump_client() {
  if command -v mariadb-dump &>/dev/null; then echo mariadb-dump
  elif command -v mysqldump &>/dev/null; then echo mysqldump
  fi
}

# db_restore_client -> echoes mariadb | mysql | (empty)
db_restore_client() {
  if command -v mariadb &>/dev/null; then echo mariadb
  elif command -v mysql &>/dev/null; then echo mysql
  fi
}

# db_docker_container -> echoes the maria/mysql docker container name, or empty
db_docker_container() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'maria|mysql' | head -1 || true
}

# ── Backup ───────────────────────────────────────────────────────────────────
# db_create_encrypted_backup <enc_dest>
#   Dumps DB_DATABASE and encrypts it to <enc_dest> with
#   Backup__EncryptionPassphrase. Expects DB_* parsed + passphrase confirmed.
#   Returns 0 on success, 1 on failure (partial files removed).
db_create_encrypted_backup() {
  local enc_file="$1"
  local dump_client
  dump_client="$(db_dump_client)"
  if [[ -z "$dump_client" ]]; then
    err "mariadb-dump/mysqldump no disponible. Instalar mariadb-client."
    return 1
  fi

  local raw
  raw="$(mktemp)"
  if ! "$dump_client" -h "$DB_SERVER" -P "$DB_PORT" -u"$DB_USER" -p"$DB_PASS" \
        --ssl-verify-server-cert=0 --single-transaction --quick --routines --triggers --events \
        "$DB_DATABASE" | gzip > "$raw"; then
    err "mariadb-dump fallo. Descartando archivo parcial."
    rm -f "$raw"
    return 1
  fi
  if [[ ! -s "$raw" ]]; then
    err "El dump quedo vacio. Abortando."
    rm -f "$raw"
    return 1
  fi
  if ! openssl enc -aes-256-cbc -pbkdf2 -salt \
        -pass "pass:${Backup__EncryptionPassphrase}" \
        -in "$raw" -out "$enc_file"; then
    err "Cifrado del backup fallo."
    rm -f "$raw" "$enc_file"
    return 1
  fi
  rm -f "$raw"
  chmod 600 "$enc_file"
  return 0
}

# ── Restore ──────────────────────────────────────────────────────────────────
# db_restore_encrypted_backup <enc_file>
#   Decrypts + gunzips + loads into DB_DATABASE.
#   Returns: 0 ok | 2 decrypt/gzip failed (DB untouched) | 3 load failed
#            | 4 precondition (missing file/client)
db_restore_encrypted_backup() {
  local enc_file="$1"
  [[ -f "$enc_file" ]] || { err "No existe el archivo: $enc_file"; return 4; }
  local client
  client="$(db_restore_client)"
  [[ -n "$client" ]] || { err "mariadb/mysql no disponible. Instalar mariadb-client."; return 4; }

  local tmpdir gz sql rc=0 container
  tmpdir="$(mktemp -d)"
  gz="$tmpdir/restore.sql.gz"
  sql="$tmpdir/restore.sql"

  if ! openssl enc -d -aes-256-cbc -pbkdf2 \
        -pass "pass:${Backup__EncryptionPassphrase}" \
        -in "$enc_file" -out "$gz" 2>/dev/null; then
    rm -rf "$tmpdir"
    return 2
  fi
  if ! gunzip -c "$gz" > "$sql" 2>/dev/null; then
    rm -rf "$tmpdir"
    return 2
  fi
  rm -f "$gz"

  container="$(db_docker_container)"
  if [[ -n "$container" ]]; then
    docker exec -i "$container" "$client" -u"$DB_USER" -p"$DB_PASS" "$DB_DATABASE" < "$sql" || rc=$?
  else
    "$client" --ssl-verify-server-cert=0 -h "$DB_SERVER" -P "$DB_PORT" \
      -u"$DB_USER" -p"$DB_PASS" "$DB_DATABASE" < "$sql" || rc=$?
  fi
  rm -rf "$tmpdir"
  [[ "$rc" -eq 0 ]] || return 3
  return 0
}

# ── Listing ──────────────────────────────────────────────────────────────────
# db_backup_files_for <database> -> full paths, newest first. Matches the
# database's normal dumps and its pre-restore safety copies.
db_backup_files_for() {
  local database="$1" dir
  dir="$(backup_dir_path)"
  [[ -d "$dir" ]] || return 0
  local -a files=()
  mapfile -t files < <(find "$dir" -maxdepth 1 -type f \
    \( -name "${database}-*.sql.gz.enc" -o -name "pre-restore-${database}-*.sql.gz.enc" \) \
    -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}')
  [[ ${#files[@]} -gt 0 ]] && printf '%s\n' "${files[@]}"
  return 0
}

# db_latest_regular_backup_for <database> -> the newest REGULAR dump (newest
# first, one line). Excludes the pre-restore-* safety copies, so `--last` never
# silently picks the backup the last restore just created.
db_latest_regular_backup_for() {
  local database="$1" dir
  dir="$(backup_dir_path)"
  [[ -d "$dir" ]] || return 0
  find "$dir" -maxdepth 1 -type f -name "${database}-*.sql.gz.enc" \
    -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}' | head -1
  return 0
}
