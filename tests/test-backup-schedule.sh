#!/usr/bin/env bash
# =============================================================================
# test-backup-schedule.sh — pins the encrypted-backup schedule behaviour.
#
# The delivery catalog (DOC-23) promised a daily timer; this suite pins the
# user's decision: the schedule is EVERY 3 DAYS, wall-clock, with Persistent.
# It also pins the single-source-of-truth for the units (setup-server.sh must
# render them from modules/database/lib/backup-schedule.sh) and the
# configured/not-configured detection + the backup listing.
#
# Run: bash tests/test-backup-schedule.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$ROOT/modules/database/lib/backup-schedule.sh"

PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

check() { # <name> <expected> <actual>
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ok    %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        esperado: %s\n        obtenido: %s\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
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

check_absent() { # <name> <haystack> <needle>
  local name="$1" hay="$2" needle="$3"
  if [[ "$hay" != *"$needle"* ]]; then
    printf '  ok    %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        no deberia aparecer: %s\n' "$name" "$needle"; FAIL=$((FAIL + 1))
  fi
}

expect_state() { # <name> <expected true|false> <actual rc>
  local name="$1" expected="$2" rc="$3"
  local got="false"; [[ "$rc" -eq 0 ]] && got="true"
  check "$name" "$expected" "$got"
}

echo "Programacion de respaldos cifrados"

# ── 1. Timer template: every 3 days, wall-clock, persistent ─────────────────
timer="$(render_backup_timer_unit)"
check_contains "timer: OnCalendar cada 3 dias"        "$timer" "OnCalendar=*-*-01/3 03:00:00"
check_contains "timer: Persistent=true"               "$timer" "Persistent=true"
check_contains "timer: descripcion 'cada 3 dias'"     "$timer" "cada 3 dias"
check_absent   "timer: YA NO es diario"               "$timer" "OnCalendar=*-*-* 03:00:00"

# ── 2. Service template: oneshot, config.env, --non-interactive ─────────────
svc="$(render_backup_service_unit)"
check_contains "service: EnvironmentFile config.env"  "$svc" "EnvironmentFile=/app/config/config.env"
check_contains "service: Type=oneshot"                "$svc" "Type=oneshot"
check_contains "service: corre --non-interactive"     "$svc" "backup.sh --non-interactive"

# ── 3. Single source of truth: setup-server.sh sources the lib ──────────────
setup="$ROOT/setup/setup-server.sh"
setup_src="$(cat "$setup")"
check_contains "setup: sourcea backup-schedule.sh"    "$setup_src" "modules/database/lib/backup-schedule.sh"
check_absent   "setup: ya no define su propio timer"  "$setup_src" "OnCalendar=*-*-* 03:00:00"

# ── 4. Detection: passphrase + dir + units = configured ─────────────────────
BACKUP_SERVICE_UNIT="$TMP/backup.service"
BACKUP_TIMER_UNIT="$TMP/backup.timer"
Backup__Dir="$TMP/backups"
Backup__EncryptionPassphrase=""

backup_is_configured; expect_state "detect: vacio -> NO configurado" "false" "$?"

Backup__EncryptionPassphrase="ChangeMe"; backup_is_configured; expect_state "detect: CHANGE_ME-like -> NO configurado" "false" "$?"

Backup__EncryptionPassphrase="CHANGE_ME"; backup_is_configured; expect_state "detect: CHANGE_ME -> NO configurado" "false" "$?"

Backup__EncryptionPassphrase="una-passphrase-real"
backup_is_configured; expect_state "detect: passphrase pero sin dir/units -> NO configurado" "false" "$?"

mkdir -p "$Backup__Dir"
backup_is_configured; expect_state "detect: passphrase+dir pero sin units -> NO configurado" "false" "$?"

touch "$BACKUP_SERVICE_UNIT"
backup_is_configured; expect_state "detect: solo service -> NO configurado" "false" "$?"

touch "$BACKUP_TIMER_UNIT"
backup_is_configured; expect_state "detect: passphrase+dir+ambos units -> configurado" "true" "$?"

# ── 5. Listing: newest first, with size ─────────────────────────────────────
printf 'viejo' > "$Backup__Dir/ema-20260101-030000.sql.gz.enc"
printf 'mucho mas nuevo' > "$Backup__Dir/ema-20260110-030000.sql.gz.enc"
touch -t 202601010300 "$Backup__Dir/ema-20260101-030000.sql.gz.enc"
touch -t 202601100300 "$Backup__Dir/ema-20260110-030000.sql.gz.enc"
# un archivo que NO es un backup: no debe listarse.
printf 'x' > "$Backup__Dir/notas.txt"

listing="$(backup_list)"
check_contains "list: incluye el respaldo nuevo"      "$listing" "2026-01-10"
check_contains "list: incluye el respaldo viejo"      "$listing" "2026-01-01"
check_absent   "list: ignora archivos que no son de backup" "$listing" "notas.txt"
first_date="$(printf '%s\n' "$listing" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
check "list: mas reciente primero" "2026-01-10" "$first_date"
backup_lines="$(printf '%s\n' "$listing" | grep -c '^  - ')"
check "list: una linea por respaldo" "2" "$backup_lines"

# ── 6. Menu surface mentions the duality ────────────────────────────────────
menu_out="$(printf '6\n' | bash "$ROOT/modules/database/menu.sh" 2>&1)"
check_contains "menu: opcion de respaldos"            "$menu_out" "Respaldos (configurar / ver los existentes)"

echo
printf 'ok: %d   fallos: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
