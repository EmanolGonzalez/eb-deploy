# eb-deploy - Runbook

> ⚠️ **Importante:**
> `setup/setup-server.sh` solo prepara el entorno (dependencias, Nginx, systemd, config.env).
> El despliegue de la aplicacion se hace siempre con `install.sh`, una ejecucion por componente.

Este runbook describe el paso a paso para preparar el entorno y operar los scripts de despliegue, actualizacion y rollback.

---

## ✅ Checklist de primer deploy (servidores internos sin SSL)

Seguilo en orden. Pensado para que funcione **a la primera**.

### FASE 0 — En la maquina de dev (antes de buildear)

Las `VITE_*` se **hornean** en `npm run build`, NO se leen en runtime. Si las cambias hay que recompilar.

- [ ] `frontend/.env` (guia en `frontend/.env.example`):
  ```ini
  VITE_API_BASE_URL=/api
  VITE_HUB_BASE_URL=/      # NO "/hub": el codigo agrega /hubs/<nombre> solo
  VITE_CSP_API_URL=https://<dominio-o-ip-interna>
  VITE_CSP_WS_URL=wss://<dominio-o-ip-interna>
  ```
- [ ] `deploy release build` (frontend) → corre lint + `npm run build` + `app.rar`.
- [ ] `grep -o '"/api"' frontend/dist/assets/index-*.js` → debe imprimir `"/api"`.

### FASE 1 — Llevar al server (offline)

- [ ] Copiar `bs_deploy/` completo (con `assets/*.deb`) a `/app/deploy`.
- [ ] `app.rar` frontend → `/app/artifacts/frontend.rar`; backend → `/app/artifacts/backend.rar`.
- [ ] `deploy system lint` → **verde** (sintaxis, `local`, SSL). Si falla, NO sigas.

### FASE 2 — Setup

- [ ] `sudo bash /app/deploy/setup/setup-server.sh` (bootstrap offline + nginx + systemd + config.env + CLI).
- [ ] `command -v sqlcmd && command -v mariadb` → ambos presentes.

### FASE 3 — config.env (`deploy system edit-config`)

- [ ] `DB_PROVIDER` coincide con la cadena que llenas.
- [ ] **SQL Server interno:** `...;TrustServerCertificate=True;Encrypt=False;` y `User ID=` (NO `Trusted_Connection`).
- [ ] **MariaDB interno:** `...;SslMode=Preferred;AllowPublicKeyRetrieval=False;` (NUNCA `Required`/`VerifyCA`/`VerifyFull`).
- [ ] `FrontendProdUrl` = origen EXACTO del front, **sin barra final** (CORS con credenciales).
- [ ] `Authentication__Authority` + `Audience`. Si el IdP es **HTTP interno**: descomentar `Authentication__RequireHttpsMetadata="false"`.
- [ ] `PiiEncryption__HashKeyBase64` = la MISMA con la que se cifraron los datos.
- [ ] Al guardar, `edit-config` **no muestra warnings SSL** en amarillo.

### FASE 4 — Verificar BD

- [ ] `deploy database check` → 5 capas (DNS → puerto → cliente → SELECT 1) → **TODO OK ✓**.

### FASE 5 — Desplegar

- [ ] `deploy backend install` → reinicia `backend.service`.
- [ ] `deploy frontend install`.
- [ ] `deploy health full` → backend activo, puerto 5000, `/api/health` 200, nginx up.

### FASE 6 — Verificar nginx, `/api` y `/hubs`

Hubs del backend (todos bajo `/hubs/`, cubiertos por `location /hubs`):
`/hubs/health` · `/hubs/observability` · `/hubs/live-sessions` · `/hubs/user-setup`.

- [ ] `sudo nginx -t && sudo systemctl reload nginx`
- [ ] `curl -i http://localhost/api/health` → 200 **JSON** (si devuelve `text/html`, `/api` no matchea → cae al SPA).
- [ ] `curl -i "http://localhost/hubs/health?id=test"` → respuesta de SignalR, **NO** el index.html.
- [ ] WebSocket upgrade:
  ```bash
  curl -i -H "Connection: Upgrade" -H "Upgrade: websocket" \
       -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: x" \
       "http://localhost/hubs/health"   # esperas 101, no 200 text/html
  ```
