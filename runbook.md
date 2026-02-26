# Runbook — eb-deploy
> ⚠️ **Importante:**
> El flujo recomendado es ejecutar `setup-server.sh`, que instala y configura automáticamente todas las dependencias del sistema (Nginx, Node.js, .NET, systemd, etc.) y realiza el despliegue inicial de la aplicación.
> Los scripts `install.sh`, `update.sh` y `rollback.sh` solo gestionan el despliegue y mantenimiento de la aplicación, y asumen que el entorno ya está preparado.
Este runbook describe el paso a paso para preparar el entorno y operar los scripts de despliegue, actualización y rollback.
## Preparación y despliegue inicial (recomendado)
1. Crea una carpeta para los scripts (recomendado):
   ```bash
   mkdir -p /app/scripts
   cd /app/scripts
   ```
2. Descarga el script setup-server.sh manualmente:
   ```bash
   wget -O setup-server.sh https://raw.githubusercontent.com/<usuario>/<repo>/main/scripts/setup-server.sh
   chmod +x setup-server.sh
   ```
3. Ejecuta el script maestro:
   ```bash
   bash setup-server.sh
   ```
4. El script instalará dependencias, configurará servicios y realizará el despliegue inicial de la aplicación.
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