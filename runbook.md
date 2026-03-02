# Runbook — eb-deploy

> ⚠️ **Importante:**
> `setup-server.sh` solo prepara el entorno (dependencias, azcopy, Nginx, systemd, config.env).
> El despliegue de la aplicación se hace siempre con `install.sh`, una ejecución por componente.

Este runbook describe el paso a paso para preparar el entorno y operar los scripts de despliegue, actualización y rollback.

---

## Arquitectura del sistema

### Scripts y responsabilidades

| Script | Propósito |
|---|---|
| `ops-menu.sh` | Consola de operaciones — entrypoint del sistema en el servidor |
| `setup-server.sh` | Aprovisionamiento inicial: instala dependencias, crea config.env |
| `install.sh` | Instala un componente desde Azure (selección de versión) |
| `update.sh` | Actualiza un componente con auto-rollback si el healthcheck falla |
| `rollback.sh` | Restaura un componente a una versión instalada localmente |
| `release.sh` | Sube un nuevo artifact a Azure (se ejecuta desde dev/CI, no el servidor) |
| `healthcheck.sh` | Valida que backend/frontend estén operativos |
| `status.sh` | Reporte de estado completo del sistema |
| `set-db-connection.sh` | Configura la cadena de conexión de base de datos |
| `set-health-endpoint.sh` | Configura el endpoint de healthcheck del backend |
| `set-scripts-url.sh` | Configura la URL base de GitHub para actualizar scripts |
| `configure-internal-https.sh` | Configura HTTPS interno en Nginx para subdominio |
| `uninstall.sh` | Elimina la aplicación desplegada (preserva evidencias) |
| `fetch-all.sh` | Descargador efímero de scripts — **nunca queda en disco** |

### Directorio en el servidor

```
/app/
├── config/
│   └── config.env              # Toda la configuración centralizada (chmod 600)
├── scripts/                    # Scripts de operaciones
│   ├── ops-menu.sh             # Entrypoint
│   └── ...
├── releases/
│   ├── frontend/<version>/     # Artifacts extraídos
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

### Configuración centralizada: config.env

Todos los valores de configuración y secretos residen en un único archivo `/app/config/config.env` con permisos `600`. No existen archivos `.txt` separados.

```bash
CONFIG_VERSION="1"

# --- CRÍTICAS (obligatorias) ---
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

> 🔒 **El SAS token nunca se guarda en disco — ni en `config.env` ni en ningún archivo.**

El SAS token de Azure es la credencial de acceso a los artifacts en Blob Storage. Por diseño:

- Se solicita de forma interactiva (input oculto) **en cada operación** que lo requiere: `install.sh`, `update.sh`, `release.sh`
- Existe únicamente en memoria durante la ejecución del script
- Se descarta automáticamente al terminar
- Nunca aparece en logs del sistema

Esto es intencional: un SAS comprometido tiene alcance limitado al tiempo de vida del token. Si estuviera almacenado en disco, cualquier acceso al servidor implicaría acceso permanente al storage.

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

## Preparación del entorno (primera vez)

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

Selecciona **Actualizar scripts**. Como aún no hay `config.env`, pedirá la URL base raw de GitHub. Introdúcela. `fetch-all.sh` se descarga de forma temporal, trae todos los scripts al directorio actual y se elimina automáticamente.

### Paso 3 — Configurar el servidor

```bash
bash setup-server.sh
```

El setup instala y configura:
- Node.js 20 LTS
- .NET 9 SDK
- **azcopy** (herramienta estándar para Azure Blob Storage)
- Nginx + virtual host de la app
- Servicio systemd `backend`

Al terminar, crea `/app/config/config.env` con todos los valores configurados interactivamente (Azure Storage Account, Container, URL de scripts). Si existían archivos de configuración heredados (`storage.conf`, `db-connection.txt`, etc.), los migra automáticamente a `config.env`.

A partir de este momento, **Actualizar scripts** usará `SCRIPTS_BASE_URL` guardada y preguntará si deseas usarla o ingresar otra.

### Paso 4 — Instalar la aplicación

```bash
bash install.sh   # selecciona frontend, luego SAS token y versión
bash install.sh   # selecciona backend, luego SAS token, versión y cadena de conexión BD
```

El SAS token se ingresa de forma interactiva en cada ejecución (input oculto). Nunca se almacena.

---

## Publicar una nueva versión (release)

`release.sh` se ejecuta desde la **máquina de desarrollo o CI**, no desde el servidor.

```bash
bash release.sh
```

El script:
1. Valida que `curl` esté disponible (incluido con Git for Windows)
2. Solicita la cuenta de Azure Storage y el nombre del contenedor
3. Solicita el SAS token de forma interactiva (input oculto, nunca se almacena)
4. Detecta la última versión subida vía Azure Blob REST API y calcula la siguiente automáticamente (semver patch)
5. Ofrece dos opciones para el artifact:
   - **Build automático**: compila/publica el componente localmente con `npm run build` (frontend) o `dotnet publish` (backend), empaqueta el resultado en `app.rar` con WinRAR y lo sube
   - **Manual**: pide la ruta a un `app.rar` ya construido
