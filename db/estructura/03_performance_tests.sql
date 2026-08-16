BEGIN;

/* -- 1) Quitar temporalmente índices (si no existen, solo mostrará NOTICE)
DROP INDEX IF EXISTS ix_medicion_valores_gin;
DROP INDEX IF EXISTS ux_instalacion_dispositivo_activa;
DROP INDEX IF EXISTS ux_asignacion_pivote_activa;

DROP INDEX IF EXISTS ix_lote_id_campo;
DROP INDEX IF EXISTS ix_sector_id_lote;
DROP INDEX IF EXISTS ix_pivote_id_campo;
DROP INDEX IF EXISTS ix_asignacion_pivote_id_lote;
DROP INDEX IF EXISTS ix_tipo_dispositivo_id_categoria;
DROP INDEX IF EXISTS ix_dispositivo_id_tipo;
DROP INDEX IF EXISTS ix_instalacion_dispositivo_id_sector;
DROP INDEX IF EXISTS ix_instalacion_dispositivo_id_campo;
DROP INDEX IF EXISTS ix_instalacion_dispositivo_id_pivote;
DROP INDEX IF EXISTS ix_medicion_id_dispositivo;
DROP INDEX IF EXISTS ix_medicion_id_gateway;
DROP INDEX IF EXISTS ix_regla_alarma_id_variable;
DROP INDEX IF EXISTS ix_evento_alarma_id_regla;
DROP INDEX IF EXISTS ix_alarma_dispositivo_id_dispositivo;
DROP INDEX IF EXISTS ix_tipo_variable_id_variable;
DROP INDEX IF EXISTS ix_usuario_id_perfil;
DROP INDEX IF EXISTS ix_medicion_fecha_hora_desc;
DROP INDEX IF EXISTS ix_evento_alarma_fecha_hora_desc; */

-- 2) Consulta 10.1
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    l.id_lote,
    l.nombre AS lote,
    ROUND(AVG((m.valores_medidos ->> 'humedad_suelo')::numeric), 2) AS humedad_promedio
FROM medicion m
JOIN dispositivo d
    ON d.id_dispositivo = m.id_dispositivo
JOIN instalacion_dispositivo i
    ON i.id_dispositivo = d.id_dispositivo
JOIN sector s
    ON s.id_sector = i.id_sector
JOIN lote l
    ON l.id_lote = s.id_lote
WHERE i.fecha_fin IS NULL
  AND m.fecha_hora >= NOW() - INTERVAL '7 days'
GROUP BY l.id_lote, l.nombre
ORDER BY humedad_promedio ASC;

-- 3) Consulta 10.3
EXPLAIN (ANALYZE, BUFFERS)
WITH ultimas_mediciones AS (
    SELECT
        m.id_dispositivo,
        m.valores_medidos,
        ROW_NUMBER() OVER (
            PARTITION BY m.id_dispositivo
            ORDER BY m.fecha_hora DESC
        ) AS rn
    FROM medicion m
)
SELECT
    d.id_dispositivo,
    td.nombre AS tipo_dispositivo,
    (um.valores_medidos ->> 'bateria')::numeric AS bateria_actual
FROM ultimas_mediciones um
JOIN dispositivo d
    ON d.id_dispositivo = um.id_dispositivo
JOIN tipo_dispositivo td
    ON td.id_tipo = d.id_tipo
WHERE um.rn = 1
  AND (um.valores_medidos ->> 'bateria')::numeric < 20
ORDER BY bateria_actual ASC;

-- 4) Consulta 10.5
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    s.id_sector,
    s.nombre AS sector,
    l.id_lote,
    l.nombre AS lote,
    ROUND(AVG((m.valores_medidos ->> 'temperatura_suelo')::numeric), 2) AS temp_promedio,
    ROUND(AVG((m.valores_medidos ->> 'humedad_suelo')::numeric), 2) AS humedad_promedio
FROM medicion m
JOIN dispositivo d
    ON d.id_dispositivo = m.id_dispositivo
JOIN instalacion_dispositivo i
    ON i.id_dispositivo = d.id_dispositivo
JOIN sector s
    ON s.id_sector = i.id_sector
JOIN lote l
    ON l.id_lote = s.id_lote
WHERE i.fecha_fin IS NULL
  AND m.fecha_hora >= NOW() - INTERVAL '24 hours'
GROUP BY s.id_sector, s.nombre, l.id_lote, l.nombre
ORDER BY l.nombre, s.nombre;

-- 5) Volver todo atrás (no deja la base modificada)
ROLLBACK;