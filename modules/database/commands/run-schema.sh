#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/database/commands/run-schema.sh — REMOVIDO
#
# Este comando quedo OBSOLETO y fue removido: el esquema lo aplica EF Core
# automaticamente al arrancar el backend (migraciones EF = unica fuente de
# verdad). Correr DDL a mano desincroniza __EFMigrationsHistory y deja al
# backend en crash-loop ("Duplicate column").
#
# Este archivo se conserva SOLO como salvaguarda hasta que la rama lo elimine
# con `git rm`; invocarlo ya no ejecuta ningun esquema.
#
# Para partir de una base limpia:
#     deploy database reset-schema   (borra las tablas, conserva la base;
#                                     EF reconstruye el esquema al arrancar)
# Si falta la base entera:
#     deploy database create         (crea la base vacia; EF migra al arrancar)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../core/logger.sh"

err "'run-schema' fue removido: el esquema lo aplica EF al arrancar el backend."
log "Base limpia: deploy database reset-schema | Base inexistente: deploy database create"
exit 1
