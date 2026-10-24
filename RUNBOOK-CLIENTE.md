# Runbook — Deploy Producción (Cliente)

> Guía corta y operativa para desplegar EMA en el servidor del cliente
> (**Ubuntu 24.04, air-gapped / sin internet**). Frontend Vue + backend .NET 10.
> Para detalle extendido ver `runbook.md`.

---

## 0. Regla de entrega (IMPORTANTE)

La transferencia va **partida**: el toolkit liviano y cada grupo de assets en su
propio `.rar`. Así un cambio de una línea no obliga a subir ~1.1 GB.

| Parte | Contenido | Peso aprox. |
|---|---|---|
| `deploy.rar` | toolkit (bin, core, modules, setup, scripts, runbooks), **sin `assets/`** | 148 KB |
| `deploy_dotnet_assets.rar` | `assets/dotnet/` (SDK .NET) | 229 MB |
| `deploy_system_assets.rar` | `assets/system/` (.deb del SO) | 68 MB |
| `deploy_database_assets.rar` | `assets/database/` | 3.9 MB |
| `deploy_nginx_assets.rar` | `assets/nginx/` | 792 KB |
| `deploy_tools_assets.rar` | `assets/tools/` (rar/unrar) | 736 KB |
| `deploy_packages_assets.rar` | `assets/packages/` | vacío hoy |
| `deploy_observability_assets.rar` | `assets/observability/` | 750 MB |
| `deploy_assets_all.rar` | todos los assets juntos (`--all`) | ~1.1 GB |
| `SHA256SUMS.txt` | checksum SHA-256 de cada parte | — |

- **Generación (máquina de build, con `rar`/WinRAR):**
  ```bash
  scripts/pack-transfer.sh                 # deploy.rar + una parte por grupo
  scripts/pack-transfer.sh --all           # deploy.rar + deploy_assets_all.rar
  scripts/pack-transfer.sh --only nginx    # deploy.rar + solo nginx (incremental)
  ```
  Salida por defecto: `transfer/` (gitignoreado). `--out <dir>` cambia el destino.
- **Qué subir según el escenario:**
  - **Servidor nuevo (air-gapped):** `deploy.rar` + `dotnet`, `system`,
    `database`, `nginx`, `tools` (y `observability` **solo si el sitio usa** el
    stack de observabilidad). `packages` solo si no está vacío. Node NO se
    sube: el servidor nunca ejecuta Node, el frontend llega ya compilado en
    `frontend.rar`. También podés usar `deploy_assets_all.rar` para una sola
    subida.
  - **Servidor existente que solo actualiza el toolkit:** `deploy.rar` únicamente.
  - **Cambió un asset puntual:** `deploy.rar` (si también cambió el toolkit) +
    la parte del grupo afectado.
- **Extracción:** cada parte de assets guarda `assets/<grupo>/...`; extraé
  **siempre en la raíz del repo** (`/app/deploy`) para reconstituir el árbol:
  ```bash
  cd /app/deploy
  sudo unrar x /ruta/deploy.rar
  sudo unrar x /ruta/deploy_<grupo>_assets.rar
  ```
- **Verificación de integridad:** con las partes y `SHA256SUMS.txt` en la misma
  carpeta, antes de extraer:
  ```bash
  cd /ruta/donde/estan/las/partes
  sha256sum -c SHA256SUMS.txt
  ```
- **NUNCA un `git clone`** — los `.deb`/tarballs están gitignoreados y un clone
  deja `assets/` vacío → el bootstrap se rompe sin internet.
- **Artefactos de la aplicación:** `backend.rar` y `frontend.rar` viajan aparte (FTP a
  `/app/artifacts/`). Comparar su SHA-256 con el que informa el build antes de instalarlos.
- **Evidencias:** `setup-server.sh` deja `/app/deploy/storage/evidences` con permisos
  `0700` en directorios y `0600` en archivos. El volumen **no** está cifrado por decisión
  registrada (riesgo aceptado); si se revisa, el procedimiento está en `RUNBOOK-LUKS.md`.
