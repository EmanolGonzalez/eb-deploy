#!/usr/bin/env bash
# =============================================================================
# core/csp.sh — Hash CSP del <style> inline del loader inicial (index.html)
#
# POR QUE EXISTE ESTE ARCHIVO
# El index.html lleva un <style> inline (loader pre-boot, para evitar FOUC).
# CSP lo permite por HASH exacto -- nginx sirve archivos estaticos y no puede
# generar un nonce por request. Ese hash vivia hardcodeado en setup-server.sh
# y se desincronizaba en silencio con cada build del frontend: la CSP bloqueaba
# el bloque y el arranque se veia sin estilos, sin ningun error en el servidor.
#
# Ahora el hash se CALCULA del archivo real y se persiste. Nadie lo escribe
# a mano, asi que no puede desfasarse.
#
# DOS TRAMPAS (las dos costaron un hash incorrecto):
#
#   1. El comentario del <head> contiene el literal "<style>". Un regex
#      naive /<style>(.*?)<\/style>/ matchea DESDE el comentario y produce
#      un hash que no corresponde a nada. Hay que tomar el ULTIMO "<style>"
#      anterior al "</style>".
#
#   2. Vite minifica el bloque y normaliza CRLF -> LF. El hash del fuente
#      (frontend/index.html) NUNCA matchea el del build. Se calcula SIEMPRE
#      sobre el archivo compilado/desplegado, que es el que el browser recibe
#      y hashea.
# =============================================================================

CSP_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$CSP_CORE_DIR/logger.sh" ]] && source "$CSP_CORE_DIR/logger.sh"

# Donde se persiste el hash vigente. render_nginx_site_config() lo lee de aca,
# asi que una corrida de setup-server.sh NO revierte lo que dejo el install.
CSP_HASH_FILE="${CSP_HASH_FILE:-/app/config/csp-style-hash}"

# Sitio nginx generado por setup-server.sh.
NGINX_SITE_FILE="${NGINX_SITE_FILE:-/etc/nginx/sites-available/app}"

# Fallback para un servidor recien seteado, ANTES del primer 'frontend install'
# (setup corre antes que el install en el orden del runbook). El install lo
# recalcula del artefacto real y pisa este valor.
CSP_STYLE_HASH_DEFAULT="d8HOkFH1+cCrhGUWPIv+SUZJu4wGAlCn9WtihiGYNMg="

