# Runbook — eb-deploy
> ⚠️ **Importante:**
> `setup-server.sh` solo prepara el entorno (Nginx, Node.js, .NET, systemd, etc.).
> El despliegue de la aplicación se hace siempre con `install.sh`, una ejecución por componente.

Este runbook describe el paso a paso para preparar el entorno y operar los scripts de despliegue, actualización y rollback.

## Preparación del entorno (primera vez)

1. Crea la carpeta de scripts:
   ```bash
   mkdir -p /app/scripts
   cd /app/scripts
   ```
2. Descarga `setup-server.sh`:
   ```bash
   wget -O setup-server.sh https://raw.githubusercontent.com/<usuario>/<repo>/main/setup-server.sh
   chmod +x setup-server.sh
   ```
3. Ejecuta el setup (instala dependencias y configura servicios):
   ```bash
   bash setup-server.sh
   ```
4. Instala cada componente por separado:
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

### Rollback
```bash
bash rollback.sh
# Selecciona el componente y la versión local a restaurar
```

### Healthcheck
```bash
bash healthcheck.sh
```