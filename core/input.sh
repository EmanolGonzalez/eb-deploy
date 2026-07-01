#!/usr/bin/env bash
# =============================================================================
# core/input.sh — Interactive input utilities
# =============================================================================

# Menu numérico simple. Sets MENU_SELECTION.
# Usage: menu_select "Prompt" "Option 1" "Option 2" "Option 3"
#
# Ctrl+C / EOF: salida CONTROLADA. En vez de dejar un loop zombie o abortar a
# medias por set -e en un caller que no chequea el return, imprime una linea y
# sale del proceso con exit 130 (convencion estandar para "terminado por SIGINT").
menu_select() {
  local prompt="$1"; shift
  local options=("$@")
  local num=${#options[@]}
  local idx

  # Salida limpia ante Ctrl+C: evita loops zombie y estado a medias.
  trap 'echo; err "Operacion interrumpida (Ctrl+C)."; exit 130' INT

  echo
  echo "$prompt"
  echo "Escribe el numero de la opcion y presiona Enter:"
  for i in "${!options[@]}"; do
    echo "  $((i+1))) ${options[$i]}"
  done
  while true; do
    # Si read recibe EOF (Ctrl+D o stream cerrado), lo tratamos como cancelacion.
    if ! read -rp "Opcion: " idx; then
      echo; err "Entrada cerrada (EOF). Operacion cancelada."
      trap - INT
      exit 130
    fi
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= num )); then
      MENU_SELECTION="${options[$((idx-1))]}"
      trap - INT
      return
    fi
    err "Opcion invalida. Introduce un numero entre 1 y $num."
  done
}

# Confirm prompt. Returns 0 on yes.
# Ctrl+C se maneja de forma controlada (exit 130). EOF se trata como "No".
confirm() {
  local prompt="$1"
  local answer
  trap 'echo; err "Operacion interrumpida (Ctrl+C)."; exit 130' INT
  if ! read -rp "$prompt [y/N]: " answer; then
    echo
    trap - INT
    return 1
  fi
  trap - INT
  [[ "$answer" =~ ^[Yy]$ ]]
}
