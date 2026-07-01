IF OBJECT_ID(N'[__EFMigrationsHistory]') IS NULL
BEGIN
    CREATE TABLE [__EFMigrationsHistory] (
        [MigrationId] nvarchar(150) NOT NULL,
        [ProductVersion] nvarchar(32) NOT NULL,
        CONSTRAINT [PK___EFMigrationsHistory] PRIMARY KEY ([MigrationId])
    );
END;
GO

BEGIN TRANSACTION;
IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [attorney_lookup_configs] (
        [AttorneyLookupConfigId] uniqueidentifier NOT NULL,
        [IsEnabled] bit NOT NULL DEFAULT CAST(0 AS bit),
        [Source] nvarchar(20) NOT NULL,
        [LookupKind] nvarchar(20) NOT NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_attorney_lookup_configs] PRIMARY KEY ([AttorneyLookupConfigId])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [audit_entries] (
        [AuditEntryId] uniqueidentifier NOT NULL,
        [Timestamp] datetime2 NOT NULL,
        [ActorId] nvarchar(50) NULL,
        [Action] nvarchar(100) NOT NULL,
        [EntityType] nvarchar(100) NOT NULL,
        [EntityId] nvarchar(200) NULL,
        [Description] nvarchar(500) NULL,
        [IpAddress_enc] varbinary(max) NULL,
        [TraceId] nvarchar(100) NULL,
        [Metadata] nvarchar(max) NULL,
        CONSTRAINT [PK_audit_entries] PRIMARY KEY ([AuditEntryId])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [operational_state] (
        [OperationalStateId] uniqueidentifier NOT NULL,
        [Status] nvarchar(20) NOT NULL,
        [Message] nvarchar(500) NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_operational_state] PRIMARY KEY ([OperationalStateId])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [organizations] (
        [OrganizacionId] uniqueidentifier NOT NULL,
        [Codigo] nvarchar(50) NOT NULL,
        [Nombre] nvarchar(200) NOT NULL,
        [IsOperational] bit NOT NULL DEFAULT CAST(1 AS bit),
        [IsInMaintenance] bit NOT NULL DEFAULT CAST(0 AS bit),
        [MaintenanceMessage] nvarchar(500) NULL,
        [IsActive] bit NOT NULL DEFAULT CAST(1 AS bit),
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_organizations] PRIMARY KEY ([OrganizacionId])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [permissions] (
        [PermisoId] uniqueidentifier NOT NULL,
        [Codigo] nvarchar(200) NOT NULL,
        [Nombre] nvarchar(200) NOT NULL,
        [Descripcion] nvarchar(300) NULL,
        [IsActive] bit NOT NULL DEFAULT CAST(1 AS bit),
        [IsSystem] bit NOT NULL DEFAULT CAST(0 AS bit),
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_permissions] PRIMARY KEY ([PermisoId])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [report_preferences] (
        [ReportPreferencesId] uniqueidentifier NOT NULL,
        [IncludeDebugOrders] bit NOT NULL DEFAULT CAST(0 AS bit),
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_report_preferences] PRIMARY KEY ([ReportPreferencesId])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [roles] (
        [RolId] uniqueidentifier NOT NULL,
        [Codigo] nvarchar(100) NOT NULL,
        [Nombre] nvarchar(150) NOT NULL,
        [Descripcion] nvarchar(300) NULL,
        [IsActive] bit NOT NULL DEFAULT CAST(1 AS bit),
        [IsSystem] bit NOT NULL DEFAULT CAST(0 AS bit),
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_roles] PRIMARY KEY ([RolId])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [system_modes] (
        [SystemModeId] uniqueidentifier NOT NULL,
        [Mode] nvarchar(50) NOT NULL,
        [IsEnabled] bit NOT NULL DEFAULT CAST(0 AS bit),
        [Message] nvarchar(500) NULL,
        [StartAt] datetime2 NULL,
        [EndAt] datetime2 NULL,
        [SelectedKey] nvarchar(10) NULL,
        [ModeCategory] nvarchar(50) NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_system_modes] PRIMARY KEY ([SystemModeId])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [offices] (
        [OficinaId] uniqueidentifier NOT NULL,
        [OrganizacionId] uniqueidentifier NOT NULL,
        [Codigo] nvarchar(50) NOT NULL,
        [Nombre] nvarchar(200) NOT NULL,
        [Direccion] nvarchar(300) NULL,
        [Provincia] nvarchar(100) NULL,
        [Distrito] nvarchar(100) NULL,
        [Corregimiento] nvarchar(100) NULL,
        [Latitude] decimal(10,7) NULL,
        [Longitude] decimal(10,7) NULL,
        [OperationalStatus] nvarchar(50) NOT NULL DEFAULT N'Operational',
        [MaintenanceMessage] nvarchar(500) NULL,
        [CodigoMaestro] nvarchar(50) NULL,
        [IsActive] bit NOT NULL DEFAULT CAST(1 AS bit),
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_offices] PRIMARY KEY ([OficinaId]),
        CONSTRAINT [FK_offices_organizations_OrganizacionId] FOREIGN KEY ([OrganizacionId]) REFERENCES [organizations] ([OrganizacionId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [role_permissions] (
        [RolPermisoId] uniqueidentifier NOT NULL,
        [RolId] uniqueidentifier NOT NULL,
        [PermisoId] uniqueidentifier NOT NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_role_permissions] PRIMARY KEY ([RolPermisoId]),
        CONSTRAINT [FK_role_permissions_permissions_PermisoId] FOREIGN KEY ([PermisoId]) REFERENCES [permissions] ([PermisoId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_role_permissions_roles_RolId] FOREIGN KEY ([RolId]) REFERENCES [roles] ([RolId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [users] (
        [Id] uniqueidentifier NOT NULL,
        [SsoId] uniqueidentifier NOT NULL,
        [Username] nvarchar(100) NULL,
        [Email_enc] varbinary(max) NULL,
        [Nombres_enc] varbinary(max) NOT NULL,
        [Apellidos_enc] varbinary(max) NOT NULL,
        [Documento_enc] varbinary(max) NULL,
        [Telefono_enc] varbinary(max) NULL,
        [Picture] nvarchar(256) NULL,
        [OrganizacionId] uniqueidentifier NULL,
        [OficinaId] uniqueidentifier NULL,
        [IsActive] bit NOT NULL DEFAULT CAST(1 AS bit),
        [Documento_hash] binary(32) NULL,
        [Email_hash] binary(32) NULL,
        [Telefono_hash] binary(32) NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_users] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_users_offices_OficinaId] FOREIGN KEY ([OficinaId]) REFERENCES [offices] ([OficinaId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_users_organizations_OrganizacionId] FOREIGN KEY ([OrganizacionId]) REFERENCES [organizations] ([OrganizacionId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [auth_sessions] (
        [SessionId] uniqueidentifier NOT NULL,
        [UserId] uniqueidentifier NOT NULL,
        [SsoId] uniqueidentifier NOT NULL,
        [CreatedAtSession] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [ExpiresAt] datetime2 NOT NULL,
        [RevokedAt] datetime2 NULL,
        [ClientIp_enc] varbinary(max) NULL,
        [UserAgent] nvarchar(512) NULL,
        [ClientInfo] nvarchar(256) NULL,
        [SsoAccessToken_enc] varbinary(max) NULL,
        [SsoRefreshToken_enc] varbinary(max) NULL,
        [SsoTokenExpiresAt] datetime2 NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_auth_sessions] PRIMARY KEY ([SessionId]),
        CONSTRAINT [FK_auth_sessions_users_UserId] FOREIGN KEY ([UserId]) REFERENCES [users] ([Id]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [orders] (
        [DeliveryOrderId] uniqueidentifier NOT NULL,
        [Status] nvarchar(50) NOT NULL,
        [Flags] int NOT NULL,
        [IsDebug] bit NOT NULL,
        [SystemDebugMode] nvarchar(max) NULL,
        [Attempts] int NOT NULL,
        [RequestedAt] datetime2 NOT NULL,
        [FirstOpenedAt] datetime2 NULL,
        [StartedAt] datetime2 NULL,
        [BiometryStartedAt] datetime2 NULL,
        [BiometryCompletedAt] datetime2 NULL,
        [CompletedAt] datetime2 NULL,
        [CanceledAt] datetime2 NULL,
        [ReceiverSelectedAt] datetime2 NULL,
        [ImageSavedAt] datetime2 NULL,
        [Latitude] decimal(18,8) NULL,
        [Longitude] decimal(18,8) NULL,
        [OrganizationId] uniqueidentifier NULL,
        [OfficeId] uniqueidentifier NULL,
        [DeliveredByUserId] uniqueidentifier NULL,
        [DeliveredByDocument_enc] varbinary(max) NULL,
        [RequestedByUserId] uniqueidentifier NULL,
        [RequestedByDocument_enc] varbinary(max) NULL,
        [OrderRequestCacheKey] nvarchar(200) NULL,
        [ReferenceCode] nvarchar(50) NULL,
        [TribunalOfficeCode] nvarchar(50) NULL,
        [CitizenNationalId_enc] varbinary(max) NOT NULL,
        [CitizenSerialNumber_enc] varbinary(max) NOT NULL,
        [Nationality] nvarchar(100) NOT NULL,
        [Address_enc] varbinary(max) NOT NULL,
        [Province] nvarchar(100) NOT NULL,
        [Description] nvarchar(300) NOT NULL,
        [Sex] nvarchar(20) NOT NULL,
        [RangeAge] nvarchar(20) NOT NULL,
        [IsJuvenile] bit NOT NULL,
        [CitizenAge] int NULL,
        [CommentRejected] nvarchar(500) NULL,
        [CommentDelivered] nvarchar(500) NULL,
        [CitizenNationalId_hash] binary(32) NULL,
        [CitizenSerialNumber_hash] binary(32) NULL,
        [DeliveredByDocument_hash] binary(32) NULL,
        [RequestedByDocument_hash] binary(32) NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_orders] PRIMARY KEY ([DeliveryOrderId]),
        CONSTRAINT [FK_orders_offices_OfficeId] FOREIGN KEY ([OfficeId]) REFERENCES [offices] ([OficinaId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_orders_organizations_OrganizationId] FOREIGN KEY ([OrganizationId]) REFERENCES [organizations] ([OrganizacionId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_orders_users_DeliveredByUserId] FOREIGN KEY ([DeliveredByUserId]) REFERENCES [users] ([Id]) ON DELETE NO ACTION,
        CONSTRAINT [FK_orders_users_RequestedByUserId] FOREIGN KEY ([RequestedByUserId]) REFERENCES [users] ([Id]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [session_daily_logs] (
        [SessionDailyLogId] uniqueidentifier NOT NULL,
        [UsuarioId] uniqueidentifier NOT NULL,
        [Date] date NOT NULL,
        [TotalSeconds] int NOT NULL DEFAULT 0,
        [SessionCount] int NOT NULL DEFAULT 0,
        [LastSnapshotAt] datetime2 NOT NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_session_daily_logs] PRIMARY KEY ([SessionDailyLogId]),
        CONSTRAINT [FK_session_daily_logs_users_UsuarioId] FOREIGN KEY ([UsuarioId]) REFERENCES [users] ([Id]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [user_roles] (
        [UsuarioRolId] uniqueidentifier NOT NULL,
        [UsuarioId] uniqueidentifier NOT NULL,
        [RolId] uniqueidentifier NOT NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_user_roles] PRIMARY KEY ([UsuarioRolId]),
        CONSTRAINT [FK_user_roles_roles_RolId] FOREIGN KEY ([RolId]) REFERENCES [roles] ([RolId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_user_roles_users_UsuarioId] FOREIGN KEY ([UsuarioId]) REFERENCES [users] ([Id]) ON DELETE CASCADE
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [user_sessions] (
        [UsuarioSesionId] uniqueidentifier NOT NULL,
        [UsuarioId] uniqueidentifier NOT NULL,
        [ConnectionId] nvarchar(200) NOT NULL,
        [StartedAt] datetime2 NOT NULL,
        [LastSeenAt] datetime2 NOT NULL,
        [EndedAt] datetime2 NULL,
        [EndReason] nvarchar(120) NULL,
        [ClientIp_enc] varbinary(max) NULL,
        [UserAgent] nvarchar(256) NULL,
        [Latitude] decimal(10,7) NULL,
        [Longitude] decimal(10,7) NULL,
        [GeoSource] nvarchar(50) NULL,
        [GeoResolvedAt] datetime2 NULL,
        [GeoAccuracyKm] int NULL,
        [IsActive] bit NOT NULL DEFAULT CAST(1 AS bit),
        [TotalSeconds] int NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_user_sessions] PRIMARY KEY ([UsuarioSesionId]),
        CONSTRAINT [FK_user_sessions_users_UsuarioId] FOREIGN KEY ([UsuarioId]) REFERENCES [users] ([Id]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [order_access_logs] (
        [DeliveryOrderAccessLogId] uniqueidentifier NOT NULL,
        [DeliveryOrderId] uniqueidentifier NOT NULL,
        [OfficialNationalId] nvarchar(50) NOT NULL,
        [AccessType] nvarchar(50) NOT NULL,
        [Source] nvarchar(100) NULL,
        [AccessedAt] datetime2 NOT NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_order_access_logs] PRIMARY KEY ([DeliveryOrderAccessLogId]),
        CONSTRAINT [FK_order_access_logs_orders_DeliveryOrderId] FOREIGN KEY ([DeliveryOrderId]) REFERENCES [orders] ([DeliveryOrderId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [order_evidences] (
        [DeliveryOrderEvidenceId] uniqueidentifier NOT NULL,
        [DeliveryOrderId] uniqueidentifier NOT NULL,
        [Type] nvarchar(50) NOT NULL,
        [FilePath] nvarchar(500) NOT NULL,
        [OriginalName] nvarchar(200) NOT NULL,
        [SequentialName] nvarchar(200) NOT NULL,
        [CapturedAt] datetime2 NOT NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_order_evidences] PRIMARY KEY ([DeliveryOrderEvidenceId]),
        CONSTRAINT [FK_order_evidences_orders_DeliveryOrderId] FOREIGN KEY ([DeliveryOrderId]) REFERENCES [orders] ([DeliveryOrderId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [order_logs] (
        [DeliveryOrderLogId] uniqueidentifier NOT NULL,
        [DeliveryOrderId] uniqueidentifier NOT NULL,
        [Level] nvarchar(50) NOT NULL,
        [Message] nvarchar(1000) NOT NULL,
        [Timestamp] datetime2 NOT NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_order_logs] PRIMARY KEY ([DeliveryOrderLogId]),
        CONSTRAINT [FK_order_logs_orders_DeliveryOrderId] FOREIGN KEY ([DeliveryOrderId]) REFERENCES [orders] ([DeliveryOrderId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE TABLE [order_receivers] (
        [DeliveryOrderReceiverId] uniqueidentifier NOT NULL,
        [DeliveryOrderId] uniqueidentifier NOT NULL,
        [Name_enc] varbinary(max) NOT NULL,
        [Role] nvarchar(100) NOT NULL,
        [Identification_enc] varbinary(max) NOT NULL,
        [Type] nvarchar(50) NOT NULL,
        [Relationship] nvarchar(max) NULL,
        [IsSelected] bit NOT NULL,
        [SelectedAt] datetime2 NULL,
        [Identification_hash] binary(32) NULL,
        [Name_hash] binary(32) NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (SYSUTCDATETIME()),
        [CreatedBy] nvarchar(max) NULL,
        [UpdatedAt] datetime2 NULL,
        [UpdatedBy] nvarchar(max) NULL,
        [DeletedAt] datetime2 NULL,
        [DeletedBy] nvarchar(max) NULL,
        [IsDeleted] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_order_receivers] PRIMARY KEY ([DeliveryOrderReceiverId]),
        CONSTRAINT [FK_order_receivers_orders_DeliveryOrderId] FOREIGN KEY ([DeliveryOrderId]) REFERENCES [orders] ([DeliveryOrderId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_audit_entries_ActorId_Timestamp] ON [audit_entries] ([ActorId], [Timestamp]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_audit_entries_EntityType] ON [audit_entries] ([EntityType]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_audit_entries_Timestamp] ON [audit_entries] ([Timestamp] DESC);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_AuthSession_ExpiresAt] ON [auth_sessions] ([ExpiresAt]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_AuthSession_RevokedAt] ON [auth_sessions] ([RevokedAt]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_AuthSession_SsoId] ON [auth_sessions] ([SsoId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_AuthSession_UserId] ON [auth_sessions] ([UserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_AuthSession_UserId_RevokedAt] ON [auth_sessions] ([UserId], [RevokedAt]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE UNIQUE INDEX [IX_offices_OrganizacionId_Codigo] ON [offices] ([OrganizacionId], [Codigo]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_order_access_logs_AccessedAt] ON [order_access_logs] ([AccessedAt]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_order_access_logs_DeliveryOrderId] ON [order_access_logs] ([DeliveryOrderId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_order_access_logs_OfficialNationalId] ON [order_access_logs] ([OfficialNationalId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_order_evidences_DeliveryOrderId] ON [order_evidences] ([DeliveryOrderId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_order_evidences_Type] ON [order_evidences] ([Type]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_order_logs_DeliveryOrderId] ON [order_logs] ([DeliveryOrderId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_order_logs_Timestamp] ON [order_logs] ([Timestamp]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_order_receivers_DeliveryOrderId] ON [order_receivers] ([DeliveryOrderId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_order_receivers_Identification_hash] ON [order_receivers] ([Identification_hash]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_order_receivers_Name_hash] ON [order_receivers] ([Name_hash]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_CitizenNationalId_hash] ON [orders] ([CitizenNationalId_hash]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_CitizenSerialNumber_hash] ON [orders] ([CitizenSerialNumber_hash]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_CreatedAt_DeliveredByUserId] ON [orders] ([CreatedAt], [DeliveredByUserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_CreatedAt_OfficeId] ON [orders] ([CreatedAt], [OfficeId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_DeliveredByDocument_hash] ON [orders] ([DeliveredByDocument_hash]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_DeliveredByUserId] ON [orders] ([DeliveredByUserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_OfficeId] ON [orders] ([OfficeId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_OfficeId_CreatedAt] ON [orders] ([OfficeId], [CreatedAt]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_OrganizationId] ON [orders] ([OrganizationId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_ReferenceCode] ON [orders] ([ReferenceCode]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_RequestedAt] ON [orders] ([RequestedAt]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_RequestedByDocument_hash] ON [orders] ([RequestedByDocument_hash]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_RequestedByUserId] ON [orders] ([RequestedByUserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_orders_Status] ON [orders] ([Status]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE UNIQUE INDEX [IX_organizations_Codigo] ON [organizations] ([Codigo]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE UNIQUE INDEX [IX_permissions_Codigo] ON [permissions] ([Codigo]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_role_permissions_PermisoId] ON [role_permissions] ([PermisoId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE UNIQUE INDEX [IX_role_permissions_RolId_PermisoId] ON [role_permissions] ([RolId], [PermisoId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE UNIQUE INDEX [IX_roles_Codigo] ON [roles] ([Codigo]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_session_daily_logs_Date] ON [session_daily_logs] ([Date]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE UNIQUE INDEX [IX_session_daily_logs_UsuarioId_Date] ON [session_daily_logs] ([UsuarioId], [Date]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_system_modes_IsEnabled] ON [system_modes] ([IsEnabled]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_system_modes_Mode] ON [system_modes] ([Mode]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_user_roles_RolId] ON [user_roles] ([RolId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE UNIQUE INDEX [IX_user_roles_UsuarioId_RolId] ON [user_roles] ([UsuarioId], [RolId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE UNIQUE INDEX [IX_user_sessions_ConnectionId] ON [user_sessions] ([ConnectionId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_user_sessions_IsActive] ON [user_sessions] ([IsActive]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_user_sessions_UsuarioId] ON [user_sessions] ([UsuarioId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_users_Documento_hash] ON [users] ([Documento_hash]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    EXEC(N'CREATE UNIQUE INDEX [IX_users_Email_hash] ON [users] ([Email_hash]) WHERE [Email_hash] IS NOT NULL');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    EXEC(N'CREATE INDEX [IX_users_OficinaId] ON [users] ([OficinaId]) WHERE [OficinaId] IS NOT NULL');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    EXEC(N'CREATE INDEX [IX_users_OrganizacionId] ON [users] ([OrganizacionId]) WHERE [OrganizacionId] IS NOT NULL');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE UNIQUE INDEX [IX_users_SsoId] ON [users] ([SsoId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    CREATE INDEX [IX_users_Telefono_hash] ON [users] ([Telefono_hash]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    EXEC(N'CREATE UNIQUE INDEX [IX_users_Username] ON [users] ([Username]) WHERE [Username] IS NOT NULL');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260530173259_InitialCreate'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260530173259_InitialCreate', N'9.0.11');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260622200915_AddTokenVersionToAuthSessions'
)
BEGIN
    ALTER TABLE [auth_sessions] ADD [TokenVersion] int NOT NULL DEFAULT 0;
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260622200915_AddTokenVersionToAuthSessions'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260622200915_AddTokenVersionToAuthSessions', N'9.0.11');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260624185642_DropPictureColumn'
)
BEGIN
    DECLARE @var sysname;
    SELECT @var = [d].[name]
    FROM [sys].[default_constraints] [d]
    INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
    WHERE ([d].[parent_object_id] = OBJECT_ID(N'[users]') AND [c].[name] = N'Picture');
    IF @var IS NOT NULL EXEC(N'ALTER TABLE [users] DROP CONSTRAINT [' + @var + '];');
    ALTER TABLE [users] DROP COLUMN [Picture];
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260624185642_DropPictureColumn'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260624185642_DropPictureColumn', N'9.0.11');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260625204429_AddAbsoluteExpiresAtToAuthSessions'
)
BEGIN
    ALTER TABLE [auth_sessions] ADD [AbsoluteExpiresAt] datetime2 NULL;
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260625204429_AddAbsoluteExpiresAtToAuthSessions'
)
BEGIN

                    UPDATE auth_sessions
                    SET AbsoluteExpiresAt = DATEADD(HOUR, 8, CreatedAtSession)
                    WHERE AbsoluteExpiresAt IS NULL
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260625204429_AddAbsoluteExpiresAtToAuthSessions'
)
BEGIN
    DECLARE @var1 sysname;
    SELECT @var1 = [d].[name]
    FROM [sys].[default_constraints] [d]
    INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
    WHERE ([d].[parent_object_id] = OBJECT_ID(N'[auth_sessions]') AND [c].[name] = N'AbsoluteExpiresAt');
    IF @var1 IS NOT NULL EXEC(N'ALTER TABLE [auth_sessions] DROP CONSTRAINT [' + @var1 + '];');
    ALTER TABLE [auth_sessions] ALTER COLUMN [AbsoluteExpiresAt] datetime2 NOT NULL;
    ALTER TABLE [auth_sessions] ADD DEFAULT (DATEADD(HOUR, 8, GETUTCDATE())) FOR [AbsoluteExpiresAt];
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260625204429_AddAbsoluteExpiresAtToAuthSessions'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260625204429_AddAbsoluteExpiresAtToAuthSessions', N'9.0.11');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260625204938_AddDataProtectionKeys'
)
BEGIN
    CREATE TABLE [DataProtectionKeys] (
        [Id] int NOT NULL IDENTITY,
        [FriendlyName] nvarchar(max) NULL,
        [Xml] nvarchar(max) NULL,
        CONSTRAINT [PK_DataProtectionKeys] PRIMARY KEY ([Id])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260625204938_AddDataProtectionKeys'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260625204938_AddDataProtectionKeys', N'9.0.11');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260626191929_RemoveDeliveryOrderLogs'
)
BEGIN
    DROP TABLE [order_logs];
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260626191929_RemoveDeliveryOrderLogs'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260626191929_RemoveDeliveryOrderLogs', N'9.0.11');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260626193949_RemoveReportPreferences'
)
BEGIN
    DROP TABLE [report_preferences];
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260626193949_RemoveReportPreferences'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260626193949_RemoveReportPreferences', N'9.0.11');
END;

COMMIT;
GO

