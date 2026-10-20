-- =============================================================================
-- esquema-backend.mariadb.sql — DDL de REFERENCIA del backend (MariaDB).
--
-- GENERADO desde las migraciones de EF Core (fuente de verdad del esquema).
-- NO editar a mano: regenerar con el comando de abajo.
--
-- OJO: LA INSTALACION NO EJECUTA ESTE ARCHIVO.
--   El backend aplica las migraciones EF automaticamente al arrancar; el
--   esquema real lo construye EF. Este DDL se conserva solo como REFERENCIA
--   (auditoria / entregable ScriptsBD). El comando historico
--   `deploy database run-schema` fue REMOVIDO.
--   Flujo de base de datos:
--     - Falta la base entera:  `deploy database create` (crea la base vacia)
--     - Esquema roto/viejo:    `deploy database reset-schema` (borra tablas,
--                              conserva la base) y EF reconstruye al arrancar.
--
-- Incluye la tabla __EFMigrationsHistory tal como la generaria EF (util si
-- alguien reaplica este DDL a mano como referencia).
--
-- Regeneracion (desde backend/):
--   dotnet ef migrations script -p Persistence -s Api -c MariaDbAppDbContext \
--     -o scripts/sql/esquema-backend.mariadb.sql
--   (requiere DB_PROVIDER=MariaDB y ConnectionStrings__MariaDB: el script no
--    abre conexion, la cadena solo satisface el diseno del contexto.)
CREATE TABLE IF NOT EXISTS `__EFMigrationsHistory` (
    `MigrationId` varchar(150) CHARACTER SET utf8mb4 NOT NULL,
    `ProductVersion` varchar(32) CHARACTER SET utf8mb4 NOT NULL,
    CONSTRAINT `PK___EFMigrationsHistory` PRIMARY KEY (`MigrationId`)
) CHARACTER SET=utf8mb4;

START TRANSACTION;
ALTER DATABASE CHARACTER SET utf8mb4;

