#!/usr/bin/env bash
# =============================================================================
# core/input.sh — Interactive input utilities
# =============================================================================

# Menu numérico simple. Sets MENU_SELECTION.
# Usage: menu_select "Prompt" "Option 1" "Option 2" "Option 3"
menu_select() {
  local prompt="$1"; shift
  local options=("$@")
  local num=${#options[@]}
  local idx
  echo
  echo "$prompt"
  echo "Escribe el numero de la opcion y presiona Enter:"
  for i in "${!options[@]}"; do
    echo "  $((i+1))) ${options[$i]}"
  done
  while true; do
    read -rp "Opcion: " idx
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= num )); then
      MENU_SELECTION="${options[$((idx-1))]}"
      return
    fi
    err "Opcion invalida. Introduce un numero entre 1 y $num."
  done
}

# Confirm prompt. Returns 0 on yes.
confirm() {
  local prompt="$1"
  read -rp "$prompt [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}
