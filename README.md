# eb-deploy - Deploy Scripts

Scripts de despliegue para la aplicación. Los artefactos (`.rar`) se almacenan en un contenedor **privado** de Azure Blob Storage y nunca se suben a este repositorio.

## Estructura del repositorio

```
├── setup-server.sh   - Prepara el entorno del servidor (primera vez)
├── fetch-all.sh      - Descarga todos los scripts desde GitHub
├── install.sh        - Instala un componente (frontend o backend)
├── update.sh         - Actualiza a una nueva versión
├── rollback.sh       - Revierte a una versión anterior
├── healthcheck.sh    - Verifica que la aplicación está sana
├── status.sh         - Muestra versión desplegada y estado de frontend/backend
├── set-db-connection.sh - Configura ConnectionStrings:DefaultConnection para backend
└── runbook.md        - Paso a paso operacional
```

## Arquitectura en el servidor

```
Cliente
   │
   ▼
Nginx :80
   ├── /        → archivos estáticos  /app/releases/frontend/current
   └── /api     → proxy               http://127.0.0.1:5000

Backend .NET 9 (systemd: backend)
   └── escucha en :5000 (solo localhost)
```

Configuración persistente en `/app/config/storage.conf` (creada por `setup-server.sh`).

## Hosts (evitar usar IP)

Para los servicios SOAP del TE en entornos cerrados, si no hay resolución DNS, agrega los dominios en hosts para evitar usar IP directa.

Linux (servidor o cliente Linux):
```bash
sudo nano /etc/hosts
```

Windows (equivalente):
```text
C:\Windows\System32\drivers\etc\hosts
```

Ejemplo de entradas para SOAP TE (usar las IP reales que te entregue infraestructura):
```text
10.10.10.10  test-esb.tribunal-electoral.gob.pa
10.10.10.11  esb.tribunal-electoral.gob.pa
10.10.10.12  bussec.tribunal-electoral.gob.pa
10.10.10.13  buste.tribunal-electoral.gob.pa
10.10.10.20  sql.entrega.local
```

Luego accede por:
```text
https://test-esb.tribunal-electoral.gob.pa
```

Para base de datos en otro servidor, usa el alias en la cadena de conexión:
```text
Server=sql.entrega.local,1433;Database=EB;User ID=<usuario>;Password=<password>;TrustServerCertificate=True;
```

## Primer despliegue

```bash
# 1. Descargar setup-server.sh
mkdir -p /app/scripts && cd /app/scripts
wget -O setup-server.sh https://raw.githubusercontent.com/<usuario>/<repo>/main/setup-server.sh
chmod +x setup-server.sh

# 2. Preparar el entorno (instala Nginx, Node.js, .NET, systemd, descarga scripts)
bash setup-server.sh

# 3. Instalar cada componente
bash install.sh   # selecciona frontend
bash install.sh   # selecciona backend
```

El SAS token se introduce sin `?`: `sv=2024-11-04&ss=b&srt=sco&sp=rl&sig=...`

El SAS token necesita permisos **Read + List** sobre el contenedor, con resource types **Service + Container + Object**.

## Operaciones de mantenimiento

```bash
# Actualizar un componente (guarda versión anterior)
bash update.sh

# Revertir manualmente a una versión anterior
bash rollback.sh

# Verificar que la aplicación está sana
bash healthcheck.sh

# Verificar sin romper flujo (solo advertencias)
bash healthcheck.sh backend --soft

# Ver estado completo (versiones + servicios)
bash status.sh

# Ver estado en JSON (para monitoreo/automatización)
bash status.sh --json

# Configurar/cambiar la cadena de conexión del backend (persistente)
bash set-db-connection.sh
```

Notas de cadena de conexión:
- `set-db-connection.sh` guarda la cadena en `/app/config/db-connection.txt`.
- `install.sh` y `update.sh` aplican automáticamente esa cadena a `publish/appsettings.json` cuando el componente es backend.
- `appsettings.Development.json` no se modifica.

## Gestión de servicios

```bash
# Estado
systemctl status nginx
systemctl status backend

# Reiniciar
systemctl restart nginx
systemctl restart backend

# Logs en tiempo real
journalctl -u backend -f
journalctl -u nginx -f

# Últimas 50 líneas
journalctl -u backend -n 50
journalctl -u nginx -n 50
```

## Estructura de artefactos en Azure Blob Storage

```
<container>/
├── frontend/
│   └── <version>/
│       └── app.rar
└── backend/
    └── <version>/
        └── app.rar
```

## Notas

- El almacenamiento de artefactos es privado. Este repositorio solo contiene los scripts.
- No hay pipelines CI/CD en este repositorio. Se gestionan externamente.
- No hay código fuente de la aplicación en este repositorio.
