# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`eb-deploy` is a public collection of Bash deployment scripts for a web application (Node.js frontend + .NET 8 backend). Artifacts (`.rar` archives) are stored in a **private** Azure Blob Storage container and are never committed here. All scripts target Debian/Ubuntu Linux and require root.

## Running the scripts

```bash
# First-time server setup (installs Nginx, Node.js 20, .NET 8, systemd, runs install.sh)
bash setup-server.sh

# Download all scripts from a GitHub raw URL to the current directory
bash fetch-all.sh https://raw.githubusercontent.com/<user>/<repo>/main

# Install a version (interactive: selects component and version from Azure)
AZURE_SAS_TOKEN="?token" bash install.sh

# Update to a newer version (auto-rollbacks on healthcheck failure)
AZURE_SAS_TOKEN="?token" bash update.sh

# Rollback to a locally installed version (also called automatically by update.sh)
bash rollback.sh

# Run healthcheck manually
bash healthcheck.sh
```

## Architecture

### Deployment flow

`setup-server.sh` is the entry point for a new server. It installs system dependencies, creates the directory structure at `/app/`, writes Nginx and systemd unit templates, then delegates to `install.sh` for the initial application deployment.

For ongoing maintenance, `install.sh`, `update.sh`, and `rollback.sh` are used independently.

### Directory layout on the server

```
/app/
├── config/storage.conf        # Created by install.sh on first run (STORAGE_ACCOUNT, CONTAINER_NAME, BASE_URL)
├── releases/
│   ├── frontend/<version>/    # Extracted frontend artifacts
│   └── backend/<version>/     # Extracted backend artifacts
├── frontend/current -> /app/releases/frontend/<version>   # Active symlink
└── backend/current  -> /app/releases/backend/<version>    # Active symlink
```

### Symlink pattern

All scripts use `ln -sfn` to atomically switch `/app/<component>/current` to a new release directory. Nginx serves the frontend from `/app/releases/frontend/current`; the systemd `backend` service runs the .NET DLL from `/app/releases/backend/current`.

### Artifact naming in Azure

Blobs follow the path `<COMPONENT>/<VERSION>/app.rar` inside the configured container. Version lists are fetched via the Azure Blob Storage XML listing API (`?restype=container&comp=list`). `install.sh` and `update.sh` filter the list to show only versions **greater than** the currently installed one.

### SAS token handling

The SAS token (starting with `?`) is never written to disk. It is read from the `$AZURE_SAS_TOKEN` environment variable or prompted interactively. `update.sh` offers to reuse a token already in the environment.

### Healthcheck

`healthcheck.sh` checks three things in order:
1. The `backend` systemd service is active.
2. Port `3000` is listening.
3. `http://localhost:3000/health` returns HTTP 200.

`update.sh` runs the healthcheck after deployment and automatically calls `rollback.sh` if it fails.

### Configuration file

`/app/config/storage.conf` stores `STORAGE_ACCOUNT`, `CONTAINER_NAME`, and `BASE_URL`. It is sourced by `update.sh` and `rollback.sh` (they exit if missing). `install.sh` creates it interactively on first run.

## Key constraints

- All scripts must be run as root (`EUID` check enforced in every script).
- Target OS: Debian/Ubuntu (uses `apt`, `systemd`, `ss`, `unrar`).
- No CI/CD pipelines are defined in this repository; pipelines are managed externally.
- No application source code lives here — only deployment tooling.
