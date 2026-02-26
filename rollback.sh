#!/usr/bin/env bash
set -e

CONFIG_FILE="/app/config/storage.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
	echo "Error: Configuration file $CONFIG_FILE not found." >&2
	exit 1
fi
source "$CONFIG_FILE"

log() { echo -e "\033[1;34m==> $*\033[0m"; }
err() { echo -e "\033[1;31mError: $*\033[0m" >&2; }
require_root() { [[ "$EUID" -ne 0 ]] && err "Must be run as root." && exit 1; }

arrow_select() {
	local prompt="$1"; shift
	local options=("$@")
	local num=${#options[@]}
	local idx
	echo "$prompt"
	echo "Escribe el número de la opción deseada y presiona Enter:"
	for i in "${!options[@]}"; do
		echo "  $((i+1))) ${options[$i]}"
	done
	while true; do
		read -rp "Opción: " idx
		if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= num )); then
			ARROW_SELECTION="${options[$((idx-1))]}"
			return
		fi
		err "Opción inválida. Introduce un número entre 1 y $num."
	done
}

select_component() {
	arrow_select "Select component:" frontend backend
	COMPONENT="$ARROW_SELECTION"
}

require_root
select_component

CURRENT_LINK="/app/${COMPONENT}/current"
RELEASES_DIR="/app/releases/${COMPONENT}"

mapfile -t VERSIONS < <(ls -1 "$RELEASES_DIR" | sort)
arrow_select "Select version to rollback:" "${VERSIONS[@]}"
PREVIOUS_VERSION="$ARROW_SELECTION"

PREVIOUS_RELEASE_DIR="${RELEASES_DIR}/${PREVIOUS_VERSION}"
[[ ! -d "$PREVIOUS_RELEASE_DIR" ]] && err "Release directory not found." && exit 1

log "Restoring symlink: $CURRENT_LINK -> $PREVIOUS_RELEASE_DIR"
ln -sfn "$PREVIOUS_RELEASE_DIR" "$CURRENT_LINK"

[[ "$COMPONENT" == "backend" ]] && log "Restarting backend service" && systemctl restart backend || true

log "Running healthcheck..."
if ! bash "$(dirname "$0")/healthcheck.sh"; then
	err "Healthcheck failed after rollback."
	exit 1
fi

log "Rollback completed successfully."