- [ ] Browser → F12 → Network → **Ctrl+Shift+R**: API va a `/api/...`, WS conecta a `/hubs/...` (101/abierto), carga el JS nuevo.

### 🔴 Los 5 que rompen "la primera vez"

| # | Trampa | Sintoma | Fix |
|---|--------|---------|-----|
| 1 | `.env` sin `VITE_API_BASE_URL` al buildear | llamadas sin `/api` | rebuildeear |
| 2 | `VITE_HUB_BASE_URL=/hub` | WS falla (`/hub/hubs/...`) | poner `/` |
| 3 | SQL sin `TrustServerCertificate=True` | backend no arranca (TLS) | agregarlo |
| 4 | `index.html` cacheado | bundle viejo persiste | `no-cache` (ya esta) + Ctrl+Shift+R |
| 5 | redeploy sin redeployar `bs_deploy` | error `local` viejo | copiar `bs_deploy` actual a `/app/deploy` |

---

## Arquitectura del sistema

### Scripts y responsabilidades

| Script | Proposito |
|---|---|
| `ops-menu.sh` | Consola de operaciones — entrypoint del sistema en el servidor |
| `setup/setup-server.sh` | Aprovisionamiento inicial: instala dependencias, crea config.env |
| `install.sh` | Instala un componente desde un archivo app.rar local |
| `update.sh` | Actualiza un componente con auto-rollback si el healthcheck | set-developer | run-schema | reset-schemafalla |
| `rollback.sh` | Restaura un componente a una version instalada localmente |
| `release.sh` | Construye y empaqueta un componente en app.rar (se ejecuta desde dev) |
| `healthcheck.sh` | Valida que backend/frontend esten operativos |
| `status.sh` | Reporte de estado completo del sistema |
| `set-db-connection.sh` | Configura la cadena de conexion de base de datos |
| `set-health-endpoint.sh` | Configura el endpoint de healthcheck del backend |
| `configure-internal-https.sh` | Configura HTTPS interno en Nginx para subdominio |
| `uninstall.sh` | Elimina la aplicacion desplegada (preserva evidencias) |

### Directorio en el servidor

```
/app/
├── config/
│   └── config.env              # Toda la configuracion centralizada (chmod 600)
├── deploy/                     # Sistema de deploy completo
│   ├── bin/                    # Entry points (deploy CLI, menu)
│   ├── core/                   # Utilidades reutilizables
│   ├── modules/                # Modulos (deploy, health, database, nginx, etc.)
│   ├── assets/                 # Dependencias offline (dotnet, node, tools)
│   ├── ops-menu.sh             # Menu de operaciones (legacy)
│   └── ...
├── releases/
│   ├── frontend/<version>/     # Artifacts extraidos
│   └── backend/<version>/
├── frontend/
│   └── current -> /app/releases/frontend/<version>   # Symlink activo
└── backend/
    └── current -> /app/releases/backend/<version>    # Symlink activo
```

### Configuracion centralizada: config.env

Todos los valores de configuracion y secretos residen en un unico archivo `/app/config/config.env` con permisos `600`.

```bash
CONFIG_VERSION="4"

# --- OPCIONALES ---
NGINX_SERVER_NAME="app.dominio.com"
BACKEND_HEALTH_ENDPOINT="http://localhost:5000/api/health"

# --- DATABASE ---
DB_PROVIDER="SqlServer"
ConnectionStrings__SqlServer="Server=...;Database=...;User ID=...;Password=...;"
ConnectionStrings__MariaDB="Server=...;Database=...;User=...;Password=...;"
```

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

### Paso 1 — Copiar el sistema de deploy al servidor

Copia toda la carpeta `deploy/` al servidor (SCP, USB, etc.):

```bash
scp -r deploy/ user@servidor:/tmp/deploy
ssh user@servidor "sudo cp -r /tmp/deploy /app/deploy && sudo chmod +x /app/deploy/*.sh /app/deploy/bin/* /app/deploy/modules/*/commands/*.sh"
```

### Paso 2 — Bootstrap (instalacion offline de dependencias)

```bash
sudo bash /app/deploy/setup/bootstrap.sh
```

Esto instala desde `assets/` (sin internet):
- Node.js 22.x
- .NET 9 SDK
- rar/unrar
- Paquetes del sistema (curl, git, wget, tar)

Si algun asset falta y hay internet, intenta descargarlo automaticamente.

### Paso 3 — Configurar el servidor

```bash
sudo bash /app/deploy/setup/setup-server.sh
```

El setup configura:
- Nginx + virtual host de la app
- Servicio systemd `backend`
- `/app/config/config.env` con valores configurados interactivamente

Si existian archivos de configuracion heredados (`db-connection.txt`, etc.), los migra automaticamente a `config.env`.

### Paso 4 — Instalar la aplicacion

Desde tu maquina de desarrollo, construi el artifact:

```bash
bash release.sh   # selecciona componente y version → genera app.rar
```

Copia el `app.rar` al servidor:

```bash
scp app.rar user@servidor:/tmp/
```

En el servidor, instala:

```bash
bash install.sh   # selecciona componente, ruta al app.rar y version
```

Para el backend, ademas se pedira la cadena de conexion de base de datos.

---

## Publicar una nueva version (release)

`release.sh` se ejecuta desde la **maquina de desarrollo**, no desde el servidor.

```bash
bash release.sh
```

El script:
1. Solicita el componente (frontend o backend)
2. Solicita la version (formato semver X.Y.Z)
3. Construye el componente:
   - **Frontend**: `npm run build` en `frontend/`
   - **Backend**: `dotnet publish` del proyecto API
4. Empaqueta el resultado en `app.rar` usando WinRAR
5. Muestra la ruta del archivo generado

Luego, copia manualmente el `app.rar` al servidor:

```bash
scp app.rar user@servidor:/tmp/
```

---

## Operaciones de mantenimiento

### Consola de operaciones (menu modular)

```bash
bash /app/deploy/bin/menu.sh
```

O via CLI:

```bash
bash /app/deploy/bin/deploy menu
```

El menu modular tiene submenus por dominio:
- **Backend / Frontend** — install, update, rollback
- **App Health** — full, check, status, set-endpoint
- **Database** — check, set-developer, run-schema, reset-schema
- **Nginx** — configure-https, reload
- **System** — setup, edit-config, uninstall, services, rotate-pem, rotate-pii, audit, lint
- **Release** — build

### CLI directa

```bash
bash /app/deploy/bin/deploy backend install
bash /app/deploy/bin/deploy backend update
bash /app/deploy/bin/deploy backend rollback
bash /app/deploy/bin/deploy database check
bash /app/deploy/bin/deploy health status
bash /app/deploy/bin/deploy nginx reload
bash /app/deploy/bin/deploy help
```

### Instalar una version

```bash
bash install.sh
# Prompts: componente → ruta al app.rar → version
# Backend ademas: cadena de conexion BD
```

### Actualizar a una version mas nueva

```bash
bash update.sh
# Prompts: componente → ruta al app.rar → version
```

`update.sh` guarda la version anterior antes de actualizar. Al finalizar, ejecuta un **healthcheck estricto**. Si el healthcheck falla, realiza **rollback automatico** a la version anterior y ejecuta un healthcheck suave para confirmar la restauracion.

### Rollback manual

```bash
bash rollback.sh
# Prompts: componente → version local disponible
```

Opera completamente en local — no requiere archivos externos. Ejecuta healthcheck en modo suave (`--soft`) al finalizar. Tambien puede invocarse con argumentos:

```bash
bash rollback.sh --component backend --version 1.2.3
```

### Uninstall (preservando evidencias)

```bash
bash uninstall.sh
```

Elimina el despliegue, el sitio Nginx de la app, el servicio backend y `config.env`. Preserva `/app/deploy/storage/evidences` (y los legacy `/app/evidence`, `/app/evidences` si quedaron de instalaciones anteriores).

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
deploy system edit-config     # abre config.env en el editor
```

- Editas `DB_PROVIDER` + `ConnectionStrings__SqlServer` o `ConnectionStrings__MariaDB`.
- Al guardar, `edit-config` **revalida SSL** (avisa si falta `TrustServerCertificate=True` o si hay `SslMode` estricto) y **ofrece reiniciar el backend** si ya esta desplegado.
- El backend lee la cadena de `config.env` via systemd `EnvironmentFile` — `appsettings.json` NO se toca (no debe tener secretos).
- Probar la conexion: `deploy database check` (confia en el cert de servers internos).

> **Servers internos sin SSL:** SQL Server requiere `TrustServerCertificate=True;Encrypt=False;`; MariaDB usa `SslMode=Preferred`. Ver `frontend/.env.example` y el template generado en `config.env` para los ejemplos completos con el porque de cada atributo.

### Endpoint de healthcheck del backend

```bash
bash set-health-endpoint.sh
```

- Guarda `BACKEND_HEALTH_ENDPOINT` en `config.env`
- `status.sh` usa este endpoint como URL preferida para validar el backend
- Al guardar, realiza una validacion inmediata (HTTP 200)

### HTTPS interno

```bash
bash configure-internal-https.sh
```

Crea o actualiza el virtual host Nginx para subdominio interno con certificado TLS y proxy `/api` al backend.

### Backup de base de datos

Requiere **dos VMs separadas** (una para la BD, otra para la app) — este toolkit corre en la VM de la app y hace `mariadb-dump` **remoto** contra la BD via `ConnectionStrings__MariaDB`. El dump cifrado queda en `Backup__Dir` (default `/app/backups`) **en la VM de la app**, no en la de la BD — eso ya es un segundo medio real, no una copia en el mismo disco.

- `deploy system setup` autogenera `Backup__EncryptionPassphrase` la primera vez (igual que `PiiEncryption__HashKeyBase64`) y la muestra una sola vez — **respaldala fuera del servidor**. Sin ella, los backups cifrados quedan ilegibles para siempre.
- Corre automaticamente todos los dias a las 03:00 (+/- 10 min) via `backup.timer` / `backup.service` (systemd), instalado por `setup-server.sh`.
- Manual: `deploy menu` → Database → "Correr backup ahora", o `bash modules/database/commands/backup.sh`.
- Retencion local configurable en `Backup__RetentionDays` (default 14 dias) — borra automaticamente los `.sql.gz.enc` mas viejos.
- Ver logs: `journalctl -u backup.service -n 50`.

**Restaurar / descifrar un backup:**

```bash
openssl enc -d -aes-256-cbc -pbkdf2 -pass "pass:<Backup__EncryptionPassphrase>" \
  -in /app/backups/<archivo>.sql.gz.enc -out restore.sql.gz
gunzip restore.sql.gz
mariadb -h <server> -P <port> -u<user> -p -D <database> < restore.sql
```

> **Pendiente conocido:** hoy el backup solo vive en la VM de la app — un segundo medio, no offsite real (misma ubicacion/proveedor). Si mas adelante hay un tercer destino (otro servidor, storage cloud), agregar un paso de copia adicional al final de `backup.sh` es un cambio chico, no un rediseno.

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

release.sh                          scp -r deploy/ user@server:/tmp/deploy
  ├── selecciona componente          ssh user@server "sudo cp -r /tmp/deploy /app/deploy"
  ├── ingresa version
  ├── build local (npm/dotnet)       sudo bash /app/deploy/setup/bootstrap.sh
  ├── WinRAR → app.rar                 ├── instala desde assets/ (offline)
  └── muestra ruta de app.rar          ├── Node.js, .NET SDK, rar/unrar
                                         └── fallback a apt si no hay asset

                                      sudo bash /app/deploy/setup/setup-server.sh
                                        ├── habilita Nginx, systemd
                                        ├── crea /app/config/config.env
                                        └── configura nginx vhost + backend service

                                      scp app.rar user@server:/tmp/

                                      sudo bash /app/deploy/bin/deploy backend install
                                      sudo bash /app/deploy/bin/deploy frontend install
                                           ├── ruta al app.rar en servidor
                                           ├── version
                                           ├── unrar → /app/releases/<componente>/<version>/
                                           ├── ln -sfn → current
                                           └── systemctl restart backend

                                      [Mantenimiento via menu modular o CLI]

                                      bash /app/deploy/bin/menu.sh
                                      bash /app/deploy/bin/deploy <modulo> <accion>

                                      Update
                                        ├── scp app.rar al servidor
                                        ├── deploy backend update
                                        ├── healthcheck estricto
                                        └── [fallo] → rollback automatico

                                      Rollback
                                        ├── deploy backend rollback
                                        ├── lista versiones locales
                                        ├── ln -sfn → version anterior
                                        └── healthcheck soft
```
