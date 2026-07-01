-- =============================================================================
-- seed-test-data-mariadb.sql — Insert test data for write-permission validation
--
-- Placeholders (reemplazados por seed-test-data.sh): mismos que sqlserver.
-- =============================================================================

-- =============================================================================
-- 1. VALIDAR CONEXION
-- =============================================================================
SET @tables_count = (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'organizations');
SELECT IF(@tables_count > 0, 'OK: Conexion exitosa', 'ERR: Tabla organizations no existe') as status;

-- =============================================================================
-- 2. INSERT: Organizacion
-- =============================================================================
INSERT IGNORE INTO organizations (
    OrganizacionId, Codigo, Nombre,
    IsActive,
    CreatedAt, CreatedBy, IsDeleted
) VALUES (
    '__ORG_ID__', '__ORG_CODIGO__', '__ORG_NOMBRE__',
    1,
    CURRENT_TIMESTAMP(6), 'SYSTEM', 0
);

SELECT IF(ROW_COUNT() > 0, 'OK: Organizacion insertada', 'INFO: Organizacion ya existe') as org_result;

-- =============================================================================
-- 3. INSERT: Oficina
-- =============================================================================
INSERT IGNORE INTO offices (
    OficinaId, OrganizacionId, Codigo, Nombre,
    Direccion, Provincia, Distrito, Corregimiento,
    IsActive,
    CreatedAt, CreatedBy, IsDeleted
) VALUES (
    '__OFFICE_ID__', '__ORG_ID__', '__OFFICE_CODIGO__', '__OFFICE_NOMBRE__',
    '__OFFICE_DIRECCION__', '__OFFICE_PROVINCIA__', '__OFFICE_DISTRITO__', '__OFFICE_CORREGIMIENTO__',
    1,
    CURRENT_TIMESTAMP(6), 'SYSTEM', 0
);

SELECT IF(ROW_COUNT() > 0, 'OK: Oficina insertada', 'INFO: Oficina ya existe') as office_result;

-- =============================================================================
-- 4. INSERT: Usuario
-- =============================================================================
-- Email/Nombres/Apellidos/Telefono son PII -> columnas *_enc (blob encriptado).
-- Insertamos bytes placeholder (X'54455354'="TEST"): NO son desencriptables por
-- la app, solo validan permiso de escritura. El registro se elimina en el cleanup.
INSERT IGNORE INTO users (
    Id, SsoId, Username,
    Email_enc, Nombres_enc, Apellidos_enc, Telefono_enc,
    Documento_enc, Documento_hash,
    OrganizacionId, OficinaId,
    IsActive, CreatedAt, CreatedBy, IsDeleted
) VALUES (
    '__USER_ID__', '__USER_ID__', '__USER_USERNAME__',
    X'54455354', X'54455354', X'54455354', X'54455354',
    NULL, NULL,
    '__ORG_ID__', '__OFFICE_ID__',
    1, UTC_TIMESTAMP(), 'SYSTEM', 0
);
SELECT IF(ROW_COUNT() > 0, 'OK: Usuario insertado', 'INFO: Usuario ya existe') as user_result;

-- =============================================================================
-- 5. INSERT: Delivery Order
-- =============================================================================
INSERT IGNORE INTO orders (
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
    CURRENT_TIMESTAMP(6),
    '__ORG_ID__', '__OFFICE_ID__',

    '__USER_ID__', X'54455354',
    '__REF_CODE__', '__OFFICE_CODIGO__',
    X'54455354', X'54455354',  -- Placeholder encrypted ("TEST" en hex)
    NULL, NULL,
    '__ORDER_NACIONALIDAD__', X'54455354', '__ORDER_PROVINCIA__',
    '__ORDER_DESCRIPCION__',
    '__ORDER_SEXO__', '__ORDER_RANGOEDAD__', 0, 35,
    CURRENT_TIMESTAMP(6), 'SYSTEM', 0
);
SELECT IF(ROW_COUNT() > 0, 'OK: Orden de prueba insertada', 'INFO: Orden ya existe') as order_result;

-- =============================================================================
-- 6. VERIFICAR: SELECT
-- =============================================================================
SELECT 'Organizacion' as Entidad, Nombre as Valor FROM organizations WHERE OrganizacionId = '__ORG_ID__'
UNION ALL
SELECT 'Oficina', Nombre FROM offices WHERE OficinaId = '__OFFICE_ID__'
UNION ALL
SELECT 'Usuario', Username FROM users WHERE Id = '__USER_ID__'
UNION ALL
SELECT 'Orden', ReferenceCode FROM orders WHERE DeliveryOrderId = '__ORDER_ID__';

