-- Asignar el rol "Desarrollador" (R0) a un usuario — MariaDB (PII-HASH compliant)
--
-- La columna Email es PII: se guarda encriptada (Email_enc) y se busca por
-- Email_hash = HMAC-SHA256(email, PiiEncryption__HashKeyBase64).
-- set-developer.sh computa ese hash y reemplaza 0xHASH_PLACEHOLDER antes de correr.

SET @hash_bin = 0xHASH_PLACEHOLDER; -- Reemplazado por set-developer.sh

-- Obtener el usuario por el hash de su email
SET @usuario_id = (
    SELECT Id FROM users
    WHERE Email_hash = @hash_bin AND IsDeleted = 0
    LIMIT 1
);

SELECT IF(@usuario_id IS NULL,
    'ERROR: No se encontro usuario con el email hash proporcionado.',
    CONCAT('OK: Usuario encontrado - ', @usuario_id)
) AS resultado;

-- Obtener el rol "Desarrollador" (R0)
SET @rol_id = (
    SELECT RolId FROM roles
    WHERE Codigo = 'R0' AND IsDeleted = 0
    LIMIT 1
);

-- Insertar solo si existe usuario, existe rol y no lo tiene ya
INSERT INTO user_roles (UsuarioRolId, UserId, RolId, CreatedAt, CreatedBy, IsDeleted)
SELECT UUID(), @usuario_id, @rol_id, UTC_TIMESTAMP(), 'SYSTEM_PII_SCRIPT', 0
WHERE @usuario_id IS NOT NULL AND @rol_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM user_roles
    WHERE UserId = @usuario_id AND RolId = @rol_id AND IsDeleted = 0
  );

SELECT
    CASE
        WHEN @usuario_id IS NULL THEN 'ABORTADO: usuario no encontrado.'
        WHEN @rol_id IS NULL     THEN 'ABORTADO: rol R0 no encontrado.'
        WHEN ROW_COUNT() > 0     THEN 'OK: Rol "Desarrollador" asignado.'
        ELSE                          'INFO: El usuario ya tiene el rol "Desarrollador".'
    END AS resultado;
