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
	local selected=0
	local num=${#options[@]}
	local key k2 k3
	echo "$prompt"
	tput civis 2>/dev/null
	_draw_menu() {
		for i in "${!options[@]}"; do
			[[ $i -eq $selected ]] \
				&& echo -e "  \033[1;36m>\033[0m \033[7m ${options[$i]} \033[0m" \
				|| echo -e "    ${options[$i]}"
		done
	}
	_draw_menu
	while true; do
		IFS= read -rsn1 key
		if [[ $key == $'\x1b' ]]; then
			IFS= read -rsn1 -t 0.1 k2
			IFS= read -rsn1 -t 0.1 k3
			case "${k2}${k3}" in
				'[A'|'OA') ((selected > 0)) && ((selected--)) ;;
				'[B'|'OB') ((selected < num - 1)) && ((selected++)) ;;
			esac
		elif [[ $key == '' ]]; then
			break
		fi
		tput cuu "$num" 2>/dev/null
		_draw_menu
	done
	tput cnorm 2>/dev/null
	ARROW_SELECTION="${options[$selected]}"
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