-- =============================================================================
-- 7. UPDATE + RESTORE
-- =============================================================================
UPDATE organizations SET Nombre = CONCAT('__ORG_NOMBRE__', ' (upd)'), UpdatedAt = CURRENT_TIMESTAMP(6), UpdatedBy = 'TEST' WHERE OrganizacionId = '__ORG_ID__';
SELECT 'OK: Organization UPDATE exitoso' as upd_org;
UPDATE organizations SET Nombre = '__ORG_NOMBRE__', UpdatedAt = CURRENT_TIMESTAMP(6), UpdatedBy = 'TEST' WHERE OrganizacionId = '__ORG_ID__';
SELECT 'OK: Organization restaurado' as rst_org;

UPDATE offices SET Nombre = CONCAT('__OFFICE_NOMBRE__', ' (upd)'), UpdatedAt = CURRENT_TIMESTAMP(6), UpdatedBy = 'TEST' WHERE OficinaId = '__OFFICE_ID__';
SELECT 'OK: Office UPDATE exitoso' as upd_off;
UPDATE offices SET Nombre = '__OFFICE_NOMBRE__', UpdatedAt = CURRENT_TIMESTAMP(6), UpdatedBy = 'TEST' WHERE OficinaId = '__OFFICE_ID__';
SELECT 'OK: Office restaurado' as rst_off;

UPDATE users SET Apellidos_enc = X'5445535455', UpdatedAt = CURRENT_TIMESTAMP(6), UpdatedBy = 'TEST' WHERE Id = '__USER_ID__';
SELECT 'OK: User UPDATE exitoso' as upd_usr;
UPDATE users SET Apellidos_enc = X'54455354', UpdatedAt = CURRENT_TIMESTAMP(6), UpdatedBy = 'TEST' WHERE Id = '__USER_ID__';
SELECT 'OK: User restaurado' as rst_usr;

UPDATE orders SET Description = CONCAT('Updated: __ORDER_DESCRIPCION__'), UpdatedAt = CURRENT_TIMESTAMP(6), UpdatedBy = 'TEST' WHERE DeliveryOrderId = '__ORDER_ID__';
SELECT 'OK: Order UPDATE exitoso' as upd_order;
UPDATE orders SET Description = '__ORDER_DESCRIPCION__', UpdatedAt = CURRENT_TIMESTAMP(6), UpdatedBy = 'TEST' WHERE DeliveryOrderId = '__ORDER_ID__';
SELECT 'OK: Order restaurado' as rst_order;

-- =============================================================================
-- 8. DELETE + REINSERT
-- =============================================================================
DELETE FROM orders WHERE DeliveryOrderId = '__ORDER_ID__';
SELECT 'OK: Order DELETE exitoso' as del_order;
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
    CURRENT_TIMESTAMP(6), '__ORG_ID__', '__OFFICE_ID__',
    '__USER_ID__', X'54455354',
    '__REF_CODE__', '__OFFICE_CODIGO__',
    X'54455354', X'54455354', NULL, NULL,
    '__ORDER_NACIONALIDAD__', X'54455354', '__ORDER_PROVINCIA__',
    '__ORDER_DESCRIPCION__',
    '__ORDER_SEXO__', '__ORDER_RANGOEDAD__', 0, 35,
    CURRENT_TIMESTAMP(6), 'SYSTEM', 0
);
SELECT 'OK: Order re-insertada (DELETE+INSERT exitoso)' as reinsert;

-- =============================================================================
-- 9. CLEANUP: Eliminar datos de prueba
-- =============================================================================
SELECT '' as '';
SELECT '============================================' as cleanup;
SELECT '  LIMPIANDO DATOS DE PRUEBA...' as cleanup;
SELECT '============================================' as cleanup;

DELETE FROM orders WHERE DeliveryOrderId = '__ORDER_ID__';
SELECT 'OK: Order de prueba eliminada' as del_order2;
DELETE FROM users WHERE Id = '__USER_ID__';
SELECT 'OK: Usuario de prueba eliminado' as del_user;
DELETE FROM offices WHERE OficinaId = '__OFFICE_ID__';
SELECT 'OK: Oficina de prueba eliminada' as del_office;
DELETE FROM organizations WHERE OrganizacionId = '__ORG_ID__';
SELECT 'OK: Organizacion de prueba eliminada' as del_org;

SELECT '' as '';
SELECT '============================================' as result;
SELECT '  INSERT  SELECT  UPDATE  DELETE  LIMPIADO' as result;
SELECT '  Datos de prueba automaticamente LIMPIADOS' as result;
SELECT '============================================' as result;
