-- =============================================================================
-- reset-schema-sqlserver.sql — Drop all tables and constraints from current DB
-- WARNING: Destructive operation. Use with caution.
-- =============================================================================

SET NOCOUNT ON;

-- 1. Drop all foreign keys first (to avoid constraint violations)
DECLARE @drop_fks NVARCHAR(MAX) = '';

SELECT @drop_fks += 'ALTER TABLE [' + SCHEMA_NAME(t.schema_id) + '].[' + t.name + '] DROP CONSTRAINT [' + fk.name + '];' + CHAR(13)
FROM sys.foreign_keys fk
INNER JOIN sys.tables t ON fk.parent_object_id = t.object_id;

IF LEN(@drop_fks) > 0
BEGIN
    EXEC sp_executesql @drop_fks;
    PRINT 'Foreign keys dropped: ' + CAST(LEN(@drop_fks) AS VARCHAR) + ' bytes processed';
END
ELSE
BEGIN
    PRINT 'No foreign keys found.';
END

-- 2. Drop all tables
DECLARE @drop_tables NVARCHAR(MAX) = '';

SELECT @drop_tables += 'DROP TABLE IF EXISTS [' + SCHEMA_NAME(schema_id) + '].[' + name + '];' + CHAR(13)
FROM sys.tables
ORDER BY name;

IF LEN(@drop_tables) > 0
BEGIN
    EXEC sp_executesql @drop_tables;
    PRINT 'All tables dropped successfully.';
END
ELSE
BEGIN
    PRINT 'No tables found. Schema was already empty.';
END

-- 3. Optional: Drop all user-defined stored procedures
DECLARE @drop_procs NVARCHAR(MAX) = '';

SELECT @drop_procs += 'DROP PROCEDURE IF EXISTS [' + SCHEMA_NAME(schema_id) + '].[' + name + '];' + CHAR(13)
FROM sys.procedures
WHERE name NOT LIKE 'sp_%'
  AND SCHEMA_NAME(schema_id) = 'dbo';

IF LEN(@drop_procs) > 0
BEGIN
    EXEC sp_executesql @drop_procs;
    PRINT 'Stored procedures dropped.';
END

-- 4. Optional: Drop all user-defined functions
DECLARE @drop_funcs NVARCHAR(MAX) = '';

SELECT @drop_funcs += 'DROP FUNCTION IF EXISTS [' + SCHEMA_NAME(schema_id) + '].[' + name + '];' + CHAR(13)
FROM sys.objects
WHERE type IN ('FN', 'IF', 'TF')
  AND SCHEMA_NAME(schema_id) = 'dbo';

IF LEN(@drop_funcs) > 0
BEGIN
    EXEC sp_executesql @drop_funcs;
    PRINT 'Functions dropped.';
END

PRINT 'Schema reset complete. Database is empty and ready for new schema.';
