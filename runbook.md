# Runbook — eb-deploy

Este runbook describe el paso a paso para operar los scripts de despliegue, actualización y rollback.

---


## Preparación del entorno

1. Crea una carpeta para los scripts (recomendado):
   ```bash
   mkdir -p /app/scripts
   cd /app/scripts
   ```
2. Descarga el script fetch-all.sh manualmente:
   ```bash
   wget -O fetch-all.sh https://raw.githubusercontent.com/<usuario>/<repo>/main/fetch-all.sh
   chmod +x fetch-all.sh
   ```
3. Descarga todos los scripts:
   ```bash
   bash fetch-all.sh
   # El script te pedirá la URL base raw de GitHub, por ejemplo:
   # https://raw.githubusercontent.com/<usuario>/<repo>/main
   ```

---

## Instalación

1. Ejecuta el script de instalación:
   ```bash
   bash install.sh
   ```
2. El script solicitará:
   - SAS_TOKEN (por variable o prompt)
   - STORAGE_ACCOUNT y CONTAINER_NAME (solo la primera vez)
3. Selecciona el componente (frontend/backend) y la versión.
4. El script descarga, extrae y actualiza symlink.
5. Si es backend, reinicia el servicio.
6. El healthcheck se ejecuta automáticamente.

---

## Actualización

1. Ejecuta el script de actualización:
   ```bash
   bash update.sh
   ```
2. El script solicitará:
   - SAS_TOKEN (permite reutilizar el actual)
3. Selecciona el componente y la versión.
4. El script guarda la versión actual para rollback.
5. Descarga, extrae y actualiza symlink.
6. Si es backend, reinicia el servicio.
7. El healthcheck se ejecuta automáticamente.
   - Si falla, el script ejecuta rollback.sh automáticamente.

---

## Rollback

1. Ejecuta el script de rollback manualmente:
   ```bash
   bash rollback.sh
   ```
2. Selecciona el componente y la versión local a restaurar.
3. El script actualiza symlink y reinicia el servicio si es backend.
4. El healthcheck se ejecuta automáticamente.

---

## Notas
- El script rollback.sh también es llamado automáticamente por update.sh si el healthcheck falla tras una actualización.
- Nunca almacenes SAS_TOKEN ni credenciales en disco.
- Todos los scripts requieren permisos de root.
- Consulta el README para detalles de variables y estructura.
