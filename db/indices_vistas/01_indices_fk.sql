-- Crear archivo: db/indices_vistas/01_indices_fk.sql
-- Índices recomendados para columnas FK y joins frecuentes.
-- PK/UNIQUE ya indexan automáticamente; esto cubre FKs (no indexadas por defecto).

CREATE INDEX IF NOT EXISTS ix_lote_id_campo
    ON lote (id_campo);

CREATE INDEX IF NOT EXISTS ix_sector_id_lote
    ON sector (id_lote);

CREATE INDEX IF NOT EXISTS ix_pivote_id_campo
    ON pivote (id_campo);

CREATE INDEX IF NOT EXISTS ix_asignacion_pivote_id_lote
    ON asignacion_pivote (id_lote);

CREATE INDEX IF NOT EXISTS ix_tipo_dispositivo_id_categoria
    ON tipo_dispositivo (id_categoria);

CREATE INDEX IF NOT EXISTS ix_dispositivo_id_tipo
    ON dispositivo (id_tipo);

CREATE INDEX IF NOT EXISTS ix_instalacion_dispositivo_id_sector
    ON instalacion_dispositivo (id_sector);

CREATE INDEX IF NOT EXISTS ix_instalacion_dispositivo_id_campo
    ON instalacion_dispositivo (id_campo);

CREATE INDEX IF NOT EXISTS ix_instalacion_dispositivo_id_pivote
    ON instalacion_dispositivo (id_pivote);

CREATE INDEX IF NOT EXISTS ix_medicion_id_dispositivo
    ON medicion (id_dispositivo);

CREATE INDEX IF NOT EXISTS ix_medicion_id_gateway
    ON medicion (id_gateway);

CREATE INDEX IF NOT EXISTS ix_regla_alarma_id_variable
    ON regla_alarma (id_variable);

CREATE INDEX IF NOT EXISTS ix_evento_alarma_id_regla
    ON evento_alarma (id_regla);

-- Tabla puente: PK es (id_regla_alarma, id_dispositivo),
-- agregamos índice inverso para búsquedas por dispositivo.
CREATE INDEX IF NOT EXISTS ix_alarma_dispositivo_id_dispositivo
    ON alarma_dispositivo (id_dispositivo);

-- Tabla puente: PK es (id_tipo_dispositivo, id_variable),
-- agregamos índice inverso para búsquedas por variable.
CREATE INDEX IF NOT EXISTS ix_tipo_variable_id_variable
    ON tipo_variable (id_variable);

CREATE INDEX IF NOT EXISTS ix_usuario_id_perfil
    ON usuario (id_perfil);

-- Útiles para filtros temporales de tus consultas
CREATE INDEX IF NOT EXISTS ix_medicion_fecha_hora_desc
    ON medicion (fecha_hora DESC);

CREATE INDEX IF NOT EXISTS ix_evento_alarma_fecha_hora_desc
    ON evento_alarma (fecha_hora DESC);