# Runbook — Cifrado en reposo del volumen de evidencias (LUKS2)

Procedimiento para cifrar con LUKS2 el volumen que contiene las evidencias biométricas del sistema
(fotos de captura facial, firmas y certificados) montado en `/app/deploy/storage/evidences`.

> **Cuándo ejecutarlo:** durante la instalación, **antes** de que el sistema reciba evidencias
> reales. Si el servidor ya tiene evidencias, use el procedimiento de migración (§6).

## 1. Qué protege y qué no

| Escenario | LUKS con el volumen desbloqueado | LUKS con el volumen cerrado |
| :--- | :--- | :--- |
| Robo del disco de evidencias | Protegido | Protegido |
| Robo del servidor completo, apagado | Depende del desbloqueo: con keyfile en el mismo disco del SO, **no** protege; con passphrase o TPM2, sí | Protegido |
| Acceso con el sistema encendido | **No protege** | — |
| Copia de respaldo | Solo si el respaldo también va cifrado (DOC-23) | — |

LUKS protege los **datos en reposo**. No sustituye los permisos `0600`/`0700`, el usuario de
servicio sin privilegios ni el control de acceso al servidor: los complementa.

## 2. Niveles de desbloqueo

| Nivel | Desbloqueo | Ventaja | Costo |
| :--- | :--- | :--- | :--- |
| A | Keyfile en el mismo servidor | Automático tras un reinicio | No protege contra el robo del servidor completo si el disco del SO no está cifrado |
| B | Passphrase con intervención manual | Protege el servidor completo | El servicio no arranca solo tras un corte de energía |
| C | TPM2 (si el servidor o su vTPM lo soportan) | Automático y atado al hardware | El TPM no libera la clave en otro equipo; no protege con el SO comprometido en caliente |

**Recomendación:** nivel **C** si el hardware lo soporta; nivel **B** si no. El nivel **A** solo es
aceptable si el disco del sistema operativo **ya** está cifrado y el keyfile queda dentro de ese
volumen cifrado.

## 3. Requisitos

- Ubuntu 24.04 con `cryptsetup` (incluido en el ISO; verificar con `cryptsetup --version`).
- Una partición o volumen lógico **dedicado** para evidencias (ejemplo: `/dev/tribunal/evidences`).
- Acceso root y una ventana de mantenimiento.
- Un medio cifrado y separado para el respaldo del encabezado LUKS (§7).
- Custodios designados para la passphrase y el respaldo del encabezado.

## 4. Instalación en un servidor nuevo

```bash
# 0) Identificar el dispositivo dedicado. NUNCA usar el disco del SO.
lsblk

# 1) Formatear el volumen con LUKS2 (pide confirmación y passphrase)
cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 \
  --hash sha256 /dev/tribunal/evidences

# 2) Abrir, formatear y montar
cryptsetup open /dev/tribunal/evidences evidences_crypt
mkfs.ext4 -L evidences /dev/mapper/evidences_crypt
mkdir -p /app/deploy/storage/evidences
mount /dev/mapper/evidences_crypt /app/deploy/storage/evidences

# 3) Propietario y permisos (el servicio corre sin privilegios)
chown app-backend:app-backend /app/deploy/storage/evidences
chmod 700 /app/deploy/storage/evidences

# 4) Desbloqueo automático (nivel A o C)
#    Nivel A: keyfile
mkdir -p /etc/luks && chmod 700 /etc/luks
dd if=/dev/urandom of=/etc/luks/evidences.key bs=512 count=8 status=none
chmod 400 /etc/luks/evidences.key
cryptsetup luksAddKey /dev/tribunal/evidences /etc/luks/evidences.key

#    Nivel C: TPM2 (reemplaza o complementa al keyfile)
# systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/tribunal/evidences

# 5) Montaje en el arranque
echo 'evidences_crypt /dev/tribunal/evidences /etc/luks/evidences.key luks' >> /etc/crypttab
echo '/dev/mapper/evidences_crypt /app/deploy/storage/evidences ext4 defaults,noatime 0 2' >> /etc/fstab
systemctl daemon-reload
```

Notas:

- **No** agregar `discard` a la entrada de `crypttab` salvo que se acepte revelar el patrón de uso
  del volumen (TRIM filtra qué bloques están en uso).
