-- =============================================================================
-- seed-test-data-sqlserver.sql — Insert test data for write-permission validation
--
-- Placeholders (reemplazados por seed-test-data.sh):
--   __ORG_ID__       -> GUID de la organización
--   __OFFICE_ID__    -> GUID de la oficina
--   __USER_ID__      -> GUID del usuario
--   __ORDER_ID__     -> GUID de la orden
--   __REF_CODE__     -> Código de referencia (ej: REF-TEST-001)
--
-- Las columnas encriptadas (Documento_enc, CitizenNationalId_enc) se insertan
-- con datos binarios placeholder para probar permisos de escritura sin
-- depender de la lógica de encriptación de la aplicación.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- =============================================================================
-- 1. VALIDAR CONEXION
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'organizations')
BEGIN
    RAISERROR('La tabla organizations no existe. Verifica la conexion.', 16, 1);
    RETURN;
END

PRINT '============================================';
PRINT '  INICIANDO INSERCION DE DATOS DE PRUEBA';
PRINT '============================================';

-- =============================================================================
-- 2. INSERT: Organizacion
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM organizations WHERE OrganizacionId = '__ORG_ID__')
BEGIN
    INSERT INTO organizations (
        OrganizacionId, Codigo, Nombre,
        IsActive,
        CreatedAt, CreatedBy, IsDeleted
    ) VALUES (
        '__ORG_ID__', '__ORG_CODIGO__', '__ORG_NOMBRE__',
        1,
        SYSUTCDATETIME(), 'SYSTEM', 0
    );
    PRINT 'OK: Organizacion insertada.';
END
ELSE
    PRINT 'INFO: Organizacion ya existe.';

-- =============================================================================
-- 3. INSERT: Oficina
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM offices WHERE OficinaId = '__OFFICE_ID__')
BEGIN
    INSERT INTO offices (
        OficinaId, OrganizacionId, Codigo, Nombre,
        Direccion, Provincia, Distrito, Corregimiento,
        IsActive,
        CreatedAt, CreatedBy, IsDeleted
    ) VALUES (
        '__OFFICE_ID__', '__ORG_ID__', '__OFFICE_CODIGO__', '__OFFICE_NOMBRE__',
        '__OFFICE_DIRECCION__', '__OFFICE_PROVINCIA__', '__OFFICE_DISTRITO__', '__OFFICE_CORREGIMIENTO__',
        1,
        SYSUTCDATETIME(), 'SYSTEM', 0
    );
    PRINT 'OK: Oficina insertada.';
END
ELSE
    PRINT 'INFO: Oficina ya existe.';

-- =============================================================================
-- 4. INSERT: Usuario
--    Documento_enc y Documento_hash son campos encriptados — se insertan
--    como NULL. La aplicación debe encriptar al crear un usuario real.
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM users WHERE Id = '__USER_ID__')
BEGIN
    -- Email/Nombres/Apellidos/Telefono son PII -> columnas *_enc (varbinary).
    -- Bytes placeholder (0x54455354="TEST"): NO desencriptables por la app, solo
    -- validan permiso de escritura. El registro se elimina en el cleanup.
    INSERT INTO users (
        Id, SsoId, Username,
        Email_enc, Nombres_enc, Apellidos_enc, Telefono_enc,
        Documento_enc, Documento_hash,
        OrganizacionId, OficinaId,
        IsActive, CreatedAt, CreatedBy, IsDeleted
    ) VALUES (
        '__USER_ID__', '__USER_ID__', '__USER_USERNAME__',
        0x54455354, 0x54455354, 0x54455354, 0x54455354,
        NULL, NULL,
        '__ORG_ID__', '__OFFICE_ID__',
        1, SYSUTCDATETIME(), 'SYSTEM', 0
    );
    PRINT 'OK: Usuario insertado.';
END
ELSE
    PRINT 'INFO: Usuario ya existe.';

-- =============================================================================
-- 5. INSERT: Delivery Order
--    CitizenNationalId_enc y CitizenSerialNumber_enc son campos encriptados.
--    Insertamos un valor binario placeholder para probar permisos de escritura.
--    NOTA: Este dato NO es desencriptable por la aplicación.
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM orders WHERE DeliveryOrderId = '__ORDER_ID__')
BEGIN
    INSERT INTO orders (
        DeliveryOrderId, Status, Flags, IsDebug, SystemDebugMode, Attempts,
        RequestedAt,
        OrganizationId, OfficeId,
        RequestedByUserId, RequestedByDocument_enc,
        ReferenceCode, TribunalOfficeCode,
        CitizenNationalId_enc, CitizenSerialNumber_enc,
        CitizenNationalId_hash, CitizenSerialNumber_hash,
        Nationality, Address_enc, Province, Description, Sex, RangeAge,
        IsJuvenile, CitizenAge,
        CreatedAt, CreatedBy, IsDeleted
    ) VALUES (
        '__ORDER_ID__', 'Pendiente', 0, 0, NULL, 0,
        SYSUTCDATETIME(),
        '__ORG_ID__', '__OFFICE_ID__',
        '__USER_ID__', 0x54455354,
        '__REF_CODE__', '__OFFICE_CODIGO__',
        0x54455354, 0x54455354,  -- Placeholder encrypted ("TEST" en hex)
        NULL, NULL,
        '__ORDER_NACIONALIDAD__', 0x54455354, '__ORDER_PROVINCIA__',
        '__ORDER_DESCRIPCION__',
        '__ORDER_SEXO__', '__ORDER_RANGOEDAD__', 0, 35,
        SYSUTCDATETIME(), 'SYSTEM', 0
    );
    PRINT 'OK: Orden de prueba insertada.';