- **Licencia:** crear los `.rar` requiere WinRAR/`rar` con licencia en la
  máquina de build. El cliente **solo necesita `unrar`** para extraer (sin
  licencia); el binario viaja en `assets/tools/rarlinux-*.tar.gz` y
  `bootstrap.sh` lo instala. Si el servidor está limpio y todavía no tiene
  `unrar`, subí ese `.tar.gz` (736 KB) aparte y extraelo con `tar`; después el
  toolkit instala `rar`/`unrar` desde `assets/tools/`.
- Git es solo para versionar/resguardar el código.

## Prerrequisitos de infraestructura
- Ubuntu 24.04 (amd64). Usuario con `sudo`.
- Puertos: **22** (SSH), **80** (HTTP/challenge), **443** (HTTPS). Abiertos en firewall.
- **HTTPS del cliente = interno** (`configure-https`, cert propio del tribunal). **NO Let's Encrypt** (eso es solo para dev con internet).
- Base de datos interna accesible (SQL Server o MariaDB) con sus credenciales.

---

## 1. Secuencia de deploy (orden exacto)

> El menú del cliente (`sudo deploy menu`) agrupa el trabajo por **categoría**
> (¿qué querés hacer?): **1) ¿Cómo está el sistema?** · **2) Respaldos** ·
> **3) Actualizar la aplicación** · **4) Base de datos** ·
> **5) Configuración y seguridad**. Cada opción despacha al mismo comando de la
> CLI (`sudo deploy <módulo> <acción>`), así que no cambia nada para la
> automatización.
>
> La categoría **6) Avanzado** (`configure-letsencrypt`, `release`, `uninstall`)
> está oculta y se habilita sólo con `DEPLOY_DEV_MODE=1`. Los comandos directos
> siguen funcionando cuando se invocan a mano. El módulo **Database** NO tiene
> acciones ocultas.

```bash
# 1) Transferir el paquete partido (ver §0) a /app/deploy:
#      deploy.rar + deploy_<grupo>_assets.rar que correspondan
#    Verificar checksums y extraer con 'unrar x' EN LA RAIZ (/app/deploy).

# 2) Setup: bootstrap offline + nginx + systemd + config.env + CLI
sudo bash /app/deploy/setup/setup-server.sh
#    - Instala .NET/Node/nginx/mariadb-client/sqlcmd DESDE assets (sin internet)
#    - Abre nano para completar config.env  (ver §2)

# 2.5) Respaldar secretos ANTES de seguir (PASO OBLIGATORIO en instalación nueva):
#      el setup genera la passphrase de respaldo y la muestra UNA sola vez; sin esta
#      copia, los respaldos de BD son ilegibles si se pierde la VM (DOC-23).
sudo deploy system backup-secrets --out /ruta/externa/secrets-backups   # USB/offsite, NUNCA bajo /app
sudo deploy system backup-secrets --verify /ruta/externa/secrets-backups/secrets-backup-*.enc
#    - Guarda la passphrase con doble custodio, fuera del servidor (ver DOC-23 §Respaldo de secretos).

# 3) HTTPS interno con el cert del cliente
sudo deploy nginx configure-https
#    - Dejá el par cert+key en /app/artifacts/ssl/  (o los pide interactivo)

# 4) Base de datos: EF migra el esquema al arrancar el backend.
sudo deploy database create           # SOLO si borraron la base (la crea vacía)
sudo deploy database reset-schema     # SOLO si el esquema viejo/roto: borra tablas, conserva la base
#    El comando 'run-schema' YA NO EXISTE — EF (auto-migrate) es la ÚNICA fuente de verdad.

# 5) Copiar por FTP los artefactos a /app/artifacts/
#      frontend -> /app/artifacts/frontend.rar
#      backend  -> /app/artifacts/backend.rar
#    (el .rar lleva el CONTENIDO de dist/ y publish/ en la raíz, sin carpeta envolvente)

# 6) Instalar (ver §4 para el control de arranque del backend)
sudo deploy frontend install          # pide versión
sudo deploy backend install           # pide versión + arranque controlado

# 7) Registrar redirect URIs en Entra ID (ver §3)

# 8) Verificar
curl -kI https://<dominio>/            # 200
curl -k  https://<dominio>/api/health  # 200 JSON, DB Healthy
sudo deploy health                     # estado simple: [OK] ... → TODO FUNCIONANDO
```

---

## 2. `config.env` (BACKEND)  — `/app/config/config.env` (chmod 600)

> Se carga vía systemd `EnvironmentFile`. **appsettings.json NO lleva secretos.**
> Editar con: `sudo deploy system edit-config`

```ini
CONFIG_VERSION="4"

# --- NGINX ---
# Dominio del cliente (sin barra final). "_" acepta cualquier host.
NGINX_SERVER_NAME="entrega-biometrica.tribunal-electoral.gob.pa"
# Rutas del cert (las setea 'deploy nginx configure-https'; si ambas están, nginx sube 443).
NGINX_SSL_CERT="/etc/nginx/ssl/entrega-biometrica.tribunal-electoral.gob.pa.crt"
NGINX_SSL_KEY="/etc/nginx/ssl/entrega-biometrica.tribunal-electoral.gob.pa.key"
BACKEND_HEALTH_ENDPOINT="http://localhost:5000/api/health"

# --- DATABASE ---
# DB_PROVIDER decide QUÉ driver usa el backend. DEBE coincidir con la cadena que llenás.
DB_PROVIDER="MariaDB"                  # o "SqlServer"

# SQL Server interno (SIN SSL válido). Dejar VACÍO si usás MariaDB.
#   Server=host,puerto      -> SQL Server separa host/puerto con COMA
#   User ID=...             -> NO uses Trusted_Connection (es auth Windows, no anda en Linux)
#   TrustServerCertificate=True -> OBLIGATORIO en internos (si no, rechaza el cert self-signed)
#   Encrypt=False           -> si el server no tiene TLS
ConnectionStrings__SqlServer=""
# Ejemplo: "Server=10.0.0.5,1433;Database=EB;User ID=eb_app;Password=secret;TrustServerCertificate=True;Encrypt=False;"

# MariaDB interno. Dejar VACÍO si usás SQL Server.
#   Port=3307               -> OJO: el default del proyecto es 3307 (no 3306). Confirmá el real.
#   CharSet=utf8mb4         -> unicode completo (PII/acentos)
#   SslMode=Preferred       -> usa SSL sin validar cert (anda en internos). NUNCA Required/VerifyCA/VerifyFull.
#   AllowPublicKeyRetrieval=False
ConnectionStrings__MariaDB="Server=10.0.0.6;Port=3307;Database=ema;User=eb_app;Password=CHANGE_ME;CharSet=utf8mb4;SslMode=Preferred;AllowPublicKeyRetrieval=False;"

# --- FRONTEND (CORS) ---
# Origen EXACTO del front, SIN barra final. Es config de RUNTIME (no rebuild al cambiarlo).
FrontendProdUrl="https://entrega-biometrica.tribunal-electoral.gob.pa"

# --- AUTH OIDC (Entra ID) ---
Authentication__Authority="https://login.microsoftonline.com/<TENANT_ID>/"
Authentication__Audience="api://<CLIENT_ID>"
# Descomentar SOLO si el IdP es HTTP interno (Entra es HTTPS -> dejar comentado):
# Authentication__RequireHttpsMetadata="false"

# --- PII ENCRYPTION ---
# Clave HMAC (base64, 32+ bytes) para hashes de búsqueda sobre columnas PII.
# CRÍTICA: si se pierde, las búsquedas por hash dejan de matchear datos históricos.
# El setup la autogenera si está en CHANGE_ME y muestra el valor -> RESPALDALO fuera del server.
PiiEncryption__HashKeyBase64="CHANGE_ME"

# --- TRIBUNAL SERVICES ---
TribunalServices__NetworkScope="Internal"     # Internal | External
# TribunalServices__Servers__Internal__Prod=
# TribunalServices__Credentials__1__Username=
# TribunalServices__Credentials__1__Password=
# TribunalServices__Credentials__1__HostPrefix=      # prefijo del hostname interno (antes "Secret")
# Sustitucion de identidades: SOLO para pruebas; vacio = deshabilitada.
# TribunalServices__AuthorizedSubstitutions__0=
# TribunalServices__SubstitutionUsuario=

# --- RUNTIME OVERRIDES (opcionales, tienen default en appsettings) ---
# Session__CookieTimeoutHours=1
# RateLimiting__MaxRequests=100
```