# -----------------------------------------------------------------------------
# compute_csp_style_hash <index.html>
#   Imprime el hash base64 (sin el prefijo 'sha256-') del <style> inline.
# -----------------------------------------------------------------------------
compute_csp_style_hash() {
  local index_file="$1"

  if [[ ! -f "$index_file" ]]; then
    err "No se encontro el index.html para calcular el hash CSP: $index_file"
    return 1
  fi
  if ! command -v perl &>/dev/null; then
    err "perl no disponible (necesario para extraer el <style> inline)."
    return 1
  fi
  if ! command -v openssl &>/dev/null; then
    err "openssl no disponible (necesario para el hash SHA-256)."
    return 1
  fi

  # El bloque va a un archivo temporal, NO a una variable: la sustitucion de
  # comandos $(...) come los newlines finales, y si el bloque terminara en
  # salto de linea el hash saldria distinto al que calcula el browser. Un
  # deploy roto por un \n invisible es exactamente lo que no queremos.
  local tmp_block
  tmp_block="$(mktemp)"

  # Importante: perl y openssl NO van en una sola pipeline. El status de una
  # pipeline es el del ULTIMO comando, asi que un perl que no encuentra el
  # bloque pasaba desapercibido y openssl terminaba hasheando la cadena vacia
  # (da 47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=, que parece un hash
  # perfectamente valido y bloquea el loader).
  # La extraccion va del PRIMER <style...> a su </style>, con una expresion
  # regular sobre la etiqueta de apertura.
  #
  # Antes buscaba el literal "<style>" con rindex, hacia atras desde el primer
  # "</style>". La idea era saltear el "<style>" que aparece dentro de un
  # comentario HTML ANTES del bloque. Pero el mismo truco se da vuelta en
  # cuanto el texto "<style>" aparece DENTRO del bloque: rindex encuentra esa
  # mencion y el hash sale de un fragmento del CSS, no del bloque entero.
  #
  # Paso exactamente eso: un comentario dentro del CSS explicando esta misma
  # regla de CSP mencionaba "<style>", el hash se calculo sobre los ultimos
  # 1941 bytes de un bloque de 4639, y el navegador bloqueo el loader completo
  # reclamando el hash del bloque de verdad. El comentario escrito para
  # explicar la regla fue el que la rompio.
  #
  # Con el primer <style de apertura no hay ambiguedad: lo que venga despues,
  # comentarios incluidos, es contenido.
  if ! perl -0777 -ne '
    my $html = $_;
    $html =~ s/<!--.*?-->//gs;
    exit 1 unless $html =~ /<style\b[^>]*>/;
    my $s = $+[0];
    my $e = index($html, "</style>", $s);
    exit 1 if $e < 0;
    print substr($html, $s, $e - $s);
  ' "$index_file" > "$tmp_block"; then
    rm -f "$tmp_block"
    err "No se encontro el bloque <style> del loader en: $index_file"
    return 1
  fi

  if [[ ! -s "$tmp_block" ]]; then
    rm -f "$tmp_block"
    err "El bloque <style> del loader esta vacio en: $index_file"
    err "  Hashear un bloque vacio daria una CSP que bloquea el loader."
    return 1
  fi

  local hash
  hash="$(openssl dgst -sha256 -binary "$tmp_block" | openssl base64 -A)"
  rm -f "$tmp_block"

  # 43 chars base64 + '=' = 32 bytes de SHA-256. Cualquier otra cosa es una
  # extraccion rota: mejor fallar que escribir basura en la CSP.
  if [[ ! "$hash" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    err "El hash CSP calculado es invalido: '$hash'"
    err "  Archivo: $index_file"
    return 1
  fi

  printf '%s\n' "$hash"
}

# -----------------------------------------------------------------------------
# read_csp_style_hash
#   Hash persistido, o el default si todavia no se instalo ningun frontend.
# -----------------------------------------------------------------------------
read_csp_style_hash() {
  local stored=""
  if [[ -f "$CSP_HASH_FILE" ]]; then
    stored="$(tr -d ' \t\r\n' < "$CSP_HASH_FILE")"
  fi

  if [[ "$stored" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    printf '%s\n' "$stored"
  else
    printf '%s\n' "$CSP_STYLE_HASH_DEFAULT"
  fi
}

# -----------------------------------------------------------------------------
# write_csp_style_hash <hash>
# -----------------------------------------------------------------------------
write_csp_style_hash() {
  local hash="$1"
  mkdir -p "$(dirname "$CSP_HASH_FILE")"
  printf '%s\n' "$hash" > "$CSP_HASH_FILE"
  chmod 644 "$CSP_HASH_FILE"
}

# -----------------------------------------------------------------------------
# sync_csp_style_hash <index.html>
#   Recalcula el hash del frontend desplegado, lo persiste y lo aplica a la
#   config de nginx. Recarga nginx SOLO si el hash cambio y 'nginx -t' pasa.
#   Idempotente: si no cambio nada, no toca nginx.
# -----------------------------------------------------------------------------
sync_csp_style_hash() {
  local index_file="$1"

  local new_hash
  if ! new_hash="$(compute_csp_style_hash "$index_file")"; then
    err "No se pudo calcular el hash CSP. La CSP queda como estaba."
    err "El loader inicial puede verse sin estilos hasta corregirlo."
    return 1
  fi

  local current_hash
  current_hash="$(read_csp_style_hash)"
  write_csp_style_hash "$new_hash"

  if [[ ! -f "$NGINX_SITE_FILE" ]]; then
    warn "No existe $NGINX_SITE_FILE — hash CSP guardado, se aplicara en el proximo setup."
    return 0
  fi

  # Que este en el archivo, no solo que haya cambiado: la config pudo haberse
  # regenerado por fuera (setup-server.sh) con el valor viejo.
  if [[ "$new_hash" == "$current_hash" ]] && grep -qF "sha256-${new_hash}" "$NGINX_SITE_FILE"; then
    ok "Hash CSP del loader sin cambios (sha256-${new_hash})."
    return 0
  fi

  log "Hash CSP del loader cambio — actualizando nginx."
  log "  Anterior : sha256-${current_hash}"
  log "  Nuevo    : sha256-${new_hash}"

  local backup="${NGINX_SITE_FILE}.bak.$(date '+%Y%m%d-%H%M%S')"
  cp -p "$NGINX_SITE_FILE" "$backup"

  sed -i "s|'sha256-[A-Za-z0-9+/=]*'|'sha256-${new_hash}'|g" "$NGINX_SITE_FILE"

  # Sin pipeline: 'nginx -t | sed' devuelve el status de sed (siempre 0) y un
  # nginx -t fallido pasaba como exitoso, recargando una config rota.
  local nginx_test_out
  if ! nginx_test_out="$(nginx -t 2>&1)"; then
    printf '%s\n' "$nginx_test_out" | sed 's/^/      /'
    err "nginx -t fallo tras actualizar la CSP. Restaurando la config anterior."
    cp -p "$backup" "$NGINX_SITE_FILE"
    err "  Restaurado desde: $backup"
    return 1
  fi
  printf '%s\n' "$nginx_test_out" | sed 's/^/      /'

  systemctl reload nginx
  ok "CSP actualizada y nginx recargado (sha256-${new_hash})."
  log "  Backup de la config anterior: $backup"
}
