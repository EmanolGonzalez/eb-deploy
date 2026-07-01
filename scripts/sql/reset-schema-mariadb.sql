-- =============================================================================
-- reset-schema-mariadb.sql — Elimina TODAS las tablas de la base actual.
-- WARNING: operacion destructiva.
--
-- Metodo: arma un unico "DROP TABLE IF EXISTS `t1`,`t2`,..." con GROUP_CONCAT
-- y lo ejecuta con PREPARE/EXECUTE. NO usa INTO OUTFILE/LOAD_FILE (los bloquea
-- --secure-file-priv en servers gestionados como Railway/RDS, y escribirian en
-- el filesystem del server, no del cliente). Funciona por conexion remota.
-- =============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- Evitar truncado del DROP si hay muchas tablas (default group_concat_max_len=1024).
SET SESSION group_concat_max_len = 10000000;

-- Construir la lista `t1`,`t2`,... de todas las BASE TABLE de la base actual.
SET @tables = NULL;
SELECT GROUP_CONCAT('`', table_name, '`')
  INTO @tables
  FROM information_schema.tables
  WHERE table_schema = DATABASE()
    AND table_type = 'BASE TABLE';

-- Si no hay tablas, @tables queda NULL -> ejecutamos un no-op informativo.
SET @stmt = IF(@tables IS NULL,
               'SELECT ''No hay tablas que eliminar.'' AS resultado',
               CONCAT('DROP TABLE IF EXISTS ', @tables));

PREPARE drop_stmt FROM @stmt;
EXECUTE drop_stmt;
DEALLOCATE PREPARE drop_stmt;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Reset completado. La base quedo sin tablas, lista para el esquema nuevo.' AS resultado;
