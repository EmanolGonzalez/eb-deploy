#!/usr/bin/env bash
# =============================================================================
# modules/database/lib/backup-schedule.sh
#
# Canonical source of truth for the encrypted-backup schedule:
#   backup.service  — oneshot: runs backup.sh --non-interactive
#   backup.timer    — every 3 days at 03:00 (wall-clock, Persistent=true)
#
# Used by BOTH `setup/setup-server.sh` (day-0 install) and
# `modules/database/commands/backup.sh` (operator (re)configure), so the units
# can never drift between the two paths.
#
# ── Schedule choice: OnCalendar, every 3 days, 03:00 ─────────────────────────
#   OnCalendar=*-*-01/3 03:00:00  -> days 1, 4, 7, 10, ... of each month.
#   Justification (vs OnUnitActiveSec=3d):
#     * OnCalendar is WALL-CLOCK anchored: a fixed, predictable time of day,
#       independent of when the previous run/manual test happened.
#     * Persistent=true replays a missed run if the server was off at 03:00.
#     * OnUnitActiveSec=3d is relative to the LAST activation, so it drifts
#       every time someone triggers the unit and it does NOT replay missed runs.
#   RandomizedDelaySec=600 spreads load across 10 min without moving the day.
# =============================================================================

BACKUP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_BASE_DIR="$(cd "$BACKUP_LIB_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
if [[ -f "$BACKUP_BASE_DIR/core/logger.sh" ]]; then
  source "$BACKUP_BASE_DIR/core/logger.sh"
fi

# Unit paths (overridable in tests).
BACKUP_SERVICE_UNIT="${BACKUP_SERVICE_UNIT:-/etc/systemd/system/backup.service}"
BACKUP_TIMER_UNIT="${BACKUP_TIMER_UNIT:-/etc/systemd/system/backup.timer}"

# ── Identity / paths resolved at call time ───────────────────────────────────
# setup-server.sh sets SERVICE_USER/SERVICE_GROUP/DEPLOY_DIR/CONFIG_FILE; when
# sourced from `deploy database backup` those are unset and we fall back to the
# same defaults setup-server.sh uses.
backup_service_user()  { printf '%s' "${SERVICE_USER:-app-backend}"; }
backup_service_group() { printf '%s' "${SERVICE_GROUP:-app-backend}"; }
backup_deploy_dir()    { printf '%s' "${DEPLOY_DIR:-/app/deploy}"; }
backup_config_file()   { printf '%s' "${CONFIG_FILE:-/app/config/config.env}"; }
backup_dir_path()      { printf '%s' "${Backup__Dir:-/app/backups}"; }
backup_retention_days(){ printf '%s' "${Backup__RetentionDays:-14}"; }

# ── Unit renderers ───────────────────────────────────────────────────────────

render_backup_service_unit() {
  local user group deploy_dir config_file
  user="$(backup_service_user)"
  group="$(backup_service_group)"
  deploy_dir="$(backup_deploy_dir)"
  config_file="$(backup_config_file)"
  cat <<SYSTEMDEOF
[Unit]
Description=Backup cifrado de MariaDB (dump remoto + retencion)
After=network.target

[Service]
Type=oneshot
User=${user}
Group=${group}
EnvironmentFile=${config_file}
ExecStart=/bin/bash ${deploy_dir}/modules/database/commands/backup.sh --non-interactive
StandardOutput=journal
StandardError=journal
SYSTEMDEOF
}

render_backup_timer_unit() {
  cat <<'SYSTEMDEOF'
[Unit]
Description=Disparador de backup.service (cada 3 dias, 03:00)

# Cada 3 dias a las 03:00 (dias 1, 4, 7, 10, ... de cada mes).
# OnCalendar (wall-clock, hora fija y predecible) en vez de OnUnitActiveSec=3d
# (relativo a la ultima activacion: se corre con cada reinicio/ejecucion manual
# y no replays corridas perdidas). Persistent=true corre el backup al arrancar
# si el server estaba apagado a la hora programada.
[Timer]
OnCalendar=*-*-01/3 03:00:00
RandomizedDelaySec=600
Persistent=true

[Install]
WantedBy=timers.target
SYSTEMDEOF
}