6. Muestra un resumen y solicita confirmación
7. Sube el artifact a Azure via REST API (PUT Blob): `<componente>/<version>/app.rar`

> **Nota:** `release.sh` usa `curl` + Azure Blob REST API (no `azcopy`). Esto es intencional: se ejecuta desde máquinas Windows de desarrollo donde `azcopy` no está instalado. Los scripts del servidor (`install.sh`, `update.sh`) sí usan `azcopy`.

---

## Operaciones de mantenimiento

### Consola de operaciones

```bash
bash ops-menu.sh
```

Todas las operaciones del servidor están disponibles desde el menú.

### Actualización de scripts

Desde el menú → **Actualizar scripts**.

Si `SCRIPTS_BASE_URL` está configurada, mostrará la URL guardada y preguntará si deseas usarla o ingresar otra. `fetch-all.sh` se ejecuta de forma efímera (temporal, se elimina automáticamente) y actualiza todos los scripts en `/app/scripts/`.

### Instalar una versión

```bash
bash install.sh
# Prompts: SAS token (oculto) → componente → versión
# Backend además: cadena de conexión BD
```

### Actualizar a una versión más nueva

```bash
bash update.sh
# Prompts: SAS token (oculto) → componente → versión más nueva disponible
```

`update.sh` guarda la versión anterior antes de actualizar. Al finalizar, ejecuta un **healthcheck estricto**. Si el healthcheck falla, realiza **rollback automático** a la versión anterior y ejecuta un healthcheck suave para confirmar la restauración.

### Rollback manual

```bash
bash rollback.sh
# Prompts: componente → versión local disponible
```

Opera completamente en local — no requiere Azure ni SAS token. Ejecuta healthcheck en modo suave (`--soft`) al finalizar. También puede invocarse con argumentos:

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
bash status.sh --json   # JSON para automatización/monitoreo
```

Verifica versiones instaladas, symlinks, Nginx, servicio backend, puerto y endpoint de salud.

---

## Configuración persistente

Todos los valores se guardan en `/app/config/config.env`. Los scripts `set-*` actualizan la clave correspondiente sin tocar el resto del archivo.

### Cadena de conexión de base de datos

```bash
bash set-db-connection.sh
```

- Solicita la nueva cadena (input oculto)
- Guarda `DB_CONNECTION_STRING` en `config.env`
- Si hay un backend desplegado, aplica la cadena en `appsettings.json` y ofrece reiniciar el servicio
- `install.sh`, `update.sh` y `rollback.sh` preguntan en backend si deseas usar la cadena guardada o ingresar otra
- En cada deploy de backend, la cadena se aplica automáticamente en `appsettings.json` (`appsettings.Development.json` no se toca)

### Endpoint de healthcheck del backend

```bash
bash set-health-endpoint.sh
```

- Guarda `BACKEND_HEALTH_ENDPOINT` en `config.env`
- `status.sh` usa este endpoint como URL preferida para validar el backend
- Al guardar, realiza una validación inmediata (HTTP 200)

### URL de scripts de GitHub

```bash
bash set-scripts-url.sh
```

- Guarda `SCRIPTS_BASE_URL` en `config.env`
- A partir de ese momento, **Actualizar scripts** muestra la URL guardada y pregunta si usarla o ingresar otra
- Útil para cambiar de rama (`main` → `dev`) sin editar el archivo manualmente

### HTTPS interno

```bash
bash configure-internal-https.sh
```

Crea o actualiza el virtual host Nginx para subdominio interno con certificado TLS y proxy `/api` al backend.

---

## Variables de entorno (sin persistencia en disco)

Estas variables se leen en tiempo de ejecución y **nunca se escriben a ningún archivo**.

| Variable | Usada en | Descripción |
|---|---|---|
| `AZURE_SAS_TOKEN` | `install.sh`, `update.sh`, `release.sh` | Solo para pipelines CI/CD. Nunca exportar en sesiones interactivas ni guardar en archivos. En operaciones manuales el SAS siempre se ingresa de forma interactiva. |
| `HEALTHCHECK_RETRIES` | `healthcheck.sh` | Intentos máximos antes de fallar (default: 20) |
| `HEALTHCHECK_SLEEP_SECONDS` | `healthcheck.sh` | Segundos entre intentos (default: 3) |
| `APP_PORT` | `healthcheck.sh` | Override del puerto a verificar |
| `BACKEND_PORTS` | `healthcheck.sh` | Lista de puertos candidatos separados por coma |

> ⚠️ `AZURE_SAS_TOKEN` existe únicamente para automatización. En el servidor, el SAS se ingresa manualmente en cada operación y se descarta al terminar.

---

## Operación de servicios y logs

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

# Últimas líneas
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
  ├── build local (npm/dotnet)         └── fetch-all efímero → descarga todos los scripts
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

                                     [Mantenimiento futuro vía ops-menu.sh]
                                     Update
                                       ├── azcopy list → versiones más nuevas
                                       ├── azcopy copy → descarga
                                       ├── deploy + restart
                                       ├── healthcheck estricto
                                       └── [fallo] → rollback automático

                                     Rollback
                                       ├── lista versiones locales
                                       ├── ln -sfn → versión anterior
                                       └── healthcheck soft
```
