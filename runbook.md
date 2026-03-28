# eb-deploy - Runbook

> ⚠️ **Importante:**
> `setup-server.sh` solo prepara el entorno (dependencias, azcopy, Nginx, systemd, config.env).
> El despliegue de la aplicacion se hace siempre con `install.sh`, una ejecucion por componente.

Este runbook describe el paso a paso para preparar el entorno y operar los scripts de despliegue, actualizacion y rollback.

---

## Arquitectura del sistema

### Scripts y responsabilidades

| Script | Proposito |
|---|---|
| `ops-menu.sh` | Consola de operaciones — entrypoint del sistema en el servidor |
| `setup-server.sh` | Aprovisionamiento inicial: instala dependencias, crea config.env |
| `install.sh` | Instala un componente desde Azure (seleccion de version) |
| `update.sh` | Actualiza un componente con auto-rollback si el healthcheck falla |
| `rollback.sh` | Restaura un componente a una version instalada localmente |
| `release.sh` | Sube un nuevo artifact a Azure (se ejecuta desde dev/CI, no el servidor) |
| `healthcheck.sh` | Valida que backend/frontend esten operativos |
| `status.sh` | Reporte de estado completo del sistema |
| `set-db-connection.sh` | Configura la cadena de conexion de base de datos |
| `set-health-endpoint.sh` | Configura el endpoint de healthcheck del backend |
| `set-scripts-url.sh` | Configura la URL base de GitHub para actualizar scripts |
| `configure-internal-https.sh` | Configura HTTPS interno en Nginx para subdominio |
| `uninstall.sh` | Elimina la aplicacion desplegada (preserva evidencias) |
| `fetch-all.sh` | Descargador efimero de scripts — **nunca queda en disco** |

### Directorio en el servidor

```
/app/
├── config/
│   └── config.env              # Toda la configuracion centralizada (chmod 600)
├── scripts/                    # Scripts de operaciones
│   ├── ops-menu.sh             # Entrypoint
│   └── ...
├── releases/
│   ├── frontend/<version>/     # Artifacts extraidos
│   └── backend/<version>/
├── frontend/
│   └── current -> /app/releases/frontend/<version>   # Symlink activo
└── backend/
    └── current -> /app/releases/backend/<version>    # Symlink activo
```

### Estructura de blobs en Azure

```
<container>/
├── frontend/
│   ├── 1.0.0/
│   │   └── app.rar
│   └── 1.0.1/
│       └── app.rar
└── backend/
    ├── 1.0.0/
    │   └── app.rar
    └── 1.0.1/
        └── app.rar
```

### Configuracion centralizada: config.env

Todos los valores de configuracion y secretos residen en un unico archivo `/app/config/config.env` con permisos `600`. No existen archivos `.txt` separados.

```bash
CONFIG_VERSION="1"

# --- CRITICAS (obligatorias) ---
STORAGE_ACCOUNT="mi-cuenta"
CONTAINER_NAME="mi-contenedor"
BASE_URL="https://mi-cuenta.blob.core.windows.net/mi-contenedor"

# --- SCRIPTS ---
SCRIPTS_BASE_URL="https://raw.githubusercontent.com/usuario/repo/main"

# --- OPCIONALES ---
NGINX_SERVER_NAME="app.dominio.com"
BACKEND_HEALTH_ENDPOINT="http://localhost:5000/api/health"

# --- SECRETAS ---
DB_CONNECTION_STRING="Server=...;Database=...;User ID=...;Password=...;"
```

### Seguridad del SAS token

> 🔒 **El SAS token nunca se guarda en disco — ni en `config.env` ni en ningun archivo.**

El SAS token de Azure es la credencial de acceso a los artifacts en Blob Storage. Por diseno:

- Se solicita de forma interactiva (input oculto) **en cada operacion** que lo requiere: `install.sh`, `update.sh`, `release.sh`
- Existe unicamente en memoria durante la ejecucion del script
- Se descarta automaticamente al terminar
- Nunca aparece en logs del sistema

