#!/usr/bin/env bash
# =============================================================================
# test-restore.sh — pins `database restore` (the recovery half of backups).
#
# Offline: the real dump/restore cycle needs a live MariaDB, so this suite
# pins the operator-facing contract — argument parsing, the config gates, the
# confirmation/--yes boundary, the pre-restore safety step, and the listing
# helpers (newest first; --last skips pre-restore copies).
#
# Run: bash tests/test-restore.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESTORE="$ROOT/modules/database/commands/restore.sh"

PASS=0
FAIL=0
TMP="$(mktemp -d)" || { printf 'FATAL: fallo mktemp -d: no se puede preparar el directorio temporal de pruebas.\n' >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

check() { # <name> <expected> <actual>
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ok    %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        esperado: %s\n        obtenido: %s\n' "$name" "$expected" "$actual"; FAIL=$((FAIL + 1))
  fi
}

check_contains() { # <name> <haystack> <needle>
  local name="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    printf '  ok    %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        falta: %s\n' "$name" "$needle"; FAIL=$((FAIL + 1))
  fi
}

# ── Fixtures: a config + backup files ───────────────────────────────────────
mkdir -p "$TMP/backups"
printf 'Backup__EncryptionPassphrase="testpass"\nBackup__Dir="%s/backups"\nBackup__RetentionDays="14"\nConnectionStrings__MariaDB="Server=localhost;Port=3307;Database=ema;User=u;Password=p;"\n' "$TMP" > "$TMP/config.env"
printf 'Backup__EncryptionPassphrase="CHANGE_ME"\nBackup__Dir="%s/backups"\nConnectionStrings__MariaDB="Server=localhost;Database=ema;User=u;Password=p;"\n' "$TMP" > "$TMP/config-changeme.env"
printf 'Backup__EncryptionPassphrase="testpass"\nBackup__Dir="%s/backups"\n' "$TMP" > "$TMP/config-noconn.env"

: > "$TMP/backups/ema-20261001-030000.sql.gz.enc"
: > "$TMP/backups/ema-20261010-030000.sql.gz.enc"
: > "$TMP/backups/pre-restore-ema-20261005-120000.sql.gz.enc"
touch -t 202610010300 "$TMP/backups/ema-20261001-030000.sql.gz.enc"
touch -t 202610100300 "$TMP/backups/ema-20261010-030000.sql.gz.enc"
touch -t 202610051200 "$TMP/backups/pre-restore-ema-20261005-120000.sql.gz.enc"

run() { CONFIG_FILE="$1" bash "$RESTORE" "${@:2}"; }

echo "database restore (recuperacion de respaldos)"

# ── 1. Command present + help ───────────────────────────────────────────────
[[ -f "$RESTORE" ]] && { printf '  ok    restore.sh existe\n'; PASS=$((PASS + 1)); } || { printf '  FAIL  restore.sh ausente\n'; FAIL=$((FAIL + 1)); }
help_out="$(run "$TMP/config.env" --help 2>&1)"; help_rc=$?
check "help: exit 0" "0" "$help_rc"
check_contains "help: --last"        "$help_out" "--last"
check_contains "help: --file"        "$help_out" "--file"
check_contains "help: --yes"         "$help_out" "--yes"
check_contains "help: pre-restore"   "$help_out" "pre-restore"

# ── 2. Argument parsing errors ──────────────────────────────────────────────
run "$TMP/config.env" --bogus >/dev/null 2>&1; check "opcion desconocida -> exit 2" "2" "$?"
run "$TMP/config.env" --file  >/dev/null 2>&1; check "--file sin valor -> exit 2"   "2" "$?"
run "$TMP/config.env" --help  >/dev/null 2>&1; check "--help -> exit 0"              "0" "$?"

# ── 3. Config gates ─────────────────────────────────────────────────────────
out="$(run "$TMP/config-changeme.env" --last </dev/null 2>&1)"; rc=$?
check "CHANGE_ME -> exit 1" "1" "$rc"
check_contains "CHANGE_ME: mensaje claro" "$out" "clave de cifrado"

out="$(run "$TMP/config-noconn.env" --last </dev/null 2>&1)"; rc=$?
check "sin conexion -> exit 1" "1" "$rc"
check_contains "sin conexion: mensaje claro" "$out" "cadena de conexion"

# ── 4. --yes boundary (no TTY) ──────────────────────────────────────────────
out="$(run "$TMP/config.env" --last </dev/null 2>&1)"; rc=$?
check "--last sin --yes (no TTY) -> exit 1" "1" "$rc"
check_contains "refusal: pide confirmacion" "$out" "requiere confirmacion"
check_contains "refusal: sugiere --yes"     "$out" "--yes"

out="$(run "$TMP/config.env" --file /no/existe.sql.gz.enc --yes </dev/null 2>&1)"; rc=$?
check "--file inexistente -> exit 1" "1" "$rc"
check_contains "--file inexistente: mensaje" "$out" "No existe el archivo"

# ── 5. Listing helpers (newest first; --last skips pre-restore) ─────────────
# shellcheck source=/dev/null
source "$ROOT/modules/database/lib/backup-schedule.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/database/lib/backup-db.sh"
Backup__Dir="$TMP/backups"

all_list="$(db_backup_files_for ema)"
first_all="$(printf '%s\n' "$all_list" | head -1)"
check "listing: mas reciente primero" "$TMP/backups/ema-20261010-030000.sql.gz.enc" "$first_all"
check_contains "listing: incluye pre-restore" "$all_list" "pre-restore-ema-20261005-120000.sql.gz.enc"
n_all="$(printf '%s\n' "$all_list" | grep -c '\.sql\.gz\.enc$')"
check "listing: 3 archivos" "3" "$n_all"

last_regular="$(db_latest_regular_backup_for ema)"
check "--last: ignora pre-restore" "$TMP/backups/ema-20261010-030000.sql.gz.enc" "$last_regular"

# ── 6. Source pins: shared helper + pre-restore safety step ─────────────────
restore_src="$(cat "$RESTORE")"
check_contains "restore usa db_restore_encrypted_backup" "$restore_src" "db_restore_encrypted_backup"
check_contains "restore toma respaldo pre-restore"       "$restore_src" "pre-restore-\${DB_DATABASE}"
backup_src="$(cat "$ROOT/modules/database/commands/backup.sh")"
check_contains "backup reusa db_create_encrypted_backup (sin duplicar)" "$backup_src" "db_create_encrypted_backup"

echo
printf 'ok: %d   fallos: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
