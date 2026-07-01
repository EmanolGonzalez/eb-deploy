#!/usr/bin/env bash
# NO usamos 'set -e': este es un diagnostico por capas, queremos seguir
# corriendo aunque una capa falle para mostrar el cuadro completo.
set -uo pipefail
# =============================================================================
# modules/database/commands/check.sh — Diagnostico de conexion a BD
#
# Verifica POR CAPAS y de forma TRANSPARENTE (muestra cada comando que usa):
#   1. Resumen de parametros detectados
#   2. Resolucion DNS del host           (getent hosts)
#   3. Conectividad TCP al puerto         (/dev/tcp con timeout)
#   4. Cliente del motor disponible       (sqlcmd / mariadb)
#   5. Autenticacion + SELECT 1           (sqlcmd / mariadb)
#
# Soporta SqlServer y MariaDB. Imprime el comando exacto de cada paso
# (con la password enmascarada) para que puedas reproducirlo a mano.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_DIR="$(cd "$MODULE_DIR/../.." && pwd)"
source "$MODULE_DIR/lib/prompt-connection.sh"

prompt_connection || exit 1

# ── HELPERS DE PRESENTACION ─────────────────────────────────────────────────

# Imprime el comando que vamos a ejecutar, en cyan, con la password enmascarada.
show_cmd() {
  local rendered="$*"
  if [[ -n "${CONN_PASS:-}" ]]; then
    rendered="${rendered//$CONN_PASS/********}"
  fi
  echo -e "    \033[1;36m\$ ${rendered}\033[0m"
}

FAILED=0
fail() { (( FAILED += 1 )) || true; }

