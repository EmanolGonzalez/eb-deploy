# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`eb-deploy` is a collection of Bash deployment scripts for a web application (.NET 9 backend + Node.js 20 frontend). Artifacts (`.rar` archives) are stored in a **private** Azure Blob Storage container and are never committed here. All scripts target Debian/Ubuntu Linux and require root.

`ops-menu.sh` is the operational entrypoint on the server. `release.sh` is the publishing tool used from dev machines or CI pipelines.

---

## Scripts inventory

| Script | Purpose |
|---|---|
| `ops-menu.sh` | Interactive console — orchestrates all server operations |
| `setup-server.sh` | First-time server provisioning: installs deps, azcopy, creates `config.env` |
| `install.sh` | Installs a component version from Azure (interactive version selection) |
| `update.sh` | Updates a component with strict healthcheck and auto-rollback on failure |
| `rollback.sh` | Restores a component to a previously installed local version |
| `release.sh` | Uploads a new artifact to Azure (run from dev/CI, not the server) |
| `fetch-all.sh` | Ephemeral bootstrapper — downloads all scripts; **never persists on disk** |
| `healthcheck.sh` | Validates backend/frontend health; supports `--soft` and `--strict` modes |
| `status.sh` | Full system status report; supports `--json` for automation |
| `set-db-connection.sh` | Configures `DB_CONNECTION_STRING` in `config.env` |
| `set-health-endpoint.sh` | Configures `BACKEND_HEALTH_ENDPOINT` in `config.env` |
| `set-scripts-url.sh` | Configures `SCRIPTS_BASE_URL` in `config.env` |
| `configure-internal-https.sh` | Sets up internal HTTPS virtual host in Nginx |
| `uninstall.sh` | Removes deployed application; preserves `/app/evidence` and `/app/evidences` |

---

## Architecture

### Bootstrap flow

The entry point for a new server is `ops-menu.sh`, not `setup-server.sh`:

```
1. mkdir /app/scripts && wget ops-menu.sh → chmod +x
2. bash ops-menu.sh → "Actualizar scripts"
      └── fetch-all.sh downloaded to /tmp (ephemeral)
      └── fetch-all.sh downloads all scripts to /app/scripts/
      └── fetch-all.sh deleted automatically (trap)
3. bash setup-server.sh   ← installs deps + creates config.env
4. bash install.sh        ← once per component
```

### fetch-all is always ephemeral

`fetch-all.sh` is **never stored permanently** on the server. `ops-menu.sh` downloads it to a `mktemp` file, runs it, and a `trap` deletes it automatically. The scripts it downloads (`install.sh`, `update.sh`, etc.) do persist in `/app/scripts/`.

### Directory layout on the server

```
/app/
├── config/
│   └── config.env                  # All configuration and secrets (chmod 600)
├── scripts/                        # Operational scripts (updated by fetch-all)
│   ├── ops-menu.sh
│   └── ...
├── releases/
│   ├── frontend/<version>/         # Extracted frontend artifacts
│   └── backend/<version>/          # Extracted backend artifacts
├── frontend/
│   └── current -> /app/releases/frontend/<version>   # Active symlink
└── backend/
    └── current -> /app/releases/backend/<version>    # Active symlink
```

### Symlink pattern

All scripts use `ln -sfn` to atomically switch `/app/<component>/current`. Nginx serves the frontend from `/app/frontend/current`; the `backend` systemd service runs from `/app/backend/current/publish/Api.dll`.

### Blob structure in Azure

```
<container>/
├── frontend/<version>/app.rar
└── backend/<version>/app.rar
```

Versions follow semver (`1.0.0`, `1.0.1`, ...). `release.sh` auto-increments the patch number.

---

## Configuration: config.env

**Single source of truth.** All configuration and secrets live in `/app/config/config.env` with `chmod 600`. There are no separate `.txt` config files.

```bash
CONFIG_VERSION="1"

# --- Required ---
STORAGE_ACCOUNT=""        # Azure Storage account name
CONTAINER_NAME=""         # Azure container name
BASE_URL=""               # https://<account>.blob.core.windows.net/<container>

# --- Scripts ---
SCRIPTS_BASE_URL=""       # Raw GitHub base URL for fetch-all (ops-menu.sh)

# --- Optional ---
NGINX_SERVER_NAME=""      # Nginx server_name value (defaults to _)
BACKEND_HEALTH_ENDPOINT="" # Override for health check URL

# --- Secrets ---
DB_CONNECTION_STRING=""   # ConnectionStrings:DefaultConnection for appsettings.json
```

### load_config()

Every script that needs config sources it through a `load_config()` function:

