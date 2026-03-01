# Runbook — eb-deploy
> ⚠️ **Importante:**
> `setup-server.sh` solo prepara el entorno (Nginx, Node.js, .NET, systemd, etc.).
> El despliegue de la aplicación se hace siempre con `install.sh`, una ejecución por componente.

Este runbook describe el paso a paso para preparar el entorno y operar los scripts de despliegue, actualización y rollback.

## Prerrequisito: hosts (evitar IP)

Antes del despliegue, en entornos cerrados sin DNS interno, agrega los aliases necesarios en hosts.

Linux:
```bash
sudo nano /etc/hosts
```

Windows:
```text
C:\Windows\System32\drivers\etc\hosts
```

Ejemplo:
```text
10.10.10.10  test-esb.tribunal-electoral.gob.pa
10.10.10.11  esb.tribunal-electoral.gob.pa
10.10.10.12  bussec.tribunal-electoral.gob.pa
10.10.10.13  buste.tribunal-electoral.gob.pa
10.10.10.20  sql.entrega.local
```

## Preparación del entorno (primera vez)

1. Crea la carpeta de scripts:
   ```bash
   mkdir -p /app/scripts
   cd /app/scripts
   ```
2. Descarga `ops-menu.sh` (entrada principal):
   ```bash
   wget -O ops-menu.sh https://raw.githubusercontent.com/<usuario>/<repo>/main/ops-menu.sh
   chmod +x ops-menu.sh
   ```
3. Ejecuta el menú y usa **Actualizar scripts** para traer todo:
   ```bash
   bash ops-menu.sh
   ```
   El menú descargará `fetch-all.sh` si no existe y luego traerá todos los scripts.
4. Ejecuta el setup (instala dependencias y configura servicios):
   ```bash
   bash setup-server.sh
   ```
   Durante el setup, el script preguntará si deseas registrar dominio/subdominio para `server_name` en Nginx.
5. Instala cada componente por separado:
   ```bash
   bash install.sh   # selecciona frontend
   bash install.sh   # selecciona backend
   ```

## Operaciones de mantenimiento

Una vez el entorno está preparado, puedes usar los siguientes scripts para mantenimiento y gestión de versiones:

### Instalación manual de una nueva versión
```bash
bash install.sh
# Sigue los prompts para SAS_TOKEN, componente y versión
```

### Actualización
```bash
bash update.sh
# Sigue los prompts para SAS_TOKEN, componente y versión
```

Notas de actualización:
- `update.sh` no ejecuta healthcheck bloqueante.
- Si necesitas validar luego del update, usa `status.sh` o `healthcheck.sh --soft`.

### Rollback
```bash
bash rollback.sh
# Selecciona el componente y la versión local a restaurar
```

Notas de rollback:
- `rollback.sh` ejecuta healthcheck en modo suave (`--soft`) para no bloquear el flujo por transitorios.

### Uninstall de la aplicación (manteniendo evidencia)
```bash
bash uninstall.sh
```

Notas de uninstall:
- Elimina despliegue, sitio Nginx de la app y servicio backend.
- Preserva las carpetas `/app/evidence` y `/app/evidences`.

### Healthcheck
```bash
bash healthcheck.sh backend
bash healthcheck.sh frontend

# Modo no bloqueante
bash healthcheck.sh backend --soft
```

### Estado operativo
```bash
bash status.sh

# Para automatización
bash status.sh --json
```

### Configurar / cambiar cadena de conexión (backend)
```bash
bash set-db-connection.sh
```

### Configurar endpoint health backend (status)
```bash
bash set-health-endpoint.sh
```

### Configurar HTTPS interno (Nginx + subdominio)
```bash
bash configure-internal-https.sh
```

### Consola técnica (menú)
```bash
bash ops-menu.sh
```

Dentro del menú puedes usar **Actualizar scripts** para ejecutar `fetch-all.sh` y traer todos los scripts desde la URL base raw.

Notas:
- Guarda la cadena en `/app/config/db-connection.txt`.
- El cambio se aplica al backend actual y ofrece reiniciar el servicio.
- `install.sh`, `update.sh` y `rollback.sh` preguntan en backend si deseas usar la cadena guardada o ingresar otra.
- En próximos `install.sh`/`update.sh` del backend, la cadena se vuelve a aplicar automáticamente en `appsettings.json`.
- `appsettings.Development.json` no se toca.
- `set-health-endpoint.sh` guarda la URL en `/app/config/backend-health-endpoint.txt`.
- `status.sh` usa esa URL como endpoint preferido para validar el backend.
- `configure-internal-https.sh` crea/actualiza el virtual host Nginx para subdominio interno con certificado TLS y proxy `/api` al backend.

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