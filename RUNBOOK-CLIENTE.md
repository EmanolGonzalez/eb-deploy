# Runbook — Deploy Producción (Cliente)

> Guía corta y operativa para desplegar EMA en el servidor del cliente
> (**Ubuntu 24.04, air-gapped / sin internet**). Frontend Vue + backend .NET 9.
> Para detalle extendido ver `runbook.md`.

---

## 0. Regla de entrega (IMPORTANTE)

- El paquete se transfiere por **FTP: la carpeta `bs_deploy` COMPLETA** (con `assets/` poblada). **NUNCA un `git clone`** — los `.deb`/tarballs están gitignoreados y un clone deja `assets/` vacío → el bootstrap se rompe sin internet.
- **Script y assets viajan juntos.** Si actualizás `setup/bootstrap.sh`, subí también `assets/system/`. No hagas cherry-pick de un solo archivo.
- Git es solo para versionar/resguardar el código.

## Prerrequisitos de infraestructura
- Ubuntu 24.04 (amd64). Usuario con `sudo`.
- Puertos: **22** (SSH), **80** (HTTP/challenge), **443** (HTTPS). Abiertos en firewall.
- **HTTPS del cliente = interno** (`configure-https`, cert propio del tribunal). **NO Let's Encrypt** (eso es solo para dev con internet).
- Base de datos interna accesible (SQL Server o MariaDB) con sus credenciales.

---

## 1. Secuencia de deploy (orden exacto)

```bash
# 1) Copiar por FTP la carpeta bs_deploy completa a  /app/deploy
#    (incluye assets/ con los .deb y tarballs)

# 2) Setup: bootstrap offline + nginx + systemd + config.env + CLI
sudo bash /app/deploy/setup/setup-server.sh
#    - Instala .NET/Node/nginx/mariadb-client/sqlcmd DESDE assets (sin internet)
#    - Abre nano para completar config.env  (ver §2)

# 3) HTTPS interno con el cert del cliente
sudo deploy nginx configure-https
#    - Dejá el par cert+key en /app/artifacts/ssl/  (o los pide interactivo)

# 4) Base de datos: dejar VACÍA para que EF migre de cero
sudo deploy database reset-schema     # SOLO si la BD tiene esquema viejo/roto
#    NO uses 'run-schema' — EF (auto-migrate) es la ÚNICA fuente de verdad.

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
# TribunalServices__Credentials__1__Secret=

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
- **BD vacía + `InitialCreate` único** → EF crea todo de cero, limpio.
- **NO mezclar** `run-schema` con auto-migrate: elegí una sola fuente de verdad (EF).

---

## 5. Troubleshooting rápido

| Síntoma | Causa / Fix |
|---|---|
| `apt: Unmet dependencies` / dpkg roto | Falta un `.deb` en `assets`. Reenviá `assets/system/` completo por FTP. Offline no hay `apt -f install`. |
| Backend crash-loop, `Duplicate column` | Esquema desincronizado con migraciones. `reset-schema` (BD vacía) + reinstalar backend. No usar `run-schema`. |
| `AADSTS50011 redirect_uri mismatch` | La URI no está registrada en Entra, o el `.env` tiene doble esquema. Registrar en Entra como **SPA** y rebuildear el front con la URI correcta. |
| `/api/health` devuelve HTML | nginx no matchea `/api`. Re-aplicar: `sudo deploy nginx reload` / re-correr setup. |
| Backend no arranca, `config.env` con CHANGE_ME | Completar `config.env` (`deploy system edit-config`) y reiniciar. |
| Servicios / logs | `deploy system services` (start/stop/restart/status/logs) · `journalctl -u backend -f` |
```