CREATE TABLE `audit_entries` (
    `AuditEntryId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Timestamp` datetime(6) NOT NULL,
    `ActorId` varchar(50) CHARACTER SET utf8mb4 NULL,
    `Action` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `EntityType` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `EntityId` varchar(200) CHARACTER SET utf8mb4 NULL,
    `Description` varchar(500) CHARACTER SET utf8mb4 NULL,
    `IpAddress_enc` longblob NULL,
    `TraceId` varchar(100) CHARACTER SET utf8mb4 NULL,
    `Metadata` longtext CHARACTER SET utf8mb4 NULL,
    `Period` varchar(7) CHARACTER SET utf8mb4 NOT NULL,
    CONSTRAINT `PK_audit_entries` PRIMARY KEY (`AuditEntryId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `audit_entry_archives` (
    `AuditEntryArchiveId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `OriginalAuditEntryId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `Timestamp` datetime(6) NOT NULL,
    `ActorId` longtext CHARACTER SET utf8mb4 NULL,
    `Action` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `EntityType` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `EntityId` longtext CHARACTER SET utf8mb4 NULL,
    `Description` longtext CHARACTER SET utf8mb4 NULL,
    `IpAddress` longtext CHARACTER SET utf8mb4 NULL,
    `TraceId` longtext CHARACTER SET utf8mb4 NULL,
    `Metadata` longtext CHARACTER SET utf8mb4 NULL,
    `Period` varchar(7) CHARACTER SET utf8mb4 NOT NULL,
    `ArchivedAt` datetime(6) NOT NULL,
    CONSTRAINT `PK_audit_entry_archives` PRIMARY KEY (`AuditEntryArchiveId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `DataProtectionKeys` (
    `Id` int NOT NULL AUTO_INCREMENT,
    `FriendlyName` longtext CHARACTER SET utf8mb4 NULL,
    `Xml` longtext CHARACTER SET utf8mb4 NULL,
    CONSTRAINT `PK_DataProtectionKeys` PRIMARY KEY (`Id`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `order_access_log_archives` (
    `DeliveryOrderAccessLogArchiveId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `OriginalDeliveryOrderAccessLogId` char(36) COLLATE ascii_general_ci NOT NULL,
    `DeliveryOrderId` char(36) COLLATE ascii_general_ci NOT NULL,
    `OfficialNationalId` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `AccessType` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `Source` longtext CHARACTER SET utf8mb4 NULL,
    `AccessedAt` datetime(6) NOT NULL,
    `Period` varchar(7) CHARACTER SET utf8mb4 NOT NULL,
    `ArchivedAt` datetime(6) NOT NULL,
    CONSTRAINT `PK_order_access_log_archives` PRIMARY KEY (`DeliveryOrderAccessLogArchiveId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `organizations` (
    `OrganizacionId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Codigo` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `Nombre` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `IsOperational` tinyint(1) NOT NULL DEFAULT TRUE,
    `IsInMaintenance` tinyint(1) NOT NULL DEFAULT FALSE,
    `MaintenanceMessage` varchar(500) CHARACTER SET utf8mb4 NULL,
    `IsActive` tinyint(1) NOT NULL DEFAULT TRUE,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_organizations` PRIMARY KEY (`OrganizacionId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `permissions` (
    `PermisoId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Codigo` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `Nombre` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `Descripcion` varchar(300) CHARACTER SET utf8mb4 NULL,
    `IsActive` tinyint(1) NOT NULL DEFAULT TRUE,
    `IsSystem` tinyint(1) NOT NULL DEFAULT FALSE,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_permissions` PRIMARY KEY (`PermisoId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `roles` (
    `RolId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Codigo` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `Nombre` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `Descripcion` varchar(300) CHARACTER SET utf8mb4 NULL,
    `IsActive` tinyint(1) NOT NULL DEFAULT TRUE,
    `IsSystem` tinyint(1) NOT NULL DEFAULT FALSE,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_roles` PRIMARY KEY (`RolId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `session_daily_log_slots` (
    `SlotId` char(36) COLLATE ascii_general_ci NOT NULL,
    `UsuarioId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Date` date NOT NULL,
    `HourSlot` tinyint unsigned NOT NULL,
    `TotalSeconds` int NOT NULL DEFAULT 0,
    `SessionCount` int NOT NULL DEFAULT 0,
    `LastSnapshotAt` datetime(6) NOT NULL,
    CONSTRAINT `PK_session_daily_log_slots` PRIMARY KEY (`SlotId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `system_modes` (
    `SystemModeId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Mode` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `IsEnabled` tinyint(1) NOT NULL DEFAULT FALSE,
    `Message` varchar(500) CHARACTER SET utf8mb4 NULL,
    `StartAt` datetime(6) NULL,
    `EndAt` datetime(6) NULL,
    `SelectedKey` varchar(10) CHARACTER SET utf8mb4 NULL,
    `ModeCategory` varchar(50) CHARACTER SET utf8mb4 NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_system_modes` PRIMARY KEY (`SystemModeId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `offices` (
    `OficinaId` char(36) COLLATE ascii_general_ci NOT NULL,
    `OrganizacionId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Codigo` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `Nombre` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `Direccion` varchar(300) CHARACTER SET utf8mb4 NULL,
    `Provincia` varchar(100) CHARACTER SET utf8mb4 NULL,
    `Distrito` varchar(100) CHARACTER SET utf8mb4 NULL,
    `Corregimiento` varchar(100) CHARACTER SET utf8mb4 NULL,
    `Latitude` decimal(10,7) NULL,
    `Longitude` decimal(10,7) NULL,
    `OperationalStatus` varchar(50) CHARACTER SET utf8mb4 NOT NULL DEFAULT 'Operational',
    `MaintenanceMessage` varchar(500) CHARACTER SET utf8mb4 NULL,
    `CodigoMaestro` varchar(50) CHARACTER SET utf8mb4 NULL,
    `IsActive` tinyint(1) NOT NULL DEFAULT TRUE,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_offices` PRIMARY KEY (`OficinaId`),
    CONSTRAINT `FK_offices_organizations_OrganizacionId` FOREIGN KEY (`OrganizacionId`) REFERENCES `organizations` (`OrganizacionId`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `role_permissions` (
    `RolPermisoId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `RolId` char(36) COLLATE ascii_general_ci NOT NULL,
    `PermisoId` char(36) COLLATE ascii_general_ci NOT NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_role_permissions` PRIMARY KEY (`RolPermisoId`),
    CONSTRAINT `FK_role_permissions_permissions_PermisoId` FOREIGN KEY (`PermisoId`) REFERENCES `permissions` (`PermisoId`) ON DELETE RESTRICT,
    CONSTRAINT `FK_role_permissions_roles_RolId` FOREIGN KEY (`RolId`) REFERENCES `roles` (`RolId`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `users` (
    `Id` char(36) COLLATE ascii_general_ci NOT NULL,
    `SsoId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `Username` varchar(100) CHARACTER SET utf8mb4 NULL,
    `Email_enc` longblob NULL,
    `Nombres_enc` longblob NOT NULL,
    `Apellidos_enc` longblob NOT NULL,
    `Documento_enc` longblob NULL,
    `Telefono_enc` longblob NULL,
    `OrganizacionId` char(36) COLLATE ascii_general_ci NULL,
    `OficinaId` char(36) COLLATE ascii_general_ci NULL,
    `IsActive` tinyint(1) NOT NULL DEFAULT TRUE,
    `Documento_hash` binary(32) NULL,
    `Email_hash` binary(32) NULL,
    `Telefono_hash` binary(32) NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_users` PRIMARY KEY (`Id`),
    CONSTRAINT `FK_users_offices_OficinaId` FOREIGN KEY (`OficinaId`) REFERENCES `offices` (`OficinaId`) ON DELETE RESTRICT,
    CONSTRAINT `FK_users_organizations_OrganizacionId` FOREIGN KEY (`OrganizacionId`) REFERENCES `organizations` (`OrganizacionId`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `auth_sessions` (
    `SessionId` char(36) COLLATE ascii_general_ci NOT NULL,
    `UserId` char(36) COLLATE ascii_general_ci NOT NULL,
    `SsoId` char(36) COLLATE ascii_general_ci NOT NULL,
    `CreatedAtSession` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `ExpiresAt` datetime(6) NOT NULL,
    `AbsoluteExpiresAt` datetime(6) NOT NULL,
    `RevokedAt` datetime(6) NULL,
    `ClientIp_enc` longblob NULL,
    `UserAgent` varchar(512) CHARACTER SET utf8mb4 NULL,
    `ClientInfo` varchar(256) CHARACTER SET utf8mb4 NULL,
    `SsoAccessToken_enc` longblob NULL,
    `SsoRefreshToken_enc` longblob NULL,
    `SsoTokenExpiresAt` datetime(6) NULL,
    `TokenVersion` int NOT NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_auth_sessions` PRIMARY KEY (`SessionId`),
    CONSTRAINT `FK_auth_sessions_users_UserId` FOREIGN KEY (`UserId`) REFERENCES `users` (`Id`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `orders` (
    `DeliveryOrderId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Status` tinyint unsigned NOT NULL,
    `Flags` int NOT NULL,
    `IsDebug` tinyint(1) NOT NULL,
    `SystemDebugMode` varchar(50) CHARACTER SET utf8mb4 NULL,
    `Attempts` int NOT NULL,
    `RequestedAt` datetime(6) NOT NULL,
    `FirstOpenedAt` datetime(6) NULL,
    `StartedAt` datetime(6) NULL,
    `BiometryStartedAt` datetime(6) NULL,
    `BiometryCompletedAt` datetime(6) NULL,
    `BiometryOutcome` tinyint unsigned NOT NULL DEFAULT 0,
    `BiometryLastAttemptAt` datetime(6) NULL,
    `BiometryRejectionCode` varchar(64) CHARACTER SET utf8mb4 NULL,
    `CompletedAt` datetime(6) NULL,
    `CanceledAt` datetime(6) NULL,
    `ReceiverSelectedAt` datetime(6) NULL,
    `ImageSavedAt` datetime(6) NULL,
    `Latitude` decimal(18,8) NULL,
    `Longitude` decimal(18,8) NULL,
    `AccuracyMeters` decimal(10,2) NULL,
    `IsLocationEstimated` tinyint(1) NOT NULL DEFAULT FALSE,
    `OrganizationId` char(36) COLLATE ascii_general_ci NULL,
    `OfficeId` char(36) COLLATE ascii_general_ci NULL,
    `DeliveredByUserId` char(36) COLLATE ascii_general_ci NULL,
    `DeliveredByDocument_enc` longblob NULL,
    `RequestedByUserId` char(36) COLLATE ascii_general_ci NULL,
    `RequestedByDocument_enc` longblob NULL,
    `OrderRequestCacheKey` varchar(200) CHARACTER SET utf8mb4 NULL,
    `ReferenceCode` varchar(50) CHARACTER SET utf8mb4 NULL,
    `TribunalOfficeCode` varchar(50) CHARACTER SET utf8mb4 NULL,
    `CitizenNationalId_enc` longblob NOT NULL,
    `CitizenSerialNumber_enc` longblob NOT NULL,
    `Nationality` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `Address_enc` longblob NOT NULL,
    `Province` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `Description` varchar(300) CHARACTER SET utf8mb4 NOT NULL,
    `Sex` varchar(20) CHARACTER SET utf8mb4 NOT NULL,
    `RangeAge` varchar(20) CHARACTER SET utf8mb4 NOT NULL,
    `IsJuvenile` tinyint(1) NOT NULL,
    `CitizenAge` int NULL,
    `CommentRejected` varchar(500) CHARACTER SET utf8mb4 NULL,
    `CommentDelivered` varchar(500) CHARACTER SET utf8mb4 NULL,
    `row_version` timestamp(6) NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `CitizenNationalId_hash` binary(32) NULL,
    `CitizenSerialNumber_hash` binary(32) NULL,
    `DeliveredByDocument_hash` binary(32) NULL,
    `RequestedByDocument_hash` binary(32) NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_orders` PRIMARY KEY (`DeliveryOrderId`),
    CONSTRAINT `FK_orders_offices_OfficeId` FOREIGN KEY (`OfficeId`) REFERENCES `offices` (`OficinaId`) ON DELETE RESTRICT,
    CONSTRAINT `FK_orders_organizations_OrganizationId` FOREIGN KEY (`OrganizationId`) REFERENCES `organizations` (`OrganizacionId`) ON DELETE RESTRICT,
    CONSTRAINT `FK_orders_users_DeliveredByUserId` FOREIGN KEY (`DeliveredByUserId`) REFERENCES `users` (`Id`) ON DELETE RESTRICT,
    CONSTRAINT `FK_orders_users_RequestedByUserId` FOREIGN KEY (`RequestedByUserId`) REFERENCES `users` (`Id`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `session_daily_logs` (
    `SessionDailyLogId` char(36) COLLATE ascii_general_ci NOT NULL,
    `UsuarioId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Date` date NOT NULL,
    `TotalSeconds` int NOT NULL DEFAULT 0,
    `SessionCount` int NOT NULL DEFAULT 0,
    `LastSnapshotAt` datetime(6) NOT NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_session_daily_logs` PRIMARY KEY (`SessionDailyLogId`),
    CONSTRAINT `FK_session_daily_logs_users_UsuarioId` FOREIGN KEY (`UsuarioId`) REFERENCES `users` (`Id`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `user_roles` (
    `UsuarioRolId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `UserId` char(36) COLLATE ascii_general_ci NOT NULL,
    `RolId` char(36) COLLATE ascii_general_ci NOT NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_user_roles` PRIMARY KEY (`UsuarioRolId`),
    CONSTRAINT `FK_user_roles_roles_RolId` FOREIGN KEY (`RolId`) REFERENCES `roles` (`RolId`) ON DELETE RESTRICT,
    CONSTRAINT `FK_user_roles_users_UserId` FOREIGN KEY (`UserId`) REFERENCES `users` (`Id`) ON DELETE CASCADE
) CHARACTER SET=utf8mb4;

CREATE TABLE `user_sessions` (
    `UsuarioSesionId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `UsuarioId` char(36) COLLATE ascii_general_ci NULL,
    `ConnectionId` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `StartedAt` datetime(6) NOT NULL,
    `LastSeenAt` datetime(6) NOT NULL,
    `EndedAt` datetime(6) NULL,
    `EndReason` varchar(120) CHARACTER SET utf8mb4 NULL,
    `ClientIp_enc` longblob NULL,
    `UserAgent` varchar(256) CHARACTER SET utf8mb4 NULL,
    `Latitude` decimal(10,7) NULL,
    `Longitude` decimal(10,7) NULL,
    `GeoSource` varchar(50) CHARACTER SET utf8mb4 NULL,
    `GeoResolvedAt` datetime(6) NULL,
    `GeoAccuracyKm` int NULL,
    `IsActive` tinyint(1) NOT NULL DEFAULT TRUE,
    `TotalSeconds` int NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL,
    CONSTRAINT `PK_user_sessions` PRIMARY KEY (`UsuarioSesionId`),
    CONSTRAINT `FK_user_sessions_users_UsuarioId` FOREIGN KEY (`UsuarioId`) REFERENCES `users` (`Id`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `order_access_logs` (
    `DeliveryOrderAccessLogId` char(36) COLLATE ascii_general_ci NOT NULL,
    `DeliveryOrderId` char(36) COLLATE ascii_general_ci NULL,
    `OfficialNationalId` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `AccessType` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `Source` varchar(100) CHARACTER SET utf8mb4 NULL,
    `AccessedAt` datetime(6) NOT NULL,
    `Period` varchar(7) CHARACTER SET utf8mb4 NOT NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL,
    CONSTRAINT `PK_order_access_logs` PRIMARY KEY (`DeliveryOrderAccessLogId`),
    CONSTRAINT `FK_order_access_logs_orders_DeliveryOrderId` FOREIGN KEY (`DeliveryOrderId`) REFERENCES `orders` (`DeliveryOrderId`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `order_evidences` (
    `DeliveryOrderEvidenceId` char(36) COLLATE ascii_general_ci NOT NULL,
    `DeliveryOrderId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Type` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `FilePath` varchar(500) CHARACTER SET utf8mb4 NOT NULL,
    `OriginalName` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `SequentialName` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `CapturedAt` datetime(6) NOT NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_order_evidences` PRIMARY KEY (`DeliveryOrderEvidenceId`),
    CONSTRAINT `FK_order_evidences_orders_DeliveryOrderId` FOREIGN KEY (`DeliveryOrderId`) REFERENCES `orders` (`DeliveryOrderId`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `order_receivers` (
    `DeliveryOrderReceiverId` char(36) COLLATE ascii_general_ci NOT NULL,
    `DeliveryOrderId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Name_enc` longblob NOT NULL,
    `Role` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `Identification_enc` longblob NOT NULL,
    `Type` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `Relationship` longtext CHARACTER SET utf8mb4 NULL,
    `IsSelected` tinyint(1) NOT NULL,
    `SelectedAt` datetime(6) NULL,
    `Identification_hash` binary(32) NULL,
    `Name_hash` binary(32) NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_order_receivers` PRIMARY KEY (`DeliveryOrderReceiverId`),
    CONSTRAINT `FK_order_receivers_orders_DeliveryOrderId` FOREIGN KEY (`DeliveryOrderId`) REFERENCES `orders` (`DeliveryOrderId`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE INDEX `IX_audit_entries_ActorId_Timestamp` ON `audit_entries` (`ActorId`, `Timestamp`);

CREATE INDEX `IX_audit_entries_EntityType` ON `audit_entries` (`EntityType`);

CREATE INDEX `IX_audit_entries_Period` ON `audit_entries` (`Period`);

CREATE INDEX `IX_audit_entries_Period_Timestamp` ON `audit_entries` (`Period`, `Timestamp`);

CREATE INDEX `IX_audit_entries_Timestamp` ON `audit_entries` (`Timestamp` DESC);

CREATE UNIQUE INDEX `IX_audit_entry_archives_OriginalAuditEntryId` ON `audit_entry_archives` (`OriginalAuditEntryId`);

CREATE INDEX `IX_audit_entry_archives_Period` ON `audit_entry_archives` (`Period`);

CREATE INDEX `IX_AuthSession_ExpiresAt_IsDeleted` ON `auth_sessions` (`ExpiresAt`, `IsDeleted`);

CREATE INDEX `IX_AuthSession_RevokedAt` ON `auth_sessions` (`RevokedAt`);

CREATE INDEX `IX_AuthSession_SsoId` ON `auth_sessions` (`SsoId`);

CREATE INDEX `IX_AuthSession_UserId_IsDeleted_RevokedAt_ExpiresAt` ON `auth_sessions` (`UserId`, `IsDeleted`, `RevokedAt`, `ExpiresAt`);

CREATE INDEX `IX_AuthSession_UserId_RevokedAt` ON `auth_sessions` (`UserId`, `RevokedAt`);

CREATE UNIQUE INDEX `IX_offices_OrganizacionId_Codigo` ON `offices` (`OrganizacionId`, `Codigo`);

CREATE UNIQUE INDEX `IX_order_access_log_archives_OriginalDeliveryOrderAccessLogId` ON `order_access_log_archives` (`OriginalDeliveryOrderAccessLogId`);

CREATE INDEX `IX_order_access_log_archives_Period` ON `order_access_log_archives` (`Period`);

CREATE INDEX `IX_order_access_logs_AccessedAt` ON `order_access_logs` (`AccessedAt`);

CREATE INDEX `IX_order_access_logs_DeliveryOrderId` ON `order_access_logs` (`DeliveryOrderId`);

CREATE INDEX `IX_order_access_logs_OfficialNationalId` ON `order_access_logs` (`OfficialNationalId`);

CREATE INDEX `IX_order_access_logs_Period` ON `order_access_logs` (`Period`);

CREATE INDEX `IX_order_access_logs_Period_AccessedAt` ON `order_access_logs` (`Period`, `AccessedAt`);

CREATE INDEX `IX_order_evidences_DeliveryOrderId` ON `order_evidences` (`DeliveryOrderId`);

CREATE INDEX `IX_order_evidences_Type` ON `order_evidences` (`Type`);

CREATE INDEX `IX_order_receivers_DeliveryOrderId` ON `order_receivers` (`DeliveryOrderId`);

CREATE INDEX `IX_order_receivers_Identification_hash` ON `order_receivers` (`Identification_hash`);

CREATE INDEX `IX_order_receivers_Name_hash` ON `order_receivers` (`Name_hash`);

CREATE INDEX `IX_orders_CitizenNationalId_hash` ON `orders` (`CitizenNationalId_hash`);

CREATE INDEX `IX_orders_CitizenNationalId_hash_Status` ON `orders` (`CitizenNationalId_hash`, `Status`);

CREATE INDEX `IX_orders_CitizenSerialNumber_hash` ON `orders` (`CitizenSerialNumber_hash`);

CREATE INDEX `IX_orders_CompletedAt_IsDeleted` ON `orders` (`CompletedAt`, `IsDeleted`);

CREATE INDEX `IX_orders_CreatedAt_DeliveredByUserId` ON `orders` (`CreatedAt`, `DeliveredByUserId`);

CREATE INDEX `IX_orders_CreatedAt_OfficeId` ON `orders` (`CreatedAt`, `OfficeId`);

CREATE INDEX `IX_orders_DeliveredByDocument_hash` ON `orders` (`DeliveredByDocument_hash`);

CREATE INDEX `IX_orders_DeliveredByUserId` ON `orders` (`DeliveredByUserId`);

CREATE INDEX `IX_orders_DeliveredByUserId_Status` ON `orders` (`DeliveredByUserId`, `Status`);

CREATE INDEX `IX_orders_OfficeId` ON `orders` (`OfficeId`);

CREATE INDEX `IX_orders_OfficeId_CreatedAt` ON `orders` (`OfficeId`, `CreatedAt`);

CREATE INDEX `IX_orders_OrganizationId` ON `orders` (`OrganizationId`);

CREATE INDEX `IX_orders_ReferenceCode` ON `orders` (`ReferenceCode`);

CREATE INDEX `IX_orders_RequestedByDocument_hash` ON `orders` (`RequestedByDocument_hash`);

CREATE INDEX `IX_orders_RequestedByUserId` ON `orders` (`RequestedByUserId`);

CREATE INDEX `IX_orders_Status_RequestedAt` ON `orders` (`Status`, `RequestedAt`);

CREATE UNIQUE INDEX `IX_organizations_Codigo` ON `organizations` (`Codigo`);

CREATE UNIQUE INDEX `IX_permissions_Codigo` ON `permissions` (`Codigo`);

CREATE INDEX `IX_role_permissions_PermisoId` ON `role_permissions` (`PermisoId`);

CREATE UNIQUE INDEX `IX_role_permissions_RolId_PermisoId` ON `role_permissions` (`RolId`, `PermisoId`);

CREATE UNIQUE INDEX `IX_roles_Codigo` ON `roles` (`Codigo`);

CREATE INDEX `IX_session_daily_log_slots_Date` ON `session_daily_log_slots` (`Date`);

CREATE INDEX `IX_session_daily_log_slots_UsuarioId_Date` ON `session_daily_log_slots` (`UsuarioId`, `Date`);

CREATE UNIQUE INDEX `IX_session_daily_log_slots_UsuarioId_Date_HourSlot` ON `session_daily_log_slots` (`UsuarioId`, `Date`, `HourSlot`);

CREATE INDEX `IX_session_daily_logs_Date` ON `session_daily_logs` (`Date`);

CREATE UNIQUE INDEX `IX_session_daily_logs_UsuarioId_Date` ON `session_daily_logs` (`UsuarioId`, `Date`);

CREATE INDEX `IX_system_modes_IsEnabled` ON `system_modes` (`IsEnabled`);

CREATE INDEX `IX_system_modes_Mode` ON `system_modes` (`Mode`);

ALTER TABLE `system_modes` ADD COLUMN `ActiveMode` varchar(50) GENERATED ALWAYS AS (case when `IsDeleted` = 0 then `Mode` else null end) STORED;

CREATE UNIQUE INDEX `UX_system_modes_ActiveMode` ON `system_modes` (`ActiveMode`);

CREATE INDEX `IX_user_roles_RolId` ON `user_roles` (`RolId`);

CREATE UNIQUE INDEX `IX_user_roles_UserId_RolId` ON `user_roles` (`UserId`, `RolId`);

CREATE UNIQUE INDEX `IX_user_sessions_ConnectionId` ON `user_sessions` (`ConnectionId`);

CREATE INDEX `IX_user_sessions_IsActive` ON `user_sessions` (`IsActive`);

CREATE INDEX `IX_user_sessions_UsuarioId` ON `user_sessions` (`UsuarioId`);

CREATE INDEX `IX_user_sessions_UsuarioId_IsActive` ON `user_sessions` (`UsuarioId`, `IsActive`);

CREATE INDEX `IX_users_Documento_hash` ON `users` (`Documento_hash`);

CREATE UNIQUE INDEX `IX_users_Email_hash` ON `users` (`Email_hash`);

CREATE INDEX `IX_users_OficinaId` ON `users` (`OficinaId`);

CREATE INDEX `IX_users_OrganizacionId` ON `users` (`OrganizacionId`);

CREATE UNIQUE INDEX `IX_users_SsoId` ON `users` (`SsoId`);

CREATE INDEX `IX_users_Telefono_hash` ON `users` (`Telefono_hash`);

CREATE UNIQUE INDEX `IX_users_Username` ON `users` (`Username`);

INSERT INTO `__EFMigrationsHistory` (`MigrationId`, `ProductVersion`)
VALUES ('20261018012052_Initial', '9.0.11');

COMMIT;
CREATE TABLE IF NOT EXISTS `__EFMigrationsHistory` (
    `MigrationId` varchar(150) CHARACTER SET utf8mb4 NOT NULL,
    `ProductVersion` varchar(32) CHARACTER SET utf8mb4 NOT NULL,
    CONSTRAINT `PK___EFMigrationsHistory` PRIMARY KEY (`MigrationId`)
) CHARACTER SET=utf8mb4;

START TRANSACTION;
ALTER DATABASE CHARACTER SET utf8mb4;

CREATE TABLE `audit_entries` (
    `AuditEntryId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Timestamp` datetime(6) NOT NULL,
    `ActorId` varchar(50) CHARACTER SET utf8mb4 NULL,
    `Action` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `EntityType` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `EntityId` varchar(200) CHARACTER SET utf8mb4 NULL,
    `Description` varchar(500) CHARACTER SET utf8mb4 NULL,
    `IpAddress_enc` longblob NULL,
    `TraceId` varchar(100) CHARACTER SET utf8mb4 NULL,
    `Metadata` longtext CHARACTER SET utf8mb4 NULL,
    `Period` varchar(7) CHARACTER SET utf8mb4 NOT NULL,
    CONSTRAINT `PK_audit_entries` PRIMARY KEY (`AuditEntryId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `audit_entry_archives` (
    `AuditEntryArchiveId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `OriginalAuditEntryId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `Timestamp` datetime(6) NOT NULL,
    `ActorId` longtext CHARACTER SET utf8mb4 NULL,
    `Action` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `EntityType` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `EntityId` longtext CHARACTER SET utf8mb4 NULL,
    `Description` longtext CHARACTER SET utf8mb4 NULL,
    `IpAddress` longtext CHARACTER SET utf8mb4 NULL,
    `TraceId` longtext CHARACTER SET utf8mb4 NULL,
    `Metadata` longtext CHARACTER SET utf8mb4 NULL,
    `Period` varchar(7) CHARACTER SET utf8mb4 NOT NULL,
    `ArchivedAt` datetime(6) NOT NULL,
    CONSTRAINT `PK_audit_entry_archives` PRIMARY KEY (`AuditEntryArchiveId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `DataProtectionKeys` (
    `Id` int NOT NULL AUTO_INCREMENT,
    `FriendlyName` longtext CHARACTER SET utf8mb4 NULL,
    `Xml` longtext CHARACTER SET utf8mb4 NULL,
    CONSTRAINT `PK_DataProtectionKeys` PRIMARY KEY (`Id`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `order_access_log_archives` (
    `DeliveryOrderAccessLogArchiveId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `OriginalDeliveryOrderAccessLogId` char(36) COLLATE ascii_general_ci NOT NULL,
    `DeliveryOrderId` char(36) COLLATE ascii_general_ci NOT NULL,
    `OfficialNationalId` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `AccessType` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `Source` longtext CHARACTER SET utf8mb4 NULL,
    `AccessedAt` datetime(6) NOT NULL,
    `Period` varchar(7) CHARACTER SET utf8mb4 NOT NULL,
    `ArchivedAt` datetime(6) NOT NULL,
    CONSTRAINT `PK_order_access_log_archives` PRIMARY KEY (`DeliveryOrderAccessLogArchiveId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `organizations` (
    `OrganizacionId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Codigo` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `Nombre` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `IsOperational` tinyint(1) NOT NULL DEFAULT TRUE,
    `IsInMaintenance` tinyint(1) NOT NULL DEFAULT FALSE,
    `MaintenanceMessage` varchar(500) CHARACTER SET utf8mb4 NULL,
    `IsActive` tinyint(1) NOT NULL DEFAULT TRUE,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_organizations` PRIMARY KEY (`OrganizacionId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `permissions` (
    `PermisoId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Codigo` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `Nombre` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `Descripcion` varchar(300) CHARACTER SET utf8mb4 NULL,
    `IsActive` tinyint(1) NOT NULL DEFAULT TRUE,
    `IsSystem` tinyint(1) NOT NULL DEFAULT FALSE,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_permissions` PRIMARY KEY (`PermisoId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `roles` (
    `RolId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Codigo` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `Nombre` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `Descripcion` varchar(300) CHARACTER SET utf8mb4 NULL,
    `IsActive` tinyint(1) NOT NULL DEFAULT TRUE,
    `IsSystem` tinyint(1) NOT NULL DEFAULT FALSE,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_roles` PRIMARY KEY (`RolId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `session_daily_log_slots` (
    `SlotId` char(36) COLLATE ascii_general_ci NOT NULL,
    `UsuarioId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Date` date NOT NULL,
    `HourSlot` tinyint unsigned NOT NULL,
    `TotalSeconds` int NOT NULL DEFAULT 0,
    `SessionCount` int NOT NULL DEFAULT 0,
    `LastSnapshotAt` datetime(6) NOT NULL,
    CONSTRAINT `PK_session_daily_log_slots` PRIMARY KEY (`SlotId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `system_modes` (
    `SystemModeId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Mode` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `IsEnabled` tinyint(1) NOT NULL DEFAULT FALSE,
    `Message` varchar(500) CHARACTER SET utf8mb4 NULL,
    `StartAt` datetime(6) NULL,
    `EndAt` datetime(6) NULL,
    `SelectedKey` varchar(10) CHARACTER SET utf8mb4 NULL,
    `ModeCategory` varchar(50) CHARACTER SET utf8mb4 NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_system_modes` PRIMARY KEY (`SystemModeId`)
) CHARACTER SET=utf8mb4;

CREATE TABLE `offices` (
    `OficinaId` char(36) COLLATE ascii_general_ci NOT NULL,
    `OrganizacionId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Codigo` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `Nombre` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `Direccion` varchar(300) CHARACTER SET utf8mb4 NULL,
    `Provincia` varchar(100) CHARACTER SET utf8mb4 NULL,
    `Distrito` varchar(100) CHARACTER SET utf8mb4 NULL,
    `Corregimiento` varchar(100) CHARACTER SET utf8mb4 NULL,
    `Latitude` decimal(10,7) NULL,
    `Longitude` decimal(10,7) NULL,
    `OperationalStatus` varchar(50) CHARACTER SET utf8mb4 NOT NULL DEFAULT 'Operational',
    `MaintenanceMessage` varchar(500) CHARACTER SET utf8mb4 NULL,
    `CodigoMaestro` varchar(50) CHARACTER SET utf8mb4 NULL,
    `IsActive` tinyint(1) NOT NULL DEFAULT TRUE,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_offices` PRIMARY KEY (`OficinaId`),
    CONSTRAINT `FK_offices_organizations_OrganizacionId` FOREIGN KEY (`OrganizacionId`) REFERENCES `organizations` (`OrganizacionId`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `role_permissions` (
    `RolPermisoId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `RolId` char(36) COLLATE ascii_general_ci NOT NULL,
    `PermisoId` char(36) COLLATE ascii_general_ci NOT NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_role_permissions` PRIMARY KEY (`RolPermisoId`),
    CONSTRAINT `FK_role_permissions_permissions_PermisoId` FOREIGN KEY (`PermisoId`) REFERENCES `permissions` (`PermisoId`) ON DELETE RESTRICT,
    CONSTRAINT `FK_role_permissions_roles_RolId` FOREIGN KEY (`RolId`) REFERENCES `roles` (`RolId`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `users` (
    `Id` char(36) COLLATE ascii_general_ci NOT NULL,
    `SsoId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `Username` varchar(100) CHARACTER SET utf8mb4 NULL,
    `Email_enc` longblob NULL,
    `Nombres_enc` longblob NOT NULL,
    `Apellidos_enc` longblob NOT NULL,
    `Documento_enc` longblob NULL,
    `Telefono_enc` longblob NULL,
    `OrganizacionId` char(36) COLLATE ascii_general_ci NULL,
    `OficinaId` char(36) COLLATE ascii_general_ci NULL,
    `IsActive` tinyint(1) NOT NULL DEFAULT TRUE,
    `Documento_hash` binary(32) NULL,
    `Email_hash` binary(32) NULL,
    `Telefono_hash` binary(32) NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_users` PRIMARY KEY (`Id`),
    CONSTRAINT `FK_users_offices_OficinaId` FOREIGN KEY (`OficinaId`) REFERENCES `offices` (`OficinaId`) ON DELETE RESTRICT,
    CONSTRAINT `FK_users_organizations_OrganizacionId` FOREIGN KEY (`OrganizacionId`) REFERENCES `organizations` (`OrganizacionId`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `auth_sessions` (
    `SessionId` char(36) COLLATE ascii_general_ci NOT NULL,
    `UserId` char(36) COLLATE ascii_general_ci NOT NULL,
    `SsoId` char(36) COLLATE ascii_general_ci NOT NULL,
    `CreatedAtSession` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `ExpiresAt` datetime(6) NOT NULL,
    `AbsoluteExpiresAt` datetime(6) NOT NULL,
    `RevokedAt` datetime(6) NULL,
    `ClientIp_enc` longblob NULL,
    `UserAgent` varchar(512) CHARACTER SET utf8mb4 NULL,
    `ClientInfo` varchar(256) CHARACTER SET utf8mb4 NULL,
    `SsoAccessToken_enc` longblob NULL,
    `SsoRefreshToken_enc` longblob NULL,
    `SsoTokenExpiresAt` datetime(6) NULL,
    `TokenVersion` int NOT NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_auth_sessions` PRIMARY KEY (`SessionId`),
    CONSTRAINT `FK_auth_sessions_users_UserId` FOREIGN KEY (`UserId`) REFERENCES `users` (`Id`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `orders` (
    `DeliveryOrderId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Status` tinyint unsigned NOT NULL,
    `Flags` int NOT NULL,
    `IsDebug` tinyint(1) NOT NULL,
    `SystemDebugMode` varchar(50) CHARACTER SET utf8mb4 NULL,
    `Attempts` int NOT NULL,
    `RequestedAt` datetime(6) NOT NULL,
    `FirstOpenedAt` datetime(6) NULL,
    `StartedAt` datetime(6) NULL,
    `BiometryStartedAt` datetime(6) NULL,
    `BiometryCompletedAt` datetime(6) NULL,
    `BiometryOutcome` tinyint unsigned NOT NULL DEFAULT 0,
    `BiometryLastAttemptAt` datetime(6) NULL,
    `BiometryRejectionCode` varchar(64) CHARACTER SET utf8mb4 NULL,
    `CompletedAt` datetime(6) NULL,
    `CanceledAt` datetime(6) NULL,
    `ReceiverSelectedAt` datetime(6) NULL,
    `ImageSavedAt` datetime(6) NULL,
    `Latitude` decimal(18,8) NULL,
    `Longitude` decimal(18,8) NULL,
    `AccuracyMeters` decimal(10,2) NULL,
    `IsLocationEstimated` tinyint(1) NOT NULL DEFAULT FALSE,
    `OrganizationId` char(36) COLLATE ascii_general_ci NULL,
    `OfficeId` char(36) COLLATE ascii_general_ci NULL,
    `DeliveredByUserId` char(36) COLLATE ascii_general_ci NULL,
    `DeliveredByDocument_enc` longblob NULL,
    `RequestedByUserId` char(36) COLLATE ascii_general_ci NULL,
    `RequestedByDocument_enc` longblob NULL,
    `OrderRequestCacheKey` varchar(200) CHARACTER SET utf8mb4 NULL,
    `ReferenceCode` varchar(50) CHARACTER SET utf8mb4 NULL,
    `TribunalOfficeCode` varchar(50) CHARACTER SET utf8mb4 NULL,
    `CitizenNationalId_enc` longblob NOT NULL,
    `CitizenSerialNumber_enc` longblob NOT NULL,
    `Nationality` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `Address_enc` longblob NOT NULL,
    `Province` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `Description` varchar(300) CHARACTER SET utf8mb4 NOT NULL,
    `Sex` varchar(20) CHARACTER SET utf8mb4 NOT NULL,
    `RangeAge` varchar(20) CHARACTER SET utf8mb4 NOT NULL,
    `IsJuvenile` tinyint(1) NOT NULL,
    `CitizenAge` int NULL,
    `CommentRejected` varchar(500) CHARACTER SET utf8mb4 NULL,
    `CommentDelivered` varchar(500) CHARACTER SET utf8mb4 NULL,
    `row_version` timestamp(6) NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `CitizenNationalId_hash` binary(32) NULL,
    `CitizenSerialNumber_hash` binary(32) NULL,
    `DeliveredByDocument_hash` binary(32) NULL,
    `RequestedByDocument_hash` binary(32) NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_orders` PRIMARY KEY (`DeliveryOrderId`),
    CONSTRAINT `FK_orders_offices_OfficeId` FOREIGN KEY (`OfficeId`) REFERENCES `offices` (`OficinaId`) ON DELETE RESTRICT,
    CONSTRAINT `FK_orders_organizations_OrganizationId` FOREIGN KEY (`OrganizationId`) REFERENCES `organizations` (`OrganizacionId`) ON DELETE RESTRICT,
    CONSTRAINT `FK_orders_users_DeliveredByUserId` FOREIGN KEY (`DeliveredByUserId`) REFERENCES `users` (`Id`) ON DELETE RESTRICT,
    CONSTRAINT `FK_orders_users_RequestedByUserId` FOREIGN KEY (`RequestedByUserId`) REFERENCES `users` (`Id`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `session_daily_logs` (
    `SessionDailyLogId` char(36) COLLATE ascii_general_ci NOT NULL,
    `UsuarioId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Date` date NOT NULL,
    `TotalSeconds` int NOT NULL DEFAULT 0,
    `SessionCount` int NOT NULL DEFAULT 0,
    `LastSnapshotAt` datetime(6) NOT NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_session_daily_logs` PRIMARY KEY (`SessionDailyLogId`),
    CONSTRAINT `FK_session_daily_logs_users_UsuarioId` FOREIGN KEY (`UsuarioId`) REFERENCES `users` (`Id`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `user_roles` (
    `UsuarioRolId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `UserId` char(36) COLLATE ascii_general_ci NOT NULL,
    `RolId` char(36) COLLATE ascii_general_ci NOT NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_user_roles` PRIMARY KEY (`UsuarioRolId`),
    CONSTRAINT `FK_user_roles_roles_RolId` FOREIGN KEY (`RolId`) REFERENCES `roles` (`RolId`) ON DELETE RESTRICT,
    CONSTRAINT `FK_user_roles_users_UserId` FOREIGN KEY (`UserId`) REFERENCES `users` (`Id`) ON DELETE CASCADE
) CHARACTER SET=utf8mb4;

CREATE TABLE `user_sessions` (
    `UsuarioSesionId` varchar(255) CHARACTER SET utf8mb4 NOT NULL,
    `UsuarioId` char(36) COLLATE ascii_general_ci NULL,
    `ConnectionId` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `StartedAt` datetime(6) NOT NULL,
    `LastSeenAt` datetime(6) NOT NULL,
    `EndedAt` datetime(6) NULL,
    `EndReason` varchar(120) CHARACTER SET utf8mb4 NULL,
    `ClientIp_enc` longblob NULL,
    `UserAgent` varchar(256) CHARACTER SET utf8mb4 NULL,
    `Latitude` decimal(10,7) NULL,
    `Longitude` decimal(10,7) NULL,
    `GeoSource` varchar(50) CHARACTER SET utf8mb4 NULL,
    `GeoResolvedAt` datetime(6) NULL,
    `GeoAccuracyKm` int NULL,
    `IsActive` tinyint(1) NOT NULL DEFAULT TRUE,
    `TotalSeconds` int NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL,
    CONSTRAINT `PK_user_sessions` PRIMARY KEY (`UsuarioSesionId`),
    CONSTRAINT `FK_user_sessions_users_UsuarioId` FOREIGN KEY (`UsuarioId`) REFERENCES `users` (`Id`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `order_access_logs` (
    `DeliveryOrderAccessLogId` char(36) COLLATE ascii_general_ci NOT NULL,
    `DeliveryOrderId` char(36) COLLATE ascii_general_ci NULL,
    `OfficialNationalId` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `AccessType` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `Source` varchar(100) CHARACTER SET utf8mb4 NULL,
    `AccessedAt` datetime(6) NOT NULL,
    `Period` varchar(7) CHARACTER SET utf8mb4 NOT NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL,
    CONSTRAINT `PK_order_access_logs` PRIMARY KEY (`DeliveryOrderAccessLogId`),
    CONSTRAINT `FK_order_access_logs_orders_DeliveryOrderId` FOREIGN KEY (`DeliveryOrderId`) REFERENCES `orders` (`DeliveryOrderId`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `order_evidences` (
    `DeliveryOrderEvidenceId` char(36) COLLATE ascii_general_ci NOT NULL,
    `DeliveryOrderId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Type` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `FilePath` varchar(500) CHARACTER SET utf8mb4 NOT NULL,
    `OriginalName` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `SequentialName` varchar(200) CHARACTER SET utf8mb4 NOT NULL,
    `CapturedAt` datetime(6) NOT NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_order_evidences` PRIMARY KEY (`DeliveryOrderEvidenceId`),
    CONSTRAINT `FK_order_evidences_orders_DeliveryOrderId` FOREIGN KEY (`DeliveryOrderId`) REFERENCES `orders` (`DeliveryOrderId`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE TABLE `order_receivers` (
    `DeliveryOrderReceiverId` char(36) COLLATE ascii_general_ci NOT NULL,
    `DeliveryOrderId` char(36) COLLATE ascii_general_ci NOT NULL,
    `Name_enc` longblob NOT NULL,
    `Role` varchar(100) CHARACTER SET utf8mb4 NOT NULL,
    `Identification_enc` longblob NOT NULL,
    `Type` varchar(50) CHARACTER SET utf8mb4 NOT NULL,
    `Relationship` longtext CHARACTER SET utf8mb4 NULL,
    `IsSelected` tinyint(1) NOT NULL,
    `SelectedAt` datetime(6) NULL,
    `Identification_hash` binary(32) NULL,
    `CreatedAt` datetime(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    `CreatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `UpdatedAt` datetime(6) NULL,
    `UpdatedBy` longtext CHARACTER SET utf8mb4 NULL,
    `DeletedAt` datetime(6) NULL,
    `DeletedBy` longtext CHARACTER SET utf8mb4 NULL,
    `IsDeleted` tinyint(1) NOT NULL DEFAULT FALSE,
    CONSTRAINT `PK_order_receivers` PRIMARY KEY (`DeliveryOrderReceiverId`),
    CONSTRAINT `FK_order_receivers_orders_DeliveryOrderId` FOREIGN KEY (`DeliveryOrderId`) REFERENCES `orders` (`DeliveryOrderId`) ON DELETE RESTRICT
) CHARACTER SET=utf8mb4;

CREATE INDEX `IX_audit_entries_ActorId_Timestamp` ON `audit_entries` (`ActorId`, `Timestamp`);

CREATE INDEX `IX_audit_entries_EntityType` ON `audit_entries` (`EntityType`);

CREATE INDEX `IX_audit_entries_Period` ON `audit_entries` (`Period`);

CREATE INDEX `IX_audit_entries_Period_Timestamp` ON `audit_entries` (`Period`, `Timestamp`);

CREATE INDEX `IX_audit_entries_Timestamp` ON `audit_entries` (`Timestamp` DESC);

CREATE UNIQUE INDEX `IX_audit_entry_archives_OriginalAuditEntryId` ON `audit_entry_archives` (`OriginalAuditEntryId`);

CREATE INDEX `IX_audit_entry_archives_Period` ON `audit_entry_archives` (`Period`);

CREATE INDEX `IX_AuthSession_ExpiresAt_IsDeleted` ON `auth_sessions` (`ExpiresAt`, `IsDeleted`);

CREATE INDEX `IX_AuthSession_RevokedAt` ON `auth_sessions` (`RevokedAt`);

CREATE INDEX `IX_AuthSession_SsoId` ON `auth_sessions` (`SsoId`);

CREATE INDEX `IX_AuthSession_UserId_IsDeleted_RevokedAt_ExpiresAt` ON `auth_sessions` (`UserId`, `IsDeleted`, `RevokedAt`, `ExpiresAt`);

CREATE INDEX `IX_AuthSession_UserId_RevokedAt` ON `auth_sessions` (`UserId`, `RevokedAt`);

CREATE UNIQUE INDEX `IX_offices_OrganizacionId_Codigo` ON `offices` (`OrganizacionId`, `Codigo`);

CREATE UNIQUE INDEX `IX_order_access_log_archives_OriginalDeliveryOrderAccessLogId` ON `order_access_log_archives` (`OriginalDeliveryOrderAccessLogId`);

CREATE INDEX `IX_order_access_log_archives_Period` ON `order_access_log_archives` (`Period`);

CREATE INDEX `IX_order_access_logs_AccessedAt` ON `order_access_logs` (`AccessedAt`);

CREATE INDEX `IX_order_access_logs_DeliveryOrderId` ON `order_access_logs` (`DeliveryOrderId`);

CREATE INDEX `IX_order_access_logs_OfficialNationalId` ON `order_access_logs` (`OfficialNationalId`);

CREATE INDEX `IX_order_access_logs_Period` ON `order_access_logs` (`Period`);

CREATE INDEX `IX_order_access_logs_Period_AccessedAt` ON `order_access_logs` (`Period`, `AccessedAt`);

CREATE INDEX `IX_order_evidences_DeliveryOrderId` ON `order_evidences` (`DeliveryOrderId`);

CREATE INDEX `IX_order_evidences_Type` ON `order_evidences` (`Type`);

CREATE INDEX `IX_order_receivers_DeliveryOrderId` ON `order_receivers` (`DeliveryOrderId`);

CREATE INDEX `IX_order_receivers_Identification_hash` ON `order_receivers` (`Identification_hash`);

CREATE INDEX `IX_orders_CitizenNationalId_hash` ON `orders` (`CitizenNationalId_hash`);

CREATE INDEX `IX_orders_CitizenNationalId_hash_Status` ON `orders` (`CitizenNationalId_hash`, `Status`);

CREATE INDEX `IX_orders_CitizenSerialNumber_hash` ON `orders` (`CitizenSerialNumber_hash`);

CREATE INDEX `IX_orders_CompletedAt_IsDeleted` ON `orders` (`CompletedAt`, `IsDeleted`);

CREATE INDEX `IX_orders_CreatedAt_DeliveredByUserId` ON `orders` (`CreatedAt`, `DeliveredByUserId`);

CREATE INDEX `IX_orders_CreatedAt_OfficeId` ON `orders` (`CreatedAt`, `OfficeId`);

CREATE INDEX `IX_orders_DeliveredByDocument_hash` ON `orders` (`DeliveredByDocument_hash`);

CREATE INDEX `IX_orders_DeliveredByUserId` ON `orders` (`DeliveredByUserId`);

CREATE INDEX `IX_orders_DeliveredByUserId_Status` ON `orders` (`DeliveredByUserId`, `Status`);

CREATE INDEX `IX_orders_OfficeId` ON `orders` (`OfficeId`);

CREATE INDEX `IX_orders_OfficeId_CreatedAt` ON `orders` (`OfficeId`, `CreatedAt`);

CREATE INDEX `IX_orders_OrganizationId` ON `orders` (`OrganizationId`);

CREATE INDEX `IX_orders_ReferenceCode` ON `orders` (`ReferenceCode`);

ALTER TABLE `orders` ADD COLUMN `ReferenceCode_norm` varchar(50) GENERATED ALWAYS AS (upper(trim(`ReferenceCode`))) STORED;

CREATE INDEX `IX_orders_ReferenceCode_norm` ON `orders` (`ReferenceCode_norm`);

CREATE INDEX `IX_orders_RequestedByDocument_hash` ON `orders` (`RequestedByDocument_hash`);

CREATE INDEX `IX_orders_RequestedByUserId` ON `orders` (`RequestedByUserId`);

CREATE INDEX `IX_orders_Status_RequestedAt` ON `orders` (`Status`, `RequestedAt`);

CREATE UNIQUE INDEX `IX_organizations_Codigo` ON `organizations` (`Codigo`);

CREATE UNIQUE INDEX `IX_permissions_Codigo` ON `permissions` (`Codigo`);

CREATE INDEX `IX_role_permissions_PermisoId` ON `role_permissions` (`PermisoId`);

CREATE UNIQUE INDEX `IX_role_permissions_RolId_PermisoId` ON `role_permissions` (`RolId`, `PermisoId`);

CREATE UNIQUE INDEX `IX_roles_Codigo` ON `roles` (`Codigo`);

CREATE INDEX `IX_session_daily_log_slots_Date` ON `session_daily_log_slots` (`Date`);

CREATE INDEX `IX_session_daily_log_slots_UsuarioId_Date` ON `session_daily_log_slots` (`UsuarioId`, `Date`);

CREATE UNIQUE INDEX `IX_session_daily_log_slots_UsuarioId_Date_HourSlot` ON `session_daily_log_slots` (`UsuarioId`, `Date`, `HourSlot`);

CREATE INDEX `IX_session_daily_logs_Date` ON `session_daily_logs` (`Date`);

CREATE UNIQUE INDEX `IX_session_daily_logs_UsuarioId_Date` ON `session_daily_logs` (`UsuarioId`, `Date`);

CREATE INDEX `IX_system_modes_IsEnabled` ON `system_modes` (`IsEnabled`);

CREATE INDEX `IX_system_modes_Mode` ON `system_modes` (`Mode`);

ALTER TABLE `system_modes` ADD COLUMN `ActiveMode` varchar(50) GENERATED ALWAYS AS (case when `IsDeleted` = 0 then `Mode` else null end) STORED;

CREATE UNIQUE INDEX `UX_system_modes_ActiveMode` ON `system_modes` (`ActiveMode`);

CREATE INDEX `IX_user_roles_RolId` ON `user_roles` (`RolId`);

CREATE UNIQUE INDEX `IX_user_roles_UserId_RolId` ON `user_roles` (`UserId`, `RolId`);

CREATE UNIQUE INDEX `IX_user_sessions_ConnectionId` ON `user_sessions` (`ConnectionId`);

CREATE INDEX `IX_user_sessions_IsActive` ON `user_sessions` (`IsActive`);

CREATE INDEX `IX_user_sessions_UsuarioId` ON `user_sessions` (`UsuarioId`);

CREATE INDEX `IX_user_sessions_UsuarioId_IsActive` ON `user_sessions` (`UsuarioId`, `IsActive`);

CREATE INDEX `IX_users_Documento_hash` ON `users` (`Documento_hash`);

CREATE UNIQUE INDEX `IX_users_Email_hash` ON `users` (`Email_hash`);

CREATE INDEX `IX_users_OficinaId` ON `users` (`OficinaId`);

CREATE INDEX `IX_users_OrganizacionId` ON `users` (`OrganizacionId`);

CREATE UNIQUE INDEX `IX_users_SsoId` ON `users` (`SsoId`);

CREATE INDEX `IX_users_Telefono_hash` ON `users` (`Telefono_hash`);

CREATE UNIQUE INDEX `IX_users_Username` ON `users` (`Username`);

INSERT INTO `__EFMigrationsHistory` (`MigrationId`, `ProductVersion`)
VALUES ('20261020184740_Initial', '9.0.11');

COMMIT;

