#!/usr/bin/env bash
# =============================================================================
# core/logger.sh — Logging and output utilities
# =============================================================================

# P4: log() e info() comparten el prefijo "==>" pero difieren en enfasis:
#   log()  -> linea COMPLETA en azul bold. Usar para pasos/acciones del flujo.
#   info() -> solo el "==>" en azul, texto en color normal. Usar para datos o
#             notas contextuales de menor jerarquia visual.
# Se mantienen ambas (no se unifican) para no romper callers existentes.
log()     { echo -e "\033[1;34m==> $*\033[0m"; }
ok()      { echo -e "\033[1;32m OK  $*\033[0m"; }
err()     { echo -e "\033[1;31mERR  $*\033[0m" >&2; }
warn()    { echo -e "\033[1;33mWARN $*\033[0m"; }
step()    { echo; echo -e "\033[1;37m--- $* ---\033[0m"; }
info()    { echo -e "\033[1;34m==>\033[0m $*"; }
divider() { echo "========================================"; }
