#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# modules/nginx/commands/configure-https.sh
#
# Activa HTTPS con auto-deteccion en drop zone + copia gestionada al target
# de nginx + persistencia en config.env (UNICA fuente de verdad). Despues
# delega a setup-server.sh para regenerar el unit via drift detection.
#
# Drop zone:  /app/artifacts/ssl/       (root:root 700, el operador deja aca)
# Target:     /etc/nginx/ssl/           (root:root 700, nginx lee aca)
#
# Convencion: si la drop zone contiene exactamente UN par .crt|.pem + .key,
# se usan en automatico. Sino, modo interactivo.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MODULE_DIR/lib/nginx-common.sh"

DROP_ZONE="/app/artifacts/ssl"
TARGET_DIR="/etc/nginx/ssl"

require_root
load_config || true

# Snapshot de valores previos para detectar orfanatos despues del swap.
OLD_SSL_CERT="${NGINX_SSL_CERT:-}"
OLD_SSL_KEY="${NGINX_SSL_KEY:-}"

# -----------------------------------------------------------------------------
# 1. Dominio — usar el de config.env o pedirlo.
# -----------------------------------------------------------------------------
current_name="${NGINX_SERVER_NAME:-_}"
if [[ -z "$current_name" || "$current_name" == "_" ]]; then
  read -rp "Dominio para HTTPS (ej: app.dominio.com): " new_name
  if [[ -z "$new_name" ]]; then
    err "El dominio es obligatorio para HTTPS."
    exit 1
  fi
  update_config_value "NGINX_SERVER_NAME" "$new_name"
  current_name="$new_name"
  log "NGINX_SERVER_NAME = $new_name"
else
  log "Usando dominio existente: $current_name"
fi

# -----------------------------------------------------------------------------
# 2. Auto-detect en drop zone — exige UN solo par para automatico.
# -----------------------------------------------------------------------------
shopt -s nullglob
crt_files=("$DROP_ZONE"/*.crt "$DROP_ZONE"/*.pem)
key_files=("$DROP_ZONE"/*.key)
shopt -u nullglob

src_cert=""
src_key=""

if [[ ${#crt_files[@]} -eq 1 && ${#key_files[@]} -eq 1 ]]; then
  src_cert="${crt_files[0]}"
  src_key="${key_files[0]}"
  ok "Par detectado en drop zone $DROP_ZONE:"
  log "  cert: $src_cert"
  log "  key : $src_key"
elif [[ ${#crt_files[@]} -gt 0 || ${#key_files[@]} -gt 0 ]]; then
  warn "Drop zone $DROP_ZONE tiene archivos pero no un par unico (.crt|.pem + .key):"
  for f in "${crt_files[@]}" "${key_files[@]}"; do
    log "  $f"
  done
  log "Modo interactivo: especifica las rutas a usar."
else
  log "Drop zone $DROP_ZONE vacia — modo interactivo."
  log "(Tip: para futuras rotaciones, copia el par ahi y re-corre este comando.)"
fi

# Fallback interactivo si no hubo auto-detect.
if [[ -z "$src_cert" || -z "$src_key" ]]; then
  read -rp "Ruta al certificado SSL (.crt o .pem): " src_cert
  if [[ ! -f "$src_cert" ]]; then
    err "Certificado no encontrado: $src_cert"
    exit 1
  fi
  read -rp "Ruta a la clave privada (.key): " src_key
  if [[ ! -f "$src_key" ]]; then
    err "Clave privada no encontrada: $src_key"
    exit 1
  fi
fi

# -----------------------------------------------------------------------------
# 3. Copia gestionada — install setea owner/group/perms en una operacion.
# -----------------------------------------------------------------------------
dst_cert="$TARGET_DIR/${current_name}.crt"
dst_key="$TARGET_DIR/${current_name}.key"

mkdir -p "$TARGET_DIR"
chown root:root "$TARGET_DIR"
chmod 700 "$TARGET_DIR"

install -m 644 -o root -g root "$src_cert" "$dst_cert"
install -m 600 -o root -g root "$src_key" "$dst_key"

ok "Certificados copiados al target con permisos correctos:"
log "  $dst_cert (644 root:root)"
log "  $dst_key (600 root:root)"

# -----------------------------------------------------------------------------
# 4. Persistir paths FINALES (no los de la drop zone) en config.env.
# -----------------------------------------------------------------------------
update_config_value "NGINX_SSL_CERT" "$dst_cert"
update_config_value "NGINX_SSL_KEY" "$dst_key"
ok "config.env actualizado con paths finales."

# -----------------------------------------------------------------------------
# 5. Limpieza de orfanatos en /etc/nginx/ssl/ (si el dominio cambio).
# -----------------------------------------------------------------------------
clean_orphan() {
  local old_file="$1" new_file="$2" label="$3"
  if [[ -n "$old_file" \
        && "$old_file" != "$new_file" \
        && "$old_file" == "$TARGET_DIR"/* \
        && -f "$old_file" ]]; then
    log "Eliminando $label huerfano: $old_file"
    shred -u "$old_file" 2>/dev/null || rm -f "$old_file"
  fi
}
clean_orphan "$OLD_SSL_CERT" "$dst_cert" "cert"
clean_orphan "$OLD_SSL_KEY"  "$dst_key"  "key"

# -----------------------------------------------------------------------------
# 6. Limpieza de la drop zone: shred la KEY (cert puede quedar, es publico).
#    Solo si la key vino de la drop zone (auto-detect), no de un path manual.
# -----------------------------------------------------------------------------
if [[ "$src_key" == "$DROP_ZONE"/* ]]; then
  log "Shred de la key en drop zone: $src_key"
  shred -u "$src_key" 2>/dev/null || rm -f "$src_key"
fi

# -----------------------------------------------------------------------------
# 7. Delegar a setup-server.sh — drift detection regenera el unit de nginx.
# -----------------------------------------------------------------------------
log "Aplicando via setup-server.sh (NON_INTERACTIVE)..."
NON_INTERACTIVE=1 bash /app/deploy/setup/setup-server.sh

echo
ok "HTTPS activo en https://${current_name}/"
log "Validar: curl -kI https://${current_name}/"