Esto es intencional: un SAS comprometido tiene alcance limitado al tiempo de vida del token. Si estuviera almacenado en disco, cualquier acceso al servidor implicaria acceso permanente al storage.

---

## Prerrequisitos de infraestructura (responsabilidad del administrador)

Antes de ejecutar cualquier script en el servidor, el administrador de infraestructura debe garantizar lo siguiente a nivel de red y virtualizacion.

### Puertos requeridos

| Puerto | Protocolo | Uso | Requerido por |
|---|---|---|---|
| 22 | TCP | SSH — acceso remoto al servidor | Administracion |
| 80 | TCP | HTTP — frontend y proxy al backend | Nginx |
| 443 | TCP | HTTPS — si se configura TLS interno | `configure-internal-https.sh` |

Estos puertos deben estar habilitados tanto en el **virtualizador** (VMware, Hyper-V, Proxmox, etc.) como en cualquier firewall de red intermedio.

> ⚠️ **El puerto 22 (SSH) nunca debe bloquearse.** Sin SSH no hay forma de acceder al servidor para operar o corregir problemas. Si se aplica alguna regla de firewall en el SO (`ufw`, `iptables`), asegurarse de que SSH este explicitamente permitido **antes** de activar cualquier regla restrictiva.

### Firewall del SO (ufw)

En Debian/Ubuntu, `ufw` viene **inactivo por defecto**. Los scripts de deploy no lo modifican — eso queda bajo responsabilidad del administrador. Si se decide activarlo, los puertos minimos a permitir son:

```bash
ufw allow 22/tcp    # SSH — obligatorio, siempre primero
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS (si aplica)
ufw enable
```

> ⚠️ Nunca ejecutar `ufw enable` sin haber permitido el puerto 22 primero. Hacerlo bloquea la sesion SSH activa y deja el servidor inaccesible remotamente.

---

## Prerrequisito: hosts (entornos cerrados)

En entornos sin DNS interno, agrega los aliases necesarios antes del despliegue.

Linux:
```bash
sudo nano /etc/hosts
```

Windows:
```
C:\Windows\System32\drivers\etc\hosts
```

Ejemplo:
```
10.10.10.10  test-esb.tribunal-electoral.gob.pa
10.10.10.11  esb.tribunal-electoral.gob.pa
10.10.10.12  bussec.tribunal-electoral.gob.pa
10.10.10.13  buste.tribunal-electoral.gob.pa
10.10.10.20  sql.entrega.local
```

---

## Preparacion del entorno (primera vez)

### Paso 1 — Descargar el entrypoint

```bash
mkdir -p /app/scripts
cd /app/scripts
wget -O ops-menu.sh https://raw.githubusercontent.com/<usuario>/<repo>/main/ops-menu.sh
chmod +x ops-menu.sh
```

### Paso 2 — Traer todos los scripts

```bash
bash ops-menu.sh
```

Selecciona **Actualizar scripts**. Como aun no hay `config.env`, pedira la URL base raw de GitHub. Introducila. `fetch-all.sh` se descarga de forma temporal, trae todos los scripts al directorio actual y se elimina automaticamente.

### Paso 3 — Configurar el servidor

```bash
bash setup-server.sh
```

El setup instala y configura:
- Node.js 20 LTS
- .NET 9 SDK
- **azcopy** (herramienta estandar para Azure Blob Storage)
- Nginx + virtual host de la app
- Servicio systemd `backend`

Al terminar, crea `/app/config/config.env` con todos los valores configurados interactivamente (Azure Storage Account, Container, URL de scripts). Si existian archivos de configuracion heredados (`storage.conf`, `db-connection.txt`, etc.), los migra automaticamente a `config.env`.

A partir de este momento, **Actualizar scripts** usara `SCRIPTS_BASE_URL` guardada y preguntara si deseas usarla o ingresar otra.

### Paso 4 — Instalar la aplicacion

```bash
bash install.sh   # selecciona frontend, luego SAS token y version
bash install.sh   # selecciona backend, luego SAS token, version y cadena de conexion BD
```