```bash
load_config() {
  [[ ! -f "$CONFIG_FILE" ]] && { err "config.env not found."; exit 1; }
  source "$CONFIG_FILE"
  # validates required vars: STORAGE_ACCOUNT, CONTAINER_NAME, BASE_URL
  # strips trailing slash from BASE_URL
}
```

### update_config_value()

Scripts that write back to `config.env` use `update_config_value()`. This function reads the file line by line, replaces the matching key, and writes atomically via a temp file. It handles special characters (backslashes, double quotes) in values:

```bash
update_config_value() {
  local key="$1" value="$2"
  local safe="${value//\\/\\\\}"; safe="${safe//\"/\\\"}"
  local tmp found=false
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^"${key}=" ]]; then
      printf '%s="%s"\n' "$key" "$safe" >> "$tmp"
      found=true
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$CONFIG_FILE"
  [[ "$found" == false ]] && printf '\n%s="%s"\n' "$key" "$safe" >> "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}
```

Scripts that use `update_config_value()`: `install.sh`, `update.sh`, `rollback.sh`, `set-db-connection.sh`, `set-health-endpoint.sh`, `set-scripts-url.sh`.

---

## SAS token — security model

> **The SAS token is never written to disk — not in `config.env`, not anywhere.**

- Requested interactively via `read -rsp` (silent input) in every operation that needs Azure access
- Exists only in memory during script execution
- Discarded automatically when the script exits
- `AZURE_SAS_TOKEN` env var is accepted only for CI/CD pipelines — never export it in interactive sessions

Scripts that request the SAS: `install.sh`, `update.sh`, `release.sh`.
`rollback.sh` does not need it — operates entirely on local files.

---

## Azure Storage: azcopy

All Azure Blob operations use `azcopy`. `curl` + XML parsing is not used.

- **Listing versions**: `azcopy list "<container_url>?<SAS>"`
- **Downloading artifacts**: `azcopy copy "<blob_url>?<SAS>" /tmp/...`
- **Uploading artifacts**: `azcopy copy /local/app.rar "<blob_url>?<SAS>" --overwrite=false`

`azcopy` is installed automatically by `setup-server.sh` (detects x86_64 or aarch64).

---

## Coding conventions

### All scripts must follow

```bash
#!/usr/bin/env bash
set -euo pipefail
```

### Standard logging functions

Every script defines these four:

```bash
log()  { echo -e "\033[1;34m==> $*\033[0m"; }
err()  { echo -e "\033[1;31mError: $*\033[0m" >&2; }
ok()   { echo -e "\033[1;32m OK  $*\033[0m"; }
warn() { echo -e "\033[1;33mWARN $*\033[0m"; }
```

### require_root()

Every script must call `require_root` as the first thing in its main flow:

```bash
require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Este script debe ejecutarse como root."
    exit 1
  fi
}
```

### arrow_select()

Interactive menus use `arrow_select` (numeric selection, validated loop):

```bash
arrow_select() {
  local prompt="$1"; shift
  local options=("$@")
  ...
  ARROW_SELECTION="${options[$((idx-1))]}"
}
```

Result is returned via `$ARROW_SELECTION`.

### "Use saved or enter new" pattern

Scripts that have a persisted value in `config.env` follow this pattern (same as DB connection in `install.sh`/`update.sh`):

```bash
if [[ -n "${SAVED_VALUE:-}" ]]; then
  log "Valor configurado: $SAVED_VALUE"
  arrow_select "¿Qué deseas usar?" "Usar el configurado" "Ingresar otro"
  [[ "$ARROW_SELECTION" == "Ingresar otro" ]] && prompt_new_value
else
  prompt_new_value
fi
```

### set-*.sh scripts pattern

Scripts that configure a value in `config.env` follow a consistent pattern:
1. `require_root`
2. Verify `config.env` exists
3. Source `config.env` to read current value
4. Show current value if set
5. Accept value from `$1` or interactive prompt
6. Validate input
7. Call `update_config_value`
8. Optionally apply immediately and offer service restart

---

## Key constraints

- All scripts run as root — `EUID` check enforced in every script.
- Target OS: Debian/Ubuntu (uses `apt`, `systemd`, `ss`, `unrar`, `wget`).
- `fetch-all.sh` must never be executed from a permanent path — always from a `mktemp` file.
- `fetch-all.sh` must list **all** scripts in its `SCRIPTS` array so they are kept up to date.
- `config.env` is the single config file — do not create new `.txt` config files.
- `update_config_value()` must be used for all writes to `config.env` — never `echo >` or `printf >` the whole file except in `setup-server.sh`'s initial write.
- No application source code lives here — only deployment tooling.
- No CI/CD pipelines are defined in this repository.
