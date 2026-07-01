/*M!999999\- enable the sandbox mode */ 
-- MariaDB dump 10.19-12.2.2-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: ema
-- ------------------------------------------------------
-- Server version	12.2.2-MariaDB-ubu2404

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*M!100616 SET @OLD_NOTE_VERBOSITY=@@NOTE_VERBOSITY, NOTE_VERBOSITY=0 */;

--
-- Table structure for table `DataProtectionKeys`
--

DROP TABLE IF EXISTS `DataProtectionKeys`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `DataProtectionKeys` (
  `Id` int(11) NOT NULL AUTO_INCREMENT,
  `FriendlyName` longtext DEFAULT NULL,
  `Xml` longtext DEFAULT NULL,
  PRIMARY KEY (`Id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `__EFMigrationsHistory`
--

DROP TABLE IF EXISTS `__EFMigrationsHistory`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `__EFMigrationsHistory` (
  `MigrationId` varchar(150) NOT NULL,
  `ProductVersion` varchar(32) NOT NULL,
  PRIMARY KEY (`MigrationId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `attorney_lookup_configs`
--

DROP TABLE IF EXISTS `attorney_lookup_configs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `attorney_lookup_configs` (
  `AttorneyLookupConfigId` varchar(255) NOT NULL,
  `IsEnabled` tinyint(1) NOT NULL DEFAULT 0,
  `Source` varchar(20) NOT NULL,
  `LookupKind` varchar(20) NOT NULL,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`AttorneyLookupConfigId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `audit_entries`
--

DROP TABLE IF EXISTS `audit_entries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `audit_entries` (
  `AuditEntryId` varchar(255) NOT NULL,
  `Timestamp` datetime(6) NOT NULL,
  `ActorId` varchar(50) DEFAULT NULL,
  `Action` varchar(100) NOT NULL,
  `EntityType` varchar(100) NOT NULL,
  `EntityId` varchar(200) DEFAULT NULL,
  `Description` varchar(500) DEFAULT NULL,
  `IpAddress_enc` longblob DEFAULT NULL,
  `TraceId` varchar(100) DEFAULT NULL,
  `Metadata` longtext DEFAULT NULL,
  PRIMARY KEY (`AuditEntryId`),
  KEY `IX_audit_entries_ActorId_Timestamp` (`ActorId`,`Timestamp`),
  KEY `IX_audit_entries_EntityType` (`EntityType`),
  KEY `IX_audit_entries_Timestamp` (`Timestamp` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `auth_sessions`
--

DROP TABLE IF EXISTS `auth_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `auth_sessions` (
  `SessionId` varchar(255) NOT NULL,
  `UserId` varchar(255) NOT NULL,
  `SsoId` varchar(255) NOT NULL,
  `CreatedAtSession` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `ExpiresAt` datetime(6) NOT NULL,
  `RevokedAt` datetime(6) DEFAULT NULL,
  `ClientIp_enc` longblob DEFAULT NULL,
  `UserAgent` varchar(512) DEFAULT NULL,
  `ClientInfo` varchar(256) DEFAULT NULL,
  `SsoAccessToken_enc` longblob DEFAULT NULL,
  `SsoRefreshToken_enc` longblob DEFAULT NULL,
  `SsoTokenExpiresAt` datetime(6) DEFAULT NULL,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  `TokenVersion` int(11) NOT NULL DEFAULT 0,
  `AbsoluteExpiresAt` datetime(6) NOT NULL DEFAULT (utc_timestamp() + interval 8 hour),
  PRIMARY KEY (`SessionId`),
  KEY `IX_AuthSession_ExpiresAt` (`ExpiresAt`),
  KEY `IX_AuthSession_RevokedAt` (`RevokedAt`),
  KEY `IX_AuthSession_SsoId` (`SsoId`),
  KEY `IX_AuthSession_UserId` (`UserId`),
  KEY `IX_AuthSession_UserId_RevokedAt` (`UserId`,`RevokedAt`),
  CONSTRAINT `FK_auth_sessions_users_UserId` FOREIGN KEY (`UserId`) REFERENCES `users` (`Id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `offices`
--

DROP TABLE IF EXISTS `offices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `offices` (
  `OficinaId` varchar(255) NOT NULL,
  `OrganizacionId` varchar(255) NOT NULL,
  `Codigo` varchar(50) NOT NULL,
  `Nombre` varchar(200) NOT NULL,
  `Direccion` varchar(300) DEFAULT NULL,
  `Provincia` varchar(100) DEFAULT NULL,
  `Distrito` varchar(100) DEFAULT NULL,
  `Corregimiento` varchar(100) DEFAULT NULL,
  `Latitude` decimal(10,7) DEFAULT NULL,
  `Longitude` decimal(10,7) DEFAULT NULL,
  `OperationalStatus` varchar(50) NOT NULL DEFAULT 'Operational',
  `MaintenanceMessage` varchar(500) DEFAULT NULL,
  `CodigoMaestro` varchar(50) DEFAULT NULL,
  `IsActive` tinyint(1) NOT NULL DEFAULT 1,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`OficinaId`),
  UNIQUE KEY `IX_offices_OrganizacionId_Codigo` (`OrganizacionId`,`Codigo`),
  CONSTRAINT `FK_offices_organizations_OrganizacionId` FOREIGN KEY (`OrganizacionId`) REFERENCES `organizations` (`OrganizacionId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `operational_state`
--

DROP TABLE IF EXISTS `operational_state`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `operational_state` (
  `OperationalStateId` varchar(255) NOT NULL,
  `Status` varchar(20) NOT NULL,
  `Message` varchar(500) DEFAULT NULL,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`OperationalStateId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `order_access_logs`
--

DROP TABLE IF EXISTS `order_access_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `order_access_logs` (
  `DeliveryOrderAccessLogId` varchar(255) NOT NULL,
  `DeliveryOrderId` varchar(255) NOT NULL,
  `OfficialNationalId` varchar(50) NOT NULL,
  `AccessType` varchar(50) NOT NULL,
  `Source` varchar(100) DEFAULT NULL,
  `AccessedAt` datetime(6) NOT NULL,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`DeliveryOrderAccessLogId`),
  KEY `IX_order_access_logs_AccessedAt` (`AccessedAt`),
  KEY `IX_order_access_logs_DeliveryOrderId` (`DeliveryOrderId`),
  KEY `IX_order_access_logs_OfficialNationalId` (`OfficialNationalId`),
  CONSTRAINT `FK_order_access_logs_orders_DeliveryOrderId` FOREIGN KEY (`DeliveryOrderId`) REFERENCES `orders` (`DeliveryOrderId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `order_evidences`
--

DROP TABLE IF EXISTS `order_evidences`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `order_evidences` (
  `DeliveryOrderEvidenceId` varchar(255) NOT NULL,
  `DeliveryOrderId` varchar(255) NOT NULL,
  `Type` varchar(50) NOT NULL,
  `FilePath` varchar(500) NOT NULL,
  `OriginalName` varchar(200) NOT NULL,
  `SequentialName` varchar(200) NOT NULL,
  `CapturedAt` datetime(6) NOT NULL,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`DeliveryOrderEvidenceId`),
  KEY `IX_order_evidences_DeliveryOrderId` (`DeliveryOrderId`),
  KEY `IX_order_evidences_Type` (`Type`),
  CONSTRAINT `FK_order_evidences_orders_DeliveryOrderId` FOREIGN KEY (`DeliveryOrderId`) REFERENCES `orders` (`DeliveryOrderId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `order_receivers`
--

DROP TABLE IF EXISTS `order_receivers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `order_receivers` (
  `DeliveryOrderReceiverId` varchar(255) NOT NULL,
  `DeliveryOrderId` varchar(255) NOT NULL,
  `Name_enc` longblob NOT NULL,
  `Role` varchar(100) NOT NULL,
  `Identification_enc` longblob NOT NULL,
  `Type` varchar(50) NOT NULL,
  `Relationship` longtext DEFAULT NULL,
  `IsSelected` tinyint(1) NOT NULL,
  `SelectedAt` datetime(6) DEFAULT NULL,
  `Identification_hash` binary(32) DEFAULT NULL,
  `Name_hash` binary(32) DEFAULT NULL,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`DeliveryOrderReceiverId`),
  KEY `IX_order_receivers_DeliveryOrderId` (`DeliveryOrderId`),
  KEY `IX_order_receivers_Identification_hash` (`Identification_hash`),
  KEY `IX_order_receivers_Name_hash` (`Name_hash`),
  CONSTRAINT `FK_order_receivers_orders_DeliveryOrderId` FOREIGN KEY (`DeliveryOrderId`) REFERENCES `orders` (`DeliveryOrderId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `orders`
--

DROP TABLE IF EXISTS `orders`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `orders` (
  `DeliveryOrderId` varchar(255) NOT NULL,
  `Status` varchar(50) NOT NULL,
  `Flags` int(11) NOT NULL,
  `IsDebug` tinyint(1) NOT NULL,
  `SystemDebugMode` longtext DEFAULT NULL,
  `Attempts` int(11) NOT NULL,
  `RequestedAt` datetime(6) NOT NULL,
  `FirstOpenedAt` datetime(6) DEFAULT NULL,
  `StartedAt` datetime(6) DEFAULT NULL,
  `BiometryStartedAt` datetime(6) DEFAULT NULL,
  `BiometryCompletedAt` datetime(6) DEFAULT NULL,
  `CompletedAt` datetime(6) DEFAULT NULL,
  `CanceledAt` datetime(6) DEFAULT NULL,
  `ReceiverSelectedAt` datetime(6) DEFAULT NULL,
  `ImageSavedAt` datetime(6) DEFAULT NULL,
  `Latitude` decimal(18,8) DEFAULT NULL,
  `Longitude` decimal(18,8) DEFAULT NULL,
  `OrganizationId` varchar(255) DEFAULT NULL,
  `OfficeId` varchar(255) DEFAULT NULL,
  `DeliveredByUserId` varchar(255) DEFAULT NULL,
  `DeliveredByDocument_enc` longblob DEFAULT NULL,
  `RequestedByUserId` varchar(255) DEFAULT NULL,
  `RequestedByDocument_enc` longblob DEFAULT NULL,
  `OrderRequestCacheKey` varchar(200) DEFAULT NULL,
  `ReferenceCode` varchar(50) DEFAULT NULL,
  `TribunalOfficeCode` varchar(50) DEFAULT NULL,
  `CitizenNationalId_enc` longblob NOT NULL,
  `CitizenSerialNumber_enc` longblob NOT NULL,
  `Nationality` varchar(100) NOT NULL,
  `Address_enc` longblob NOT NULL,
  `Province` varchar(100) NOT NULL,
  `Description` varchar(300) NOT NULL,
  `Sex` varchar(20) NOT NULL,
  `RangeAge` varchar(20) NOT NULL,
  `IsJuvenile` tinyint(1) NOT NULL,
  `CitizenAge` int(11) DEFAULT NULL,
  `CommentRejected` varchar(500) DEFAULT NULL,
  `CommentDelivered` varchar(500) DEFAULT NULL,
  `CitizenNationalId_hash` binary(32) DEFAULT NULL,
  `CitizenSerialNumber_hash` binary(32) DEFAULT NULL,
  `DeliveredByDocument_hash` binary(32) DEFAULT NULL,
  `RequestedByDocument_hash` binary(32) DEFAULT NULL,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`DeliveryOrderId`),
  KEY `IX_orders_CitizenNationalId_hash` (`CitizenNationalId_hash`),
  KEY `IX_orders_CitizenSerialNumber_hash` (`CitizenSerialNumber_hash`),
  KEY `IX_orders_CreatedAt_DeliveredByUserId` (`CreatedAt`,`DeliveredByUserId`),
  KEY `IX_orders_CreatedAt_OfficeId` (`CreatedAt`,`OfficeId`),
  KEY `IX_orders_DeliveredByDocument_hash` (`DeliveredByDocument_hash`),
  KEY `IX_orders_DeliveredByUserId` (`DeliveredByUserId`),
  KEY `IX_orders_OfficeId` (`OfficeId`),
  KEY `IX_orders_OfficeId_CreatedAt` (`OfficeId`,`CreatedAt`),
  KEY `IX_orders_OrganizationId` (`OrganizationId`),
  KEY `IX_orders_ReferenceCode` (`ReferenceCode`),
  KEY `IX_orders_RequestedAt` (`RequestedAt`),
  KEY `IX_orders_RequestedByDocument_hash` (`RequestedByDocument_hash`),
  KEY `IX_orders_RequestedByUserId` (`RequestedByUserId`),
  KEY `IX_orders_Status` (`Status`),
  CONSTRAINT `FK_orders_offices_OfficeId` FOREIGN KEY (`OfficeId`) REFERENCES `offices` (`OficinaId`),
  CONSTRAINT `FK_orders_organizations_OrganizationId` FOREIGN KEY (`OrganizationId`) REFERENCES `organizations` (`OrganizacionId`),
  CONSTRAINT `FK_orders_users_DeliveredByUserId` FOREIGN KEY (`DeliveredByUserId`) REFERENCES `users` (`Id`),
  CONSTRAINT `FK_orders_users_RequestedByUserId` FOREIGN KEY (`RequestedByUserId`) REFERENCES `users` (`Id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `organizations`
--

DROP TABLE IF EXISTS `organizations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `organizations` (
  `OrganizacionId` varchar(255) NOT NULL,
  `Codigo` varchar(50) NOT NULL,
  `Nombre` varchar(200) NOT NULL,
  `IsOperational` tinyint(1) NOT NULL DEFAULT 1,
  `IsInMaintenance` tinyint(1) NOT NULL DEFAULT 0,
  `MaintenanceMessage` varchar(500) DEFAULT NULL,
  `IsActive` tinyint(1) NOT NULL DEFAULT 1,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`OrganizacionId`),
  UNIQUE KEY `IX_organizations_Codigo` (`Codigo`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `permissions`
--

DROP TABLE IF EXISTS `permissions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `permissions` (
  `PermisoId` varchar(255) NOT NULL,
  `Codigo` varchar(200) NOT NULL,
  `Nombre` varchar(200) NOT NULL,
  `Descripcion` varchar(300) DEFAULT NULL,
  `IsActive` tinyint(1) NOT NULL DEFAULT 1,
  `IsSystem` tinyint(1) NOT NULL DEFAULT 0,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`PermisoId`),
  UNIQUE KEY `IX_permissions_Codigo` (`Codigo`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `role_permissions`
--

DROP TABLE IF EXISTS `role_permissions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `role_permissions` (
  `RolPermisoId` varchar(255) NOT NULL,
  `RolId` varchar(255) NOT NULL,
  `PermisoId` varchar(255) NOT NULL,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`RolPermisoId`),
  UNIQUE KEY `IX_role_permissions_RolId_PermisoId` (`RolId`,`PermisoId`),
  KEY `IX_role_permissions_PermisoId` (`PermisoId`),
  CONSTRAINT `FK_role_permissions_permissions_PermisoId` FOREIGN KEY (`PermisoId`) REFERENCES `permissions` (`PermisoId`),
  CONSTRAINT `FK_role_permissions_roles_RolId` FOREIGN KEY (`RolId`) REFERENCES `roles` (`RolId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `roles`
--

DROP TABLE IF EXISTS `roles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `roles` (
  `RolId` varchar(255) NOT NULL,
  `Codigo` varchar(100) NOT NULL,
  `Nombre` varchar(150) NOT NULL,
  `Descripcion` varchar(300) DEFAULT NULL,
  `IsActive` tinyint(1) NOT NULL DEFAULT 1,
  `IsSystem` tinyint(1) NOT NULL DEFAULT 0,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`RolId`),
  UNIQUE KEY `IX_roles_Codigo` (`Codigo`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `session_daily_logs`
--

DROP TABLE IF EXISTS `session_daily_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `session_daily_logs` (
  `SessionDailyLogId` varchar(255) NOT NULL,
  `UsuarioId` varchar(255) NOT NULL,
  `Date` date NOT NULL,
  `TotalSeconds` int(11) NOT NULL DEFAULT 0,
  `SessionCount` int(11) NOT NULL DEFAULT 0,
  `LastSnapshotAt` datetime(6) NOT NULL,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`SessionDailyLogId`),
  UNIQUE KEY `IX_session_daily_logs_UsuarioId_Date` (`UsuarioId`,`Date`),
  KEY `IX_session_daily_logs_Date` (`Date`),
  CONSTRAINT `FK_session_daily_logs_users_UsuarioId` FOREIGN KEY (`UsuarioId`) REFERENCES `users` (`Id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `system_modes`
--

DROP TABLE IF EXISTS `system_modes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `system_modes` (
  `SystemModeId` varchar(255) NOT NULL,
  `Mode` varchar(50) NOT NULL,
  `IsEnabled` tinyint(1) NOT NULL DEFAULT 0,
  `Message` varchar(500) DEFAULT NULL,
  `StartAt` datetime(6) DEFAULT NULL,
  `EndAt` datetime(6) DEFAULT NULL,
  `SelectedKey` varchar(10) DEFAULT NULL,
  `ModeCategory` varchar(50) DEFAULT NULL,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`SystemModeId`),
  KEY `IX_system_modes_IsEnabled` (`IsEnabled`),
  KEY `IX_system_modes_Mode` (`Mode`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_roles`
--

DROP TABLE IF EXISTS `user_roles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_roles` (
  `UsuarioRolId` varchar(255) NOT NULL,
  `UsuarioId` varchar(255) NOT NULL,
  `RolId` varchar(255) NOT NULL,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`UsuarioRolId`),
  UNIQUE KEY `IX_user_roles_UsuarioId_RolId` (`UsuarioId`,`RolId`),
  KEY `IX_user_roles_RolId` (`RolId`),
  CONSTRAINT `FK_user_roles_roles_RolId` FOREIGN KEY (`RolId`) REFERENCES `roles` (`RolId`),
  CONSTRAINT `FK_user_roles_users_UsuarioId` FOREIGN KEY (`UsuarioId`) REFERENCES `users` (`Id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_sessions`
--

DROP TABLE IF EXISTS `user_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_sessions` (
  `UsuarioSesionId` varchar(255) NOT NULL,
  `UsuarioId` varchar(255) NOT NULL,
  `ConnectionId` varchar(200) NOT NULL,
  `StartedAt` datetime(6) NOT NULL,
  `LastSeenAt` datetime(6) NOT NULL,
  `EndedAt` datetime(6) DEFAULT NULL,
  `EndReason` varchar(120) DEFAULT NULL,
  `ClientIp_enc` longblob DEFAULT NULL,
  `UserAgent` varchar(256) DEFAULT NULL,
  `Latitude` decimal(10,7) DEFAULT NULL,
  `Longitude` decimal(10,7) DEFAULT NULL,
  `GeoSource` varchar(50) DEFAULT NULL,
  `GeoResolvedAt` datetime(6) DEFAULT NULL,
  `GeoAccuracyKm` int(11) DEFAULT NULL,
  `IsActive` tinyint(1) NOT NULL DEFAULT 1,
  `TotalSeconds` int(11) DEFAULT NULL,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`UsuarioSesionId`),
  UNIQUE KEY `IX_user_sessions_ConnectionId` (`ConnectionId`),
  KEY `IX_user_sessions_IsActive` (`IsActive`),
  KEY `IX_user_sessions_UsuarioId` (`UsuarioId`),
  CONSTRAINT `FK_user_sessions_users_UsuarioId` FOREIGN KEY (`UsuarioId`) REFERENCES `users` (`Id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `Id` varchar(255) NOT NULL,
  `SsoId` varchar(255) NOT NULL,
  `Username` varchar(100) DEFAULT NULL,
  `Email_enc` longblob DEFAULT NULL,
  `Nombres_enc` longblob NOT NULL,
  `Apellidos_enc` longblob NOT NULL,
  `Documento_enc` longblob DEFAULT NULL,
  `Telefono_enc` longblob DEFAULT NULL,
  `OrganizacionId` varchar(255) DEFAULT NULL,
  `OficinaId` varchar(255) DEFAULT NULL,
  `IsActive` tinyint(1) NOT NULL DEFAULT 1,
  `Documento_hash` binary(32) DEFAULT NULL,
  `Email_hash` binary(32) DEFAULT NULL,
  `Telefono_hash` binary(32) DEFAULT NULL,
  `CreatedAt` datetime(6) NOT NULL DEFAULT utc_timestamp(6),
  `CreatedBy` longtext DEFAULT NULL,
  `UpdatedAt` datetime(6) DEFAULT NULL,
  `UpdatedBy` longtext DEFAULT NULL,
  `DeletedAt` datetime(6) DEFAULT NULL,
  `DeletedBy` longtext DEFAULT NULL,
  `IsDeleted` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`Id`),
  UNIQUE KEY `IX_users_SsoId` (`SsoId`),
  UNIQUE KEY `IX_users_Email_hash` (`Email_hash`),
  UNIQUE KEY `IX_users_Username` (`Username`),
  KEY `IX_users_Documento_hash` (`Documento_hash`),
  KEY `IX_users_OficinaId` (`OficinaId`),
  KEY `IX_users_OrganizacionId` (`OrganizacionId`),
  KEY `IX_users_Telefono_hash` (`Telefono_hash`),
  CONSTRAINT `FK_users_offices_OficinaId` FOREIGN KEY (`OficinaId`) REFERENCES `offices` (`OficinaId`),
  CONSTRAINT `FK_users_organizations_OrganizacionId` FOREIGN KEY (`OrganizacionId`) REFERENCES `organizations` (`OrganizacionId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping events for database 'ema'
--

--
-- Dumping routines for database 'ema'
--
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*M!100616 SET NOTE_VERBOSITY=@OLD_NOTE_VERBOSITY */;

-- Dump completed on 2026-06-26 19:40:37