El SAS token se ingresa de forma interactiva en cada ejecucion (input oculto). Nunca se almacena.

---

## Publicar una nueva version (release)

`release.sh` se ejecuta desde la **maquina de desarrollo o CI**, no desde el servidor.

```bash
bash release.sh
```

El script:
1. Valida que `curl` este disponible (incluido con Git for Windows)
2. Solicita la cuenta de Azure Storage y el nombre del contenedor
3. Solicita el SAS token de forma interactiva (input oculto, nunca se almacena)
4. Detecta la ultima version subida via Azure Blob REST API y calcula la siguiente automaticamente (semver patch)
5. Ofrece dos opciones para el artifact:
   - **Build automatico**: compila/publica el componente localmente con `npm run build` (frontend) o `dotnet publish` (backend), empaqueta el resultado en `app.rar` con WinRAR y lo sube
   - **Manual**: pide la ruta a un `app.rar` ya construido
6. Muestra un resumen y solicita confirmacion
7. Sube el artifact a Azure via REST API (PUT Blob): `<componente>/<version>/app.rar`

> **Nota:** `release.sh` usa `curl` + Azure Blob REST API (no `azcopy`). Esto es intencional: se ejecuta desde maquinas Windows de desarrollo donde `azcopy` no esta instalado. Los scripts del servidor (`install.sh`, `update.sh`) si usan `azcopy`.

---

## Operaciones de mantenimiento

### Consola de operaciones

```bash
bash ops-menu.sh
```

Todas las operaciones del servidor estan disponibles desde el menu.

### Actualizacion de scripts

Desde el menu → **Actualizar scripts**.

Si `SCRIPTS_BASE_URL` esta configurada, mostrara la URL guardada y preguntara si deseas usarla o ingresar otra. `fetch-all.sh` se ejecuta de forma efimera (temporal, se elimina automaticamente) y actualiza todos los scripts en `/app/scripts/`.

### Instalar una version

```bash
bash install.sh
# Prompts: SAS token (oculto) → componente → version
# Backend ademas: cadena de conexion BD
```

### Actualizar a una version mas nueva

```bash
bash update.sh
# Prompts: SAS token (oculto) → componente → version mas nueva disponible
```

`update.sh` guarda la version anterior antes de actualizar. Al finalizar, ejecuta un **healthcheck estricto**. Si el healthcheck falla, realiza **rollback automatico** a la version anterior y ejecuta un healthcheck suave para confirmar la restauracion.

### Rollback manual

```bash
bash rollback.sh
# Prompts: componente → version local disponible
```

Opera completamente en local — no requiere Azure ni SAS token. Ejecuta healthcheck en modo suave (`--soft`) al finalizar. Tambien puede invocarse con argumentos:

```bash
bash rollback.sh --component backend --version 1.2.3
```

### Uninstall (preservando evidencias)

```bash
bash uninstall.sh
```

Elimina el despliegue, el sitio Nginx de la app, el servicio backend y `config.env`. Preserva `/app/evidence` y `/app/evidences`.

### Healthcheck

```bash
bash healthcheck.sh backend          # estricto — sale con error si falla
bash healthcheck.sh frontend         # verifica symlink y archivo index.html
bash healthcheck.sh backend --soft   # informativo — nunca bloquea
```

El healthcheck de backend verifica en orden:
1. Servicio systemd `backend` activo
2. Puerto escuchando (detectado de `appsettings.json` o default 5000)
3. HTTP 200 en `/api/health`, `/health` o `/healthz`

### Estado del sistema

```bash
bash status.sh          # texto legible
bash status.sh --json   # JSON para automatizacion/monitoreo
```

Verifica versiones instaladas, symlinks, Nginx, servicio backend, puerto y endpoint de salud.

---

## Configuracion persistente

Todos los valores se guardan en `/app/config/config.env`. Los scripts `set-*` actualizan la clave correspondiente sin tocar el resto del archivo.

### Cadena de conexion de base de datos

```bash
bash set-db-connection.sh
```

