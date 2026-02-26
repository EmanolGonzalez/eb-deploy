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
require_root() {
	if [[ "$EUID" -ne 0 ]]; then
		err "Must be run as root."
		exit 1
	fi
}

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

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--component)
				COMPONENT="$2"
				shift 2
				;;
			--version)
				PREVIOUS_VERSION="$2"
				shift 2
				;;
			*)
				err "Unknown argument: $1"
				exit 1
				;;
		esac
	done
}

require_root
parse_args "$@"
if [[ -z "$COMPONENT" ]]; then
	select_component
fi

CURRENT_LINK="/app/${COMPONENT}/current"
RELEASES_DIR="/app/releases/${COMPONENT}"

if [[ -z "$PREVIOUS_VERSION" ]]; then
	mapfile -t VERSIONS < <(ls -1 "$RELEASES_DIR" | sort -V)
	if [[ ${#VERSIONS[@]} -eq 0 ]]; then
		err "No versions available to rollback."
		exit 1
	fi
	arrow_select "Select version to rollback:" "${VERSIONS[@]}"
	PREVIOUS_VERSION="$ARROW_SELECTION"
fi

PREVIOUS_RELEASE_DIR="${RELEASES_DIR}/${PREVIOUS_VERSION}"
if [[ ! -d "$PREVIOUS_RELEASE_DIR" ]]; then
	err "Release directory not found."
	exit 1
fi

log "Restoring symlink: $CURRENT_LINK -> $PREVIOUS_RELEASE_DIR"
ln -sfn "$PREVIOUS_RELEASE_DIR" "$CURRENT_LINK"

if [[ "$COMPONENT" == "backend" ]]; then
	log "Restarting backend service"
	systemctl restart backend || true
fi

log "Running healthcheck..."
bash "$(dirname "$0")/healthcheck.sh" "$COMPONENT" --soft || true

log "Rollback completed successfully."