**Checklist config.env:** un solo `CHANGE_ME` sin dejar · `DB_PROVIDER` coincide con la cadena llena · la cadena que NO usás va VACÍA · `FrontendProdUrl` sin barra final.

---

## 3. `frontend/.env` (FRONTEND)  — se HORNEA en `npm run build`

> ⚠️ Las `VITE_*` se **compilan** en el build. Si cambiás algo hay que **rebuildear** el frontend.
> Construir con el `.env` del cliente ANTES de empaquetar `frontend.rar`.

```ini
###############################################################################
# AZURE AD / MSAL  (App Registration del cliente)
###############################################################################
VITE_AZURE_CLIENT_ID=<CLIENT_ID>
VITE_AZURE_TENANT_ID=<TENANT_ID>
VITE_AZURE_API_SCOPE=api://<CLIENT_ID>/access_as_user

# Redirect URIs — DOMINIO DEL CLIENTE, un solo esquema https:// (NO "http://https://").
# Deben coincidir EXACTO con las registradas en Entra (§3.1).
VITE_AZURE_REDIRECT_URI=https://entrega-biometrica.tribunal-electoral.gob.pa/auth/callback
VITE_AZURE_POST_LOGOUT_REDIRECT_URI=https://entrega-biometrica.tribunal-electoral.gob.pa/auth/logout-callback

# API / SignalR — DEJAR VACÍO: el código usa "/api" y hubs same-origin (nginx proxea).
# NO pongas "/hub" en HUB_BASE_URL (rompe el WebSocket).
VITE_API_BASE_URL=
VITE_HUB_BASE_URL=

# CSP — SOLO afectan el dev-server de Vite (vite.config server.headers).
# En el build de prod NO se hornea CSP; nginx no pone CSP. Podés dejarlos o quitarlos.
VITE_CSP_API_URL=https://entrega-biometrica.tribunal-electoral.gob.pa
VITE_CSP_WS_URL=wss://entrega-biometrica.tribunal-electoral.gob.pa

# Varios
VITE_AVATAR_URL=/api/profile/photo/
VITE_APP_VERSION=1.0.0
```

### 3.1 Registrar en Entra ID (App Registration → Authentication)
- Plataforma: **Single-page application (SPA)** — **NO "Web"** (MSAL.js usa PKCE; "Web" da `AADSTS9002326`).
- Redirect URIs (exactas, https, dominio del cliente):
  - `https://entrega-biometrica.tribunal-electoral.gob.pa/auth/callback`
  - `https://entrega-biometrica.tribunal-electoral.gob.pa/auth/logout-callback`
- Entra **no acepta IP** como redirect URI (solo hostname) → por eso se necesita el dominio + HTTPS.

---

## 4. Control de arranque del backend (migración limpia)

El backend aplica **migraciones EF al arrancar**. Para que corran UNA sola vez y sin carrera:

```bash
# Al actualizar el backend:
sudo deploy system services        # -> backend -> stop      (apagado bajo tu control)
sudo deploy backend install        # extrae + symlink; PREGUNTA si arrancar ahora
                                    #   -> respondé "No": lo deja detenido
sudo deploy system services        # -> backend -> start     (encendido bajo tu control)
sudo journalctl -u backend -f      # mirás la migración en vivo
```

