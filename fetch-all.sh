#!/usr/bin/env bash
set -e

# fetch-all.sh — Descarga todos los scripts necesarios desde una URL base raw de GitHub
# Uso:
#   bash fetch-all.sh https://raw.githubusercontent.com/usuario/repositorio/rama

SCRIPTS=(ops-menu.sh install.sh update.sh rollback.sh uninstall.sh healthcheck.sh status.sh set-db-connection.sh set-health-endpoint.sh set-scripts-url.sh configure-internal-https.sh setup-server.sh release.sh)

if [[ -z "$1" ]]; then
  read -rp "Introduce la URL base raw de GitHub: " BASE_URL
  if [[ -z "$BASE_URL" ]]; then
    echo "La URL base es obligatoria."
    exit 1
  fi
else
  BASE_URL="$1"
fi

for script in "${SCRIPTS[@]}"; do
  echo "Descargando $script..."
  wget -q -O "$script" "$BASE_URL/$script" || {
    echo "Error al descargar $script" >&2
    exit 1
  }
  chmod +x "$script"
  echo "$script descargado y marcado como ejecutable."
done

echo "Todos los scripts fueron descargados correctamente."
