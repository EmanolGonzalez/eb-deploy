#!/usr/bin/env bash
set -e
# =============================================================================
# modules/system/commands/rotate-pii.sh — Rotar Hash Key de PII (Blind Indexing)
# =============================================================================
# 1. Genera nueva clave Base64 (openssl rand -base64 32).
# 2. Actualiza PiiEncryption__HashKeyBase64 en config.env.
# 3. Reinicia backend.
# 4. Ejecuta KeyReencryptionJob para Usuario y DeliveryOrder.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../core/logger.sh"
source "$SCRIPT_DIR/../../../core/input.sh"
source "$SCRIPT_DIR/../../../core/config.sh"
source "$SCRIPT_DIR/../../../core/service.sh"

BACKUP_DIR="/app/deploy/storage/backups"
local_ts="$(date +%Y%m%d_%H%M%S)"

# --- Main ---

if ! command -v openssl &>/dev/null; then
  err "openssl no disponible."
  exit 1
fi

load_config

echo
divider
echo "  ROTAR CLAVE DE BUSQUEDA (PII HASH KEY)"
divider
echo
warn "ESTA ACCION ES CRITICA."
warn "Se generara una nueva clave y se re-procesaran todos los hashes de la DB."
warn "Durante el proceso, las busquedas de PII pueden fallar."
echo

menu_select "Confirmar accion:" \
  "Cancelar" \
  "SI, ENTIENDO LOS RIESGOS Y DESEO CONTINUAR"

if [[ "$MENU_SELECTION" != "SI, ENTIENDO LOS RIESGOS Y DESEO CONTINUAR" ]]; then
  log "Operacion cancelada."
  exit 0
fi

# 0. Safety Check: Verificar existencia de KeyReencryptionJob
JOB_DIR="/app/backend/current/KeyReencryptionJob"
if [[ ! -d "$JOB_DIR" ]]; then
  err "No se encontro el directorio $JOB_DIR."
  err "No se puede continuar sin la herramienta de re-encriptacion."
  exit 1
fi

# 0.1 Safety Check: Bloquear rotacion en produccion (SQL Server)
# A menos que se pase el flag --force-prod
load_config
if [[ "$DatabaseProvider" == "SqlServer" && "$1" != "--force-prod" ]]; then
  echo
  divider
  err "BLOQUEO DE SEGURIDAD: SQL SERVER DETECTADO (PRODUCCION)"
  divider
  warn "La rotacion de PII en produccion es una operacion de ALTO IMPACTO."
  warn "Afecta la capacidad de busqueda de todos los registros hasta que el job termine."
  echo
  log "Si realmente desea proceder, ejecute con el comando de sistema:"
  log "sudo bash /app/deploy/modules/system/commands/rotate-pii.sh --force-prod"
  exit 1
fi

if [[ "$DatabaseProvider" == "MariaDB" ]]; then
  ok "Ambiente de TEST (MariaDB) detectado. Procediendo con precauciones estandar."
fi

# 1. Backup config
mkdir -p "$BACKUP_DIR"
cp "$CONFIG_FILE" "$BACKUP_DIR/config.env.pre-pii-rotate.$local_ts"
ok "Backup de configuracion: $BACKUP_DIR/config.env.pre-pii-rotate.$local_ts"

# 2. Generate new Key
new_key=$(openssl rand -base64 32)
update_config_value "PiiEncryption__HashKeyBase64" "$new_key"
ok "Nueva PII Hash Key generada y guardada."

# 3. Restart backend
log "Reiniciando backend para aplicar la nueva clave..."
sudo systemctl restart backend
sleep 2

# 4. Run Re-encryption Job
log "Iniciando re-encriptacion de tablas (KeyReencryptionJob)..."

# Definimos las tablas y propiedades a re-procesar
# Segun EncryptedColumnsExtensions.cs
tables=(
    "Usuario:Email:Email_enc"
    "Usuario:Nombres:Nombres_enc"
    "Usuario:Apellidos:Apellidos_enc"
    "Usuario:Telefono:Telefono_enc"
    "Usuario:Documento:Documento_enc"
    "AuthSession:SsoAccessToken:SsoAccessToken_enc"
    "AuthSession:SsoRefreshToken:SsoRefreshToken_enc"
    "AuthSession:ClientIp:ClientIp_enc"
    "UsuarioSesion:ClientIp:ClientIp_enc"
    "AuditEntry:IpAddress:IpAddress_enc"
    "DeliveryOrder:CitizenNationalId:CitizenNationalId_enc"
    "DeliveryOrder:CitizenSerialNumber:CitizenSerialNumber_enc"
    "DeliveryOrder:DeliveredByDocument:DeliveredByDocument_enc"
    "DeliveryOrder:RequestedByDocument:RequestedByDocument_enc"
    "DeliveryOrder:Address:Address_enc"
    "DeliveryOrderReceiver:Name:Name_enc"
    "DeliveryOrderReceiver:Identification:Identification_enc"
)

cd "$JOB_DIR"

for entry in "${tables[@]}"; do
    IFS=":" read -r table prop col <<< "$entry"
    log "Procesando $table ($prop -> $col)..."
    
    # Ejecutamos el job usando el environment del sistema
    # El job ya carga la configuracion de /app/backend/KeyReencryptionJob/appsettings.json 
    # o de variables de entorno (config.env cargado en el service)
    sudo dotnet run --no-build "$table" --property "$prop" --encrypted-column "$col"
    
    if [[ $? -eq 0 ]]; then
        ok "Completado: $table.$prop"
    else
        err "Fallo al procesar $table.$prop"
        err "Revisar logs: deploy system services -> logs"
    fi
done

echo
divider
ok "Rotacion de PII Hash Key y re-procesamiento completado."
divider
echo
