#!/usr/bin/env bash
set -e

CONFIG_FILE="/app/config/storage.conf"
DB_CONNECTION_FILE="/app/config/db-connection.txt"
if [[ ! -f "$CONFIG_FILE" ]]; then
	echo "Error: Configuration file $CONFIG_FILE not found." >&2
	exit 1
fi
source "$CONFIG_FILE"

log() { echo -e "\033[1;34m==> $*\033[0m"; }
err() { echo -e "\033[1;31mError: $*\033[0m" >&2; }

load_db_connection_if_exists() {
	if [[ -f "$DB_CONNECTION_FILE" ]]; then
		DB_CONNECTION_STRING="$(cat "$DB_CONNECTION_FILE")"
		if [[ -n "$DB_CONNECTION_STRING" ]]; then
			log "DB connection string loaded from $DB_CONNECTION_FILE"
		fi
	fi
}

extract_connection_value() {
	local connection_string="$1"
	local key_regex="$2"
	echo "$connection_string" | sed -nE "s/.*${key_regex}=([^;]+).*/\1/ip"
}

connection_summary() {
	local connection_string="$1"
	local server database user

	server="$(extract_connection_value "$connection_string" 'server')"
	database="$(extract_connection_value "$connection_string" 'initial catalog|database')"
	user="$(extract_connection_value "$connection_string" 'user id|uid')"

	[[ -z "$server" ]] && server="(desconocido)"
	[[ -z "$database" ]] && database="(desconocida)"
	[[ -z "$user" ]] && user="(integrated/no user)"

	printf 'server=%s | db=%s | user=%s' "$server" "$database" "$user"
}

save_db_connection_string() {
	local connection_string="$1"
	mkdir -p /app/config
	printf '%s' "$connection_string" > "$DB_CONNECTION_FILE"
	chmod 600 "$DB_CONNECTION_FILE"
	DB_CONNECTION_STRING="$connection_string"
	log "DB connection string saved in $DB_CONNECTION_FILE"
}

prompt_new_db_connection_string() {
	local value
	read -rsp "Enter ConnectionStrings:DefaultConnection value: " value
	echo

	if [[ -z "$value" ]]; then
		err "Connection string is required."
		exit 1
	fi

	save_db_connection_string "$value"
}

ensure_db_connection_for_backend() {
	if [[ "$COMPONENT" != "backend" ]]; then
		return
	fi

	if [[ -n "${DB_CONNECTION_STRING:-}" ]]; then
		local summary use_label
		summary="$(connection_summary "$DB_CONNECTION_STRING")"
		use_label="Usar actual (${summary})"
		arrow_select "Se detectó una cadena de conexión guardada. ¿Qué deseas hacer?" "$use_label" "Usar otra"

		if [[ "$ARROW_SELECTION" == "Usar otra" ]]; then
			prompt_new_db_connection_string
		else
			log "Using existing DB connection string ($summary)"
		fi
		return
	fi

	arrow_select "No hay cadena de conexión guardada para backend." "Ingresar ahora" "Continuar sin definir"
	if [[ "$ARROW_SELECTION" == "Ingresar ahora" ]]; then
		prompt_new_db_connection_string
	else
		log "Continuing without DB connection string. appsettings.json will not be modified."
	fi
}

escape_for_sed_replacement() {
	local input="$1"
	input="${input//\\/\\\\}"
	input="${input//&/\\&}"
	printf '%s' "$input"
}

apply_connection_string_to_file() {
	local target_file="$1"
	local connection_string="$2"

	if [[ ! -f "$target_file" ]]; then
		err "File not found: $target_file"
		exit 1
	fi

	if ! grep -q '"DefaultConnection"' "$target_file"; then
		err "DefaultConnection key not found in: $target_file"
		exit 1
	fi

	local escaped
	escaped="$(escape_for_sed_replacement "$connection_string")"
	sed -i -E "s#(\"DefaultConnection\"[[:space:]]*:[[:space:]]*\").*(\")#\\1${escaped}\\2#" "$target_file"
	log "Connection string applied to $target_file"
}

apply_db_connection_if_backend() {
	if [[ "$COMPONENT" != "backend" ]]; then
		return
	fi

	if [[ -z "${DB_CONNECTION_STRING:-}" ]]; then
		log "DB connection string file not found ($DB_CONNECTION_FILE). Skipping appsettings.json update."
		return
	fi

	local backend_appsettings="${PREVIOUS_RELEASE_DIR}/publish/appsettings.json"
	apply_connection_string_to_file "$backend_appsettings" "$DB_CONNECTION_STRING"
}

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
load_db_connection_if_exists
ensure_db_connection_for_backend

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

apply_db_connection_if_backend

log "Restoring symlink: $CURRENT_LINK -> $PREVIOUS_RELEASE_DIR"
ln -sfn "$PREVIOUS_RELEASE_DIR" "$CURRENT_LINK"

if [[ "$COMPONENT" == "backend" ]]; then
	log "Restarting backend service"
	systemctl restart backend || true
fi

log "Running healthcheck..."
bash "$(dirname "$0")/healthcheck.sh" "$COMPONENT" --soft || true

log "Rollback completed successfully."