# Detecta si el server es una IP literal (para saltear el check de DNS).
IS_IP=false
[[ "$CONN_SERVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && IS_IP=true

echo ""
divider
echo "  DIAGNOSTICO DE CONEXION - $CONN_PROVIDER"
divider

# ── PASO 1: RESUMEN DE PARAMETROS ───────────────────────────────────────────

step "1/5 — Parametros detectados"
printf "    Motor    : %s\n" "$CONN_PROVIDER"
printf "    Server   : %s\n" "$CONN_SERVER"
printf "    Puerto   : %s\n" "$CONN_PORT"
printf "    Database : %s\n" "$CONN_DB"
printf "    Usuario  : %s\n" "$CONN_USER"
printf "    Password : %s\n" "$([[ -n "${CONN_PASS:-}" ]] && echo '(configurada, oculta)' || echo '(vacia)')"

# ── PASO 2: RESOLUCION DNS ──────────────────────────────────────────────────

step "2/5 — Resolucion DNS del host"
if $IS_IP; then
  ok "'$CONN_SERVER' es una IP literal — no requiere DNS."
else
  echo "  Resolviendo el nombre del host con:"
  show_cmd "getent hosts $CONN_SERVER"
  if getent hosts "$CONN_SERVER" &>/dev/null; then
    resolved="$(getent hosts "$CONN_SERVER" | awk '{print $1}' | head -1)"
    ok "DNS OK — '$CONN_SERVER' resuelve a $resolved"
  else
    err "DNS FALLO — no se pudo resolver '$CONN_SERVER'."
    err "    Revisar: nombre del host, DNS del servidor, /etc/hosts."
    fail
  fi
fi

# ── PASO 3: CONECTIVIDAD TCP AL PUERTO ──────────────────────────────────────

step "3/5 — Conectividad TCP al puerto $CONN_PORT"
echo "  Probando si el puerto esta abierto y accesible con:"
show_cmd "timeout 5 bash -c 'echo > /dev/tcp/$CONN_SERVER/$CONN_PORT'"
if timeout 5 bash -c "echo > /dev/tcp/$CONN_SERVER/$CONN_PORT" 2>/dev/null; then
  ok "TCP OK — puerto $CONN_PORT accesible en '$CONN_SERVER'."
else
  err "TCP FALLO — no se pudo abrir '$CONN_SERVER:$CONN_PORT'."
  err "    Revisar: servicio de BD activo, firewall, puerto correcto."
  fail
fi

# ── PASO 4 + 5: CLIENTE Y AUTENTICACION (por motor) ─────────────────────────

if $PROVIDER_IS_SQLSERVER; then
  # --- SQL Server ----------------------------------------------------------
  step "4/5 — Cliente sqlcmd disponible"
  # mssql-tools no siempre esta en PATH; lo buscamos en rutas conocidas.
  for d in /opt/mssql-tools18/bin /opt/mssql-tools/bin; do
    [[ -d "$d" && ":$PATH:" != *":$d:"* ]] && export PATH="$PATH:$d"
  done
  if command -v sqlcmd &>/dev/null; then
    ok "sqlcmd encontrado en: $(command -v sqlcmd)"

    step "5/5 — Autenticacion + SELECT 1"
    echo "  Conectando y ejecutando un query de prueba con:"
    show_cmd "sqlcmd -C -S $CONN_SERVER,$CONN_PORT -U $CONN_USER -P $CONN_PASS -d $CONN_DB -Q \"SELECT 1\""
    if out="$(sqlcmd -C -S "$CONN_SERVER,$CONN_PORT" -U "$CONN_USER" -P "$CONN_PASS" -d "$CONN_DB" -Q "SELECT 1" -b -t 10 2>&1)"; then
      ok "AUTH OK — login y SELECT 1 exitosos sobre db=$CONN_DB."
    else
      err "AUTH FALLO — sqlcmd no pudo completar el query."
      err "    Salida: $out"
      fail
    fi
  else
    err "sqlcmd NO disponible. Instalalo con el bootstrap o manualmente."
    err "    bash $DEPLOY_DIR/setup/bootstrap.sh"
    fail
  fi

else
  # --- MariaDB -------------------------------------------------------------
  step "4/5 — Cliente mariadb/mysql disponible"
  client=""
  command -v mariadb &>/dev/null && client="mariadb"
  [[ -z "$client" ]] && command -v mysql &>/dev/null && client="mysql"

  if [[ -z "$client" ]]; then
    # Intento de instalar desde assets/*.deb (sin acceso a internet).
    debs=("$DEPLOY_DIR/assets/database/"*mariadb*.deb)
    if [[ -f "${debs[0]:-}" ]]; then
      step "Instalando mariadb-client desde assets..."
      show_cmd "dpkg -i ${debs[*]}"
      dpkg -i "${debs[@]}" 2>/dev/null || true
      dpkg --configure -a 2>/dev/null || true
      apt-get install -f -y -qq 2>/dev/null || true
      command -v mariadb &>/dev/null && client="mariadb"
      [[ -z "$client" ]] && command -v mysql &>/dev/null && client="mysql"
    fi
  fi

  if [[ -n "$client" ]]; then
    ok "Cliente encontrado: $(command -v "$client")"

    step "5/5 — Autenticacion + SELECT 1"
    # --ssl-verify-server-cert=0: servidores internos sin SSL/con cert propio.
    # No verificamos el cert del server (equivale al -C de sqlcmd).
    echo "  Conectando y ejecutando un query de prueba con:"
    show_cmd "$client -h $CONN_SERVER -P $CONN_PORT -u$CONN_USER -p$CONN_PASS --ssl-verify-server-cert=0 $CONN_DB -e \"SELECT 1\""
    if out="$("$client" -h "$CONN_SERVER" -P "$CONN_PORT" -u"$CONN_USER" -p"$CONN_PASS" --ssl-verify-server-cert=0 "$CONN_DB" -e "SELECT 1" 2>&1)"; then
      ok "AUTH OK — login y SELECT 1 exitosos sobre db=$CONN_DB."
    else
      err "AUTH FALLO — el cliente no pudo completar el query."
      err "    Salida: $out"
      fail
    fi
  else
    err "Cliente mariadb/mysql NO disponible y no hay .deb en assets/database/."
    err "    bash $DEPLOY_DIR/setup/bootstrap.sh   (o: apt-get install -y mariadb-client)"
    fail
  fi
fi

# ── RESULTADO + SUGERENCIAS ─────────────────────────────────────────────────

echo ""
divider
if [[ $FAILED -eq 0 ]]; then
  echo "  RESULTADO: TODO OK ✓"
  divider
  ok "Las 5 capas pasaron. El servidor puede comunicarse con la BD."
  echo ""
  exit 0
fi

echo "  RESULTADO: $FAILED capa(s) con problema ✗"
divider
echo ""
step "Que validar / comandos sugeridos"

if $PROVIDER_IS_SQLSERVER; then
  cat <<EOF
  SQL SERVER:
    1. Reproducir la conexion a mano (si funciona, el problema es del script):
         sqlcmd -C -S $CONN_SERVER,$CONN_PORT -U $CONN_USER -P '<password>' -d $CONN_DB -Q "SELECT 1"
    2. Ver si el puerto responde:
         timeout 5 bash -c 'echo > /dev/tcp/$CONN_SERVER/$CONN_PORT' && echo abierto
    3. En el servidor SQL: que TCP/IP este habilitado (SQL Server Configuration Manager)
       y que el puerto $CONN_PORT coincida.
    4. Firewall del server de BD: permitir entrada al puerto $CONN_PORT.
    5. El login $CONN_USER debe ser SQL auth (no solo Windows) y tener acceso a $CONN_DB.
EOF
else
  cat <<EOF
  MARIADB:
    1. Reproducir la conexion a mano (te pide la password, no la pongas en el comando):
         $([[ -n "${client:-}" ]] && echo "$client" || echo mariadb) -h $CONN_SERVER -P $CONN_PORT -u $CONN_USER -p --ssl-verify-server-cert=0 -e "SELECT 1"
    2. Ver si el puerto responde:
         timeout 5 bash -c 'echo > /dev/tcp/$CONN_SERVER/$CONN_PORT' && echo abierto
    3. OJO: el puerto por defecto aca es $CONN_PORT (no el 3306 estandar). Confirmar el real.
    4. En el server MariaDB: bind-address debe permitir conexiones remotas (no 127.0.0.1)
         grep -R bind-address /etc/mysql/
    5. El usuario debe existir para tu host de origen:
         SELECT user, host FROM mysql.user WHERE user = '$CONN_USER';
       y tener GRANT sobre $CONN_DB.
    6. Firewall del server de BD: permitir entrada al puerto $CONN_PORT.
EOF
fi

echo ""
exit 1