END
ELSE
    PRINT 'INFO: Orden ya existe.';

-- =============================================================================
-- 6. VERIFICAR: SELECT
-- =============================================================================
PRINT '';
PRINT '============================================';
PRINT '  VERIFICACION DE LECTURA';
PRINT '============================================';
SELECT 'Organización' as Entidad, Nombre as Valor FROM organizations WHERE OrganizacionId = '__ORG_ID__'
UNION ALL
SELECT 'Oficina', Nombre FROM offices WHERE OficinaId = '__OFFICE_ID__'
UNION ALL
SELECT 'Usuario', Username FROM users WHERE Id = '__USER_ID__'
UNION ALL
SELECT 'Orden', ReferenceCode FROM orders WHERE DeliveryOrderId = '__ORDER_ID__';

-- =============================================================================
-- 7. UPDATE + RESTORE
-- =============================================================================
UPDATE organizations SET Nombre = '__ORG_NOMBRE__ (upd)', UpdatedAt = SYSUTCDATETIME(), UpdatedBy = 'TEST' WHERE OrganizacionId = '__ORG_ID__';
PRINT 'OK: Organization UPDATE exitoso.';
UPDATE organizations SET Nombre = '__ORG_NOMBRE__', UpdatedAt = SYSUTCDATETIME(), UpdatedBy = 'TEST' WHERE OrganizacionId = '__ORG_ID__';
PRINT 'OK: Organization restaurado.';

UPDATE offices SET Nombre = '__OFFICE_NOMBRE__ (upd)', UpdatedAt = SYSUTCDATETIME(), UpdatedBy = 'TEST' WHERE OficinaId = '__OFFICE_ID__';
PRINT 'OK: Office UPDATE exitoso.';
UPDATE offices SET Nombre = '__OFFICE_NOMBRE__', UpdatedAt = SYSUTCDATETIME(), UpdatedBy = 'TEST' WHERE OficinaId = '__OFFICE_ID__';
PRINT 'OK: Office restaurado.';

UPDATE users SET Apellidos_enc = 0x5445535455, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = 'TEST' WHERE Id = '__USER_ID__';
PRINT 'OK: User UPDATE exitoso.';
UPDATE users SET Apellidos_enc = 0x54455354, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = 'TEST' WHERE Id = '__USER_ID__';
PRINT 'OK: User restaurado.';

UPDATE orders SET Description = 'Updated: __ORDER_DESCRIPCION__', UpdatedAt = SYSUTCDATETIME(), UpdatedBy = 'TEST' WHERE DeliveryOrderId = '__ORDER_ID__';
PRINT 'OK: Order UPDATE exitoso.';
UPDATE orders SET Description = '__ORDER_DESCRIPCION__', UpdatedAt = SYSUTCDATETIME(), UpdatedBy = 'TEST' WHERE DeliveryOrderId = '__ORDER_ID__';
PRINT 'OK: Order restaurado.';

-- =============================================================================
-- 8. DELETE + REINSERT (limpia y recrea para probar DELETE)
-- =============================================================================
DELETE FROM orders WHERE DeliveryOrderId = '__ORDER_ID__';
PRINT 'OK: Order DELETE exitoso.';
INSERT INTO orders (
    DeliveryOrderId, Status, Flags, IsDebug, SystemDebugMode, Attempts,
    RequestedAt, OrganizationId, OfficeId,
    RequestedByUserId, RequestedByDocument_enc,
    ReferenceCode, TribunalOfficeCode,
    CitizenNationalId_enc, CitizenSerialNumber_enc,
    CitizenNationalId_hash, CitizenSerialNumber_hash,
    Nationality, Address_enc, Province, Description, Sex, RangeAge,
    IsJuvenile, CitizenAge,
    CreatedAt, CreatedBy, IsDeleted
) VALUES (
    '__ORDER_ID__', 'Pendiente', 0, 0, NULL, 0,
    SYSUTCDATETIME(), '__ORG_ID__', '__OFFICE_ID__',
    '__USER_ID__', 0x54455354,
    '__REF_CODE__', '__OFFICE_CODIGO__',
    0x54455354, 0x54455354, NULL, NULL,
    '__ORDER_NACIONALIDAD__', 0x54455354, '__ORDER_PROVINCIA__',
    '__ORDER_DESCRIPCION__',
    '__ORDER_SEXO__', '__ORDER_RANGOEDAD__', 0, 35,
    SYSUTCDATETIME(), 'SYSTEM', 0
);
PRINT 'OK: Order re-insertada (DELETE+INSERT exitoso).';

-- =============================================================================
-- 9. CLEANUP: Eliminar datos de prueba
-- =============================================================================
PRINT '';
PRINT '============================================';
PRINT '  LIMPIANDO DATOS DE PRUEBA...';
PRINT '============================================';

DELETE FROM orders WHERE DeliveryOrderId = '__ORDER_ID__';
PRINT 'OK: Order de prueba eliminada.';
DELETE FROM users WHERE Id = '__USER_ID__';
PRINT 'OK: Usuario de prueba eliminado.';
DELETE FROM offices WHERE OficinaId = '__OFFICE_ID__';
PRINT 'OK: Oficina de prueba eliminada.';
DELETE FROM organizations WHERE OrganizacionId = '__ORG_ID__';
PRINT 'OK: Organizacion de prueba eliminada.';

PRINT '';
PRINT '============================================';
PRINT '  RESULTADO: TODAS LAS OPERACIONES EXITOSAS';
PRINT '  INSERT  ✅  SELECT  ✅  UPDATE  ✅  DELETE  ✅';
PRINT '  Datos de prueba automaticamente LIMPIADOS';
PRINT '============================================';