- Solicita la nueva cadena (input oculto)
- Guarda `DB_CONNECTION_STRING` en `config.env`
- Si hay un backend desplegado, aplica la cadena en `appsettings.json` y ofrece reiniciar el servicio
- `install.sh`, `update.sh` y `rollback.sh` preguntan en backend si deseas usar la cadena guardada o ingresar otra
- En cada deploy de backend, la cadena se aplica automaticamente en `appsettings.json` (`appsettings.Development.json` no se toca)

### Endpoint de healthcheck del backend

```bash
bash set-health-endpoint.sh
```

- Guarda `BACKEND_HEALTH_ENDPOINT` en `config.env`
- `status.sh` usa este endpoint como URL preferida para validar el backend
- Al guardar, realiza una validacion inmediata (HTTP 200)

### URL de scripts de GitHub

```bash
bash set-scripts-url.sh
```

- Guarda `SCRIPTS_BASE_URL` en `config.env`
- A partir de ese momento, **Actualizar scripts** muestra la URL guardada y pregunta si usarla o ingresar otra
- Util para cambiar de rama (`main` → `dev`) sin editar el archivo manualmente

### HTTPS interno

```bash
bash configure-internal-https.sh
```

Crea o actualiza el virtual host Nginx para subdominio interno con certificado TLS y proxy `/api` al backend.

---

## Variables de entorno (sin persistencia en disco)

Estas variables se leen en tiempo de ejecucion y **nunca se escriben a ningun archivo**.

| Variable | Usada en | Descripcion |
|---|---|---|
| `AZURE_SAS_TOKEN` | `install.sh`, `update.sh`, `release.sh` | Solo para pipelines CI/CD. Nunca exportar en sesiones interactivas ni guardar en archivos. En operaciones manuales el SAS siempre se ingresa de forma interactiva. |
| `HEALTHCHECK_RETRIES` | `healthcheck.sh` | Intentos maximos antes de fallar (default: 20) |
| `HEALTHCHECK_SLEEP_SECONDS` | `healthcheck.sh` | Segundos entre intentos (default: 3) |
| `APP_PORT` | `healthcheck.sh` | Override del puerto a verificar |
| `BACKEND_PORTS` | `healthcheck.sh` | Lista de puertos candidatos separados por coma |

> ⚠️ `AZURE_SAS_TOKEN` existe unicamente para automatizacion. En el servidor, el SAS se ingresa manualmente en cada operacion y se descarta al terminar.

---

## Operacion de servicios y logs

```bash
# Estado
systemctl status nginx
systemctl status backend

# Reinicio
systemctl restart nginx
systemctl restart backend

# Logs en vivo
journalctl -u backend -f
journalctl -u nginx -f

# Ultimas lineas
journalctl -u backend -n 50
journalctl -u nginx -n 50
```

---

## Flujo completo de referencia

```
[Dev / CI]                          [Servidor]

release.sh                          mkdir /app/scripts
  ├── curl REST API (versiones)      wget ops-menu.sh
  ├── incrementa semver              bash ops-menu.sh → Actualizar scripts
  ├── build local (npm/dotnet)         └── fetch-all efimero → descarga todos los scripts
  ├── WinRAR → app.rar
  └── curl PUT Blob (sube app.rar)
                                     bash setup-server.sh
                                       ├── instala Node, .NET, azcopy, Nginx, systemd
                                       └── crea /app/config/config.env
                                     bash install.sh (frontend)
                                     bash install.sh (backend)
                                          ├── azcopy list → versiones disponibles
                                          ├── azcopy copy → descarga app.rar
                                          ├── unrar → /app/releases/<componente>/<version>/
                                          ├── ln -sfn → current
                                          └── systemctl restart backend

                                     [Mantenimiento futuro via ops-menu.sh]
                                     Update
                                       ├── azcopy list → versiones mas nuevas
                                       ├── azcopy copy → descarga
                                       ├── deploy + restart
                                       ├── healthcheck estricto
                                       └── [fallo] → rollback automatico

                                     Rollback
                                       ├── lista versiones locales
                                       ├── ln -sfn → version anterior
                                       └── healthcheck soft
```