- El nivel **B** omite el keyfile: usar `luks,keyscript=...` o desbloquear a mano con
  `cryptsetup open` antes de arrancar el servicio.
- Los scripts de instalación **no** formatean discos: este paso es responsabilidad del administrador
  de infraestructura.

## 5. Verificación

```bash
lsblk -f
cryptsetup status evidences_crypt
findmnt /app/deploy/storage/evidences
stat -c '%a %U:%G' /app/deploy/storage/evidences      # esperado: 700 app-backend:app-backend

# Prueba de escritura real (el servicio debe poder escribir)
sudo -u app-backend sh -c 'printf test > /app/deploy/storage/evidences/.luks-check'
stat -c '%a %U:%G' /app/deploy/storage/evidences/.luks-check   # esperado: 600 app-backend:app-backend
rm -f /app/deploy/storage/evidences/.luks-check
```

## 6. Migración de un servidor con evidencias

1. Detener el servicio: `systemctl stop backend`.
2. Respaldar el volumen **descifrado** según DOC-23 y verificar el checksum del respaldo.
3. Formatear y montar el volumen cifrado (§4).
4. Restaurar el respaldo en `/app/deploy/storage/evidences`.
5. Aplicar permisos (`chown -R`, `find ... -exec chmod 700/600`).
6. Arrancar el servicio y verificar (§5).

## 7. Respaldo del encabezado LUKS — obligatorio

Sin el encabezado no hay recuperación posible aunque se conserve la passphrase.

```bash
cryptsetup luksHeaderBackup /dev/tribunal/evidences \
  --header-backup-file /root/evidences-luks-header-$(date +%F).img
chmod 400 /root/evidences-luks-header-*.img
```

- Copiar el archivo a un **medio cifrado separado** (no al mismo disco).
- Registrar en DOC-23: fecha, custodios y ubicación.
- Probar la restauración en un entorno de ensayo antes de dar el paso por cerrado:

```bash
cryptsetup luksHeaderRestore /dev/tribunal/ensayo --header-backup-file <archivo>
```

## 8. Rotación y gestión de claves

```bash
# Agregar una clave nueva (passphrase o keyfile)
cryptsetup luksAddKey /dev/tribunal/evidences

# Cambiar la passphrase
cryptsetup luksChangeKey /dev/tribunal/evidences

# Quitar una clave (identificador de slot desde luksDump)
cryptsetup luksDump /dev/tribunal/evidences
cryptsetup luksRemoveKey /dev/tribunal/evidences
```

Registrar cada rotación en los custodios de claves de DOC-11.

## 9. Recuperación

| Escenario | Acción |
| :--- | :--- |
| El servicio arrancó sin montar el volumen | Verificar `/etc/crypttab` y `/etc/fstab`; `cryptdisks_start evidences_crypt` |
| Encabezado dañado | Restaurar el respaldo del encabezado (§7) sobre el dispositivo |
| Passphrase y keyfile perdidos | **No hay recuperación**; el riesgo debe estar aceptado por escrito (DOC-11) |
| Volumen corrupto pero abierto | `umount`, `fsck.ext4 /dev/mapper/evidences_crypt`, volver a montar |
| Restauración de un respaldo | DOC-23 (restauración de base + evidencias) |

## 10. Evidencia para auditoría

Conservar: salida de `cryptsetup luksDump` (sin material de clave), fecha de creación, nivel de
desbloqueo elegido, ubicación y custodios del respaldo del encabezado, y el registro de la prueba
de restauración.

## 11. Checklist

- [ ] Volumen dedicado identificado (no es el disco del SO).
- [ ] LUKS2 formateado con `aes-xts-plain64`.
- [ ] Montado en `/app/deploy/storage/evidences` y habilitado en `crypttab`/`fstab`.
- [ ] Permisos `700` del directorio y `600` de los archivos, propietario `app-backend`.
- [ ] Nivel de desbloqueo elegido y documentado (A/B/C).
- [ ] Respaldo del encabezado en medio cifrado separado, con custodios.
- [ ] Prueba de restauración del encabezado en ensayo.
- [ ] Verificación §5 completada y archivada.