- Un arranque **único y controlado** (desde detenido) evita la carrera de `Restart=always`.
- **BD vacía + migración `Initial` única** → EF crea todo de cero, limpio.
- La base la crea EF si no existe; si alguien la borró del servidor, `deploy database create` la recrea vacía. NO hay comando de esquema manual: EF es la única fuente de verdad.

---

## 5. Respaldos de base de datos

Los respaldos son dumps cifrados (AES-256) de MariaDB, guardados **en esta VM**
(la de la app), no en la de la base de datos.

- **Automático:** cada **3 días a las 03:00** (± 10 min), vía `backup.timer` /
  `backup.service` (systemd). El timer lo instala `deploy system setup`; si faltara,
  se instala solo al configurar los respaldos.
- **Operador:** `sudo deploy menu` → **Respaldos** →
  **"Respaldos (configurar / ver los existentes)"** (o `sudo deploy database backup`):
  - Si **no está configurado** → ofrece configurarlo: genera la clave de cifrado,
    crea la carpeta y **instala el timer**. Pide confirmación y explica qué quedó.
  - Si **ya está configurado** → **lista los respaldos** existentes (fecha y tamaño,
    el más reciente primero) y muestra el estado de la programación.
- **La clave de cifrado** (`Backup__EncryptionPassphrase`) es CRÍTICA: si se pierde,
  los respaldos ya generados quedan ilegibles. Respaldala fuera del servidor.
- **Retención:** 14 días (configurable en `Backup__RetentionDays`).
- **Forzar un respaldo ahora:** `sudo systemctl start backup.service`.
- **Verificar la programación:** `systemctl list-timers backup.timer` (NEXT/LAST) o
  `systemctl show backup.timer -p NextElapseUSecRealtime -p LastTriggerUSec`.

### Restaurar un respaldo (recuperación)

`sudo deploy menu` → **Respaldos** → **"Restaurar un respaldo"**
(o `sudo deploy database restore`):

```bash
sudo deploy database restore                 # lista y deja elegir por número
sudo deploy database restore --last           # el respaldo más reciente
sudo deploy database restore --file <ruta>    # un archivo específico
sudo deploy database restore --last --yes      # automatización (sin confirmación)
```

- **Antes de tocar la base** guarda un respaldo de seguridad del estado ACTUAL
  (`pre-restore-<base>-<fecha>.sql.gz.enc`). Si ese paso falla, **aborta**.
- Pide **confirmación explícita**: hay que escribir `RESTAURAR` (sin terminal y sin
  `--yes` se rechaza; usa `--yes` sólo en automatización).
- Al terminar sugiere `sudo deploy health simple` para confirmar que la app quedó sana.
- Si el descifrado falla (clave incorrecta/archivo corrupto), la base **no** se
  modifica. Si la carga falla a mitad, avisa y deja el `pre-restore` para volver.

---

## 6. Troubleshooting rápido

| Síntoma | Causa / Fix |
|---|---|
| `apt: Unmet dependencies` / dpkg roto | Falta un `.deb` en `assets`. Reenviá `deploy_system_assets.rar` (o `deploy_assets_all.rar`) y extraelo en `/app/deploy`. Offline no hay `apt -f install`. |
| Backend crash-loop, `Duplicate column` | Esquema desincronizado con migraciones. `reset-schema` (borra tablas, conserva la base) + reinstalar backend; EF reconstruye el esquema. |
| `AADSTS50011 redirect_uri mismatch` | La URI no está registrada en Entra, o el `.env` tiene doble esquema. Registrar en Entra como **SPA** y rebuildear el front con la URI correcta. |
| `/api/health` devuelve HTML | nginx no matchea `/api`. Re-aplicar: `sudo deploy nginx reload` / re-correr setup. |
| Backend no arranca, `config.env` con CHANGE_ME | Completar `config.env` (`deploy system edit-config`) y reiniciar. |
| Servicios / logs | `deploy system services` (start/stop/restart/status/logs) · `journalctl -u backend -f` |
```