# ── Configuration state ──────────────────────────────────────────────────────

# Passphrase is set and is not the CHANGE_ME placeholder.
backup_passphrase_set() {
  local v="${Backup__EncryptionPassphrase:-}"
  [[ -n "$v" && "$v" != "CHANGE_ME" ]]
}

backup_schedule_installed() {
  [[ -f "$BACKUP_SERVICE_UNIT" && -f "$BACKUP_TIMER_UNIT" ]]
}

# "Configured" is concrete: passphrase set + backup dir exists + both units
# installed. Anything missing takes the operator to the configure flow.
backup_is_configured() {
  backup_passphrase_set \
    && [[ -d "$(backup_dir_path)" ]] \
    && backup_schedule_installed
}

# ── Idempotent unit write ────────────────────────────────────────────────────

# _backup_apply_unit <target> <expected> <label>
#   Writes only on drift; backs up the previous file. Returns 1 on change.
_backup_apply_unit() {
  local target="$1" expected="$2" label="${3:-$target}"
  if [[ ! -f "$target" ]]; then
    printf '%s\n' "$expected" > "$target"
    ok "$label creado."
    return 1
  fi
  if diff -q <(printf '%s\n' "$expected") "$target" >/dev/null 2>&1; then
    ok "$label sincronizado (sin cambios)."
    return 0
  fi
  local backup="${target}.bak.$(date '+%Y%m%d-%H%M%S')"
  cp -p "$target" "$backup"
  warn "$label difiere — backup en $backup"
  printf '%s\n' "$expected" > "$target"
  ok "$label actualizado."
  return 1
}

# Install/refresh the units and enable the timer. Idempotent. Needs root.
backup_schedule_install() {
  _backup_apply_unit "$BACKUP_SERVICE_UNIT" "$(render_backup_service_unit)" "backup.service" || true
  _backup_apply_unit "$BACKUP_TIMER_UNIT" "$(render_backup_timer_unit)" "backup.timer" || true
  systemctl daemon-reload 2>/dev/null || true
  if systemctl enable --now backup.timer >/dev/null 2>&1; then
    ok "Programacion activa: backup.timer (cada 3 dias, 03:00 ± 10 min)."
    return 0
  fi
  err "No se pudo activar backup.timer. Revisa: systemctl status backup.timer"
  return 1
}

# ── Status reporting ─────────────────────────────────────────────────────────

_backup_fmt_when() { # <systemctl-value> <fallback>
  local v="$1" fallback="$2"
  if [[ -z "$v" || "$v" == "n/a" ]]; then
    printf '%s' "$fallback"
    return 0
  fi
  date -d "$v" '+%Y-%m-%d %H:%M' 2>/dev/null || printf '%s' "$v"
}

# Plain-language schedule state (next / last run). Never fails the caller.
backup_schedule_state() {
  if ! backup_schedule_installed; then
    echo "  Programacion : NO instalada"
    return 0
  fi
  local active next last
  active="$(systemctl is-active backup.timer 2>/dev/null || true)"
  [[ -z "$active" ]] && active="desconocido"
  next="$(systemctl show backup.timer -p NextElapseUSecRealtime --value 2>/dev/null || true)"
  last="$(systemctl show backup.timer -p LastTriggerUSec --value 2>/dev/null || true)"
  echo "  Programacion : cada 3 dias a las 03:00 (timer: $active)"
  echo "  Proxima      : $(_backup_fmt_when "$next" "desconocida")"
  echo "  Ultima       : $(_backup_fmt_when "$last" "nunca")"
}

# List existing encrypted backups, newest first, as date + size.
backup_list() {
  local dir
  dir="$(backup_dir_path)"
  if [[ ! -d "$dir" ]]; then
    echo "  (todavia no hay respaldos)"
    return 0
  fi
  local -a files=()
  mapfile -t files < <(find "$dir" -maxdepth 1 -type f -name '*.sql.gz.enc' -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}')
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "  (todavia no hay respaldos)"
    return 0
  fi
  local f when size
  for f in "${files[@]}"; do
    when="$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')"
    size="$(du -h "$f" 2>/dev/null | cut -f1)"
    printf '  - %s   %s\n' "$when" "$size"
  done
}
