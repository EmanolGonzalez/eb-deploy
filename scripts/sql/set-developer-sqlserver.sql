-- Asignar el rol "Desarrollador" (R0) a un usuario — SQL Server (PII-HASH compliant)
--
-- La columna Email es PII: se guarda encriptada (Email_enc) y se busca por
-- Email_hash = HMAC-SHA256(email, PiiEncryption__HashKeyBase64).
-- set-developer.sh computa ese hash y reemplaza 0xHASH_PLACEHOLDER antes de correr.

SET QUOTED_IDENTIFIER ON;

DECLARE @EmailHash VARBINARY(32) = 0xHASH_PLACEHOLDER; -- Reemplazado por set-developer.sh
DECLARE @UsuarioId UNIQUEIDENTIFIER;
DECLARE @RolId UNIQUEIDENTIFIER;

-- Obtener el usuario por el hash de su email
SELECT @UsuarioId = U.Id
FROM users U
WHERE U.Email_hash = @EmailHash
  AND U.IsDeleted = 0;

IF @UsuarioId IS NULL
BEGIN
    RAISERROR('No se encontro usuario con el email hash proporcionado.', 16, 1);
    RETURN;
END

-- Obtener el rol "Desarrollador" (R0)
SELECT @RolId = R.RolId
FROM roles R
WHERE R.Codigo = 'R0'
  AND R.IsDeleted = 0;

IF @RolId IS NULL
BEGIN
    RAISERROR('No se encontro el rol "Desarrollador" (R0).', 16, 1);
    RETURN;
END

-- Asignar solo si no lo tiene ya
IF NOT EXISTS (
    SELECT 1 FROM user_roles
    WHERE UsuarioId = @UsuarioId AND RolId = @RolId AND IsDeleted = 0
)
BEGIN
    INSERT INTO user_roles (UsuarioRolId, UsuarioId, RolId, CreatedAt, CreatedBy, IsDeleted)
    VALUES (NEWID(), @UsuarioId, @RolId, SYSUTCDATETIME(), 'SYSTEM_PII_SCRIPT', 0);
    PRINT 'OK: Rol "Desarrollador" asignado.';
END
ELSE
BEGIN
    PRINT 'INFO: El usuario ya tiene el rol "Desarrollador".';
END
