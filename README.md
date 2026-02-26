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
# Actualizar un componente (guarda versión anterior, hace rollback automático si falla)
bash update.sh

# Revertir manualmente a una versión anterior
bash rollback.sh

# Verificar que la aplicación está sana
bash healthcheck.sh
```

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
