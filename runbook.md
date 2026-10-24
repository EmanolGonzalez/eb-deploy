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

- [ ] Generar el paquete partido: `scripts/pack-transfer.sh` (o `--all`). Ver **Paso 1**.
- [ ] Subir `deploy.rar` + las partes de assets que correspondan y extraerlas con
      `unrar x` **en la raiz** (`/app/deploy`). Verificar `SHA256SUMS.txt`.
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
| `update.sh` | Actualiza un componente con auto-rollback si el healthcheck falla |
| `rollback.sh` | Restaura un componente a una version instalada localmente |
| `release.sh` | Construye y empaqueta un componente en app.rar (se ejecuta desde dev) |
| `scripts/pack-transfer.sh` | Genera `deploy.rar` + una parte de assets por grupo + `SHA256SUMS.txt` (se ejecuta desde dev) |
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
│   ├── assets/                 # Dependencias offline (dotnet, tools)
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

### Cifrado del volumen de evidencias (LUKS2)

Las evidencias biométricas (fotos, firmas, certificados) se guardan en
`/app/deploy/storage/evidences`. Antes de recibir evidencias reales, ese volumen debe estar cifrado
con LUKS2 y montado en esa ruta; el backend aplica permisos `0600`/`0700` sobre el contenido.

El procedimiento completo — formateo, desbloqueo automático (keyfile, passphrase o TPM2), respaldo
del encabezado, rotación y recuperación — está en **`RUNBOOK-LUKS.md`**.

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

### Paso 1 — Generar y copiar el sistema de deploy al servidor

La transferencia va **partida**: `deploy.rar` lleva solo el toolkit y cada grupo
de `assets/` viaja en su propio `deploy_<grupo>_assets.rar`. Generá las partes en
la **maquina de build** (necesita `rar`/WinRAR con licencia):

```bash
scripts/pack-transfer.sh                 # deploy.rar + una parte por grupo
scripts/pack-transfer.sh --all           # deploy.rar + deploy_assets_all.rar
scripts/pack-transfer.sh --only nginx    # deploy.rar + solo nginx (incremental)
```

Salida por defecto: `transfer/` (gitignoreado); `--out <dir>` cambia el destino.
Cada parte de assets guarda las rutas `assets/<grupo>/...`, así que al extraerla
en `/app/deploy` el arbol queda igual que con la carpeta completa.

**Que subir segun el escenario:**

- **Servidor nuevo (air-gapped):** `deploy.rar` + `dotnet`, `system`,
  `database`, `nginx`, `tools` (+ `observability` **solo si el sitio usa** el
  stack ADR-007; `packages` solo si no esta vacio). Node NO se sube: el
  servidor nunca ejecuta Node, el frontend llega ya compilado en
  `frontend.rar`. Tambien podes usar `deploy_assets_all.rar` para una sola
  subida.
- **Servidor existente que solo actualiza el toolkit:** `deploy.rar` unicamente.
- **Cambio de un asset puntual:** `deploy.rar` (si tambien cambio el toolkit) +
  la parte del grupo afectado.

**Transferir, verificar y extraer** (cliente; solo necesita `unrar`):

```bash
# 1) Subir las partes + SHA256SUMS.txt a /tmp/transfer (SCP, FTP, USB)
# 2) Verificar integridad ANTES de extraer:
cd /tmp/transfer
sha256sum -c SHA256SUMS.txt

# 3) Extraer en la raiz del repo, una parte por vez:
sudo mkdir -p /app/deploy
cd /app/deploy
sudo unrar x /tmp/transfer/deploy.rar
sudo unrar x /tmp/transfer/deploy_system_assets.rar
# ... repetir por cada grupo que corresponda
```

**Servidor limpio sin `unrar`:** subí ademas
`assets/tools/rarlinux-x64-720.tar.gz` (736 KB) y extraelo con `tar`; ese
binario sirve para extraer las partes. Despues `bootstrap.sh` instala
`rar`/`unrar` desde `assets/tools/`.

**Licencia:** crear los `.rar` requiere WinRAR/`rar` con licencia en la maquina
de build. El cliente solo necesita `unrar` (sin licencia).

> Alternativa sin split (no recomendada para cambios chicos): copiar la carpeta
> `bs_deploy` completa, con `assets/` poblada, a `/app/deploy`. **Nunca** un
> `git clone`: los `.deb`/tarballs estan gitignoreados y `assets/` quedaria
> vacio.

### Paso 2 — Bootstrap (instalacion offline de dependencias)

```bash
sudo bash /app/deploy/setup/bootstrap.sh
```

Esto instala desde `assets/` (sin internet):
- Node.js 22.x
- .NET 10 SDK
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

El menu principal agrupa las tareas por **categoría** ("¿qué querés hacer?"):

1. **¿Cómo está el sistema?** — estado (un toque) · diagnóstico completo · historial de deploys (auditoría)
2. **Respaldos** — configurar / ver los existentes
3. **Actualizar la aplicación** — Backend · Frontend · Observabilidad
4. **Base de datos** — crear base · verificar conexión · reset de esquema · asignar rol Developer
5. **Configuración y seguridad** — editar config.env · HTTPS interno · recargar nginx · rotar llave RSA · rotar Hash Key PII · gestionar servicios
6. **🔧 Avanzado** (solo con `DEPLOY_DEV_MODE=1`) — Let's Encrypt · release (build) · desinstalar

Las categorías son una **vista**: cada opción despacha al mismo comando de la CLI
(`deploy <modulo> <accion>`), así que la automatización y los runbooks no cambian.
Los menús por módulo siguen disponibles: `deploy <modulo>` (sin acción) abre el
menú de ese módulo.

**Base de datos:** el esquema lo aplica EF automaticamente al arrancar. El comando
`run-schema` fue **removido**. Si falta la base entera: `deploy database create`
(la crea vacia). Si el esquema quedo roto: `deploy database reset-schema` (borra
las tablas, conserva la base) y EF reconstruye al arrancar.

**Modo desarrollador:** la categoría **6) Avanzado** (Let's Encrypt, release,
desinstalar) NO se lista en el menu del cliente. Para mostrarla (solo
desarrollo/CI):

```bash
DEPLOY_DEV_MODE=1 bash /app/deploy/bin/deploy menu
```

Los comandos siguen funcionando al invocarlos directo (`deploy nginx
configure-letsencrypt`, `deploy system uninstall`, `deploy release build`, ...).

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

Vista simple para el operador (un solo comando, sin jerga ni JSON). Corre
**sin accion** — `deploy health` muestra el estado y termina con un veredicto:
`→ TODO FUNCIONANDO` (exit 0) o una linea accionable `→ QUÉ HACER: ...`
(exit 1). Si el modulo de observabilidad no esta instalado, esa linea se omite.

```bash
deploy health                     # estado simple (recomendado)
[OK]   Página web
[OK]   Aplicación
[OK]   Base de datos
→ TODO FUNCIONANDO
```

El diagnostico tecnico sigue disponible:

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
- Corre automaticamente **cada 3 dias a las 03:00** (+/- 10 min) via `backup.timer` / `backup.service` (systemd), instalado por `setup-server.sh` (unidades renderizadas desde `modules/database/lib/backup-schedule.sh`).
  - Mecanismo: `OnCalendar=*-*-01/3 03:00:00` (dias 1, 4, 7, …) + `Persistent=true`. Se prefiere a `OnUnitActiveSec=3d` porque es hora fija de reloj (no se corre con cada ejecucion manual) y `Persistent=true` recupera la corrida si el server estaba apagado.
- Operador: `deploy menu` → Database → **"Respaldos (configurar / ver los existentes)"** o `deploy database backup`:
  - Si **no esta configurado** → ofrece configurarlo: asegura la passphrase (genera si falta; `deploy system setup` tambien lo hace), crea la carpeta `Backup__Dir` y **instala el timer** (pide confirmacion y explica en lenguaje simple).
  - Si **ya esta configurado** → **lista los respaldos existentes** (fecha + tamano, mas reciente primero) y el estado de la programacion (proxima/ultima corrida).
- Retencion local configurable en `Backup__RetentionDays` (default 14 dias) — borra automaticamente los `.sql.gz.enc` mas viejos.
- Forzar un respaldo ahora: `systemctl start backup.service`.
- Verificar la programacion: `systemctl list-timers backup.timer` (NEXT/LAST) o `systemctl show backup.timer -p NextElapseUSecRealtime -p LastTriggerUSec`.
- Ver logs: `journalctl -u backup.service -n 50`.

### Restaurar un respaldo (recuperacion)

**Operador:** `deploy menu` → **Respaldos** → **"Restaurar un respaldo"**, o
`deploy database restore`.

```bash
sudo deploy database restore                 # lista y deja elegir por numero
sudo deploy database restore --last           # el respaldo regular mas reciente
sudo deploy database restore --file <ruta>    # un archivo especifico
sudo deploy database restore --last --yes      # automatizacion (sin prompt)
```

Flujo:

1. **Lista** los respaldos de la base actual (fecha + tamano, mas reciente primero)
   — incluye los `pre-restore-*`. Sin seleccion, muestra la lista y sale.
2. El operador elige uno por numero (o `--last` / `--file`).
3. **Confirmacion explicita**: muestra una advertencia de que se REEMPLAZA el
   contenido actual y pide escribir `RESTAURAR`. Sin terminal y sin `--yes` se
   **rechaza** (no hay forma de confirmar a ciegas).
4. **Respaldo pre-restore obligatorio**: antes de tocar la base, guarda el estado
   ACTUAL en `pre-restore-${DB}-<timestamp>.sql.gz.enc` (mismo `Backup__Dir`). Si
   este paso falla, **se aborta** la restauracion.
5. **Restaura**: descifra (AES-256) → gunzip → carga en `${DB}` via
   `ConnectionStrings__MariaDB` (cliente directo o docker), igual que `backup.sh`.
6. **Verifica**: sugiere `deploy health simple` y reporta la ruta del pre-restore.

Fallos:

- Passphrase ausente/`CHANGE_ME` o cadena de conexion invalida → aborta con mensaje
  claro, sin tocar la base.
- Descifrado fallido (passphrase incorrecta / archivo corrupto) → la base **NO** se
  modifica.
- Carga fallida a mitad → avisa que la base puede quedar incompleta y reporta el
  `pre-restore`; para volver: `deploy database restore --file <pre-restore> --yes`.

**Restaurar manualmente (sin el toolkit):**

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

scripts/pack-transfer.sh            scp deploy.rar + deploy_<grupo>_assets.rar
  ├── deploy.rar (sin assets)         + SHA256SUMS.txt → /tmp/transfer
  ├── deploy_<grupo>_assets.rar       sha256sum -c SHA256SUMS.txt
  └── SHA256SUMS.txt                  cd /app/deploy && unrar x <cada parte>

release.sh                          sudo bash /app/deploy/setup/bootstrap.sh
  ├── selecciona componente            ├── instala desde assets/ (offline)
  ├── ingresa version                  ├── Node.js, .NET SDK, rar/unrar
  ├── build local (npm/dotnet)         └── fallback a apt si no hay asset
  ├── WinRAR → app.rar
  └── muestra ruta de app.rar

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
