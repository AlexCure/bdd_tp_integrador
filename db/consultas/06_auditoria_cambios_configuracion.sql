-- ============================================================================
-- 06_auditoria_cambios_configuracion.sql
-- TP Integrador BDIA — CEIA FIUBA 2026 · aporte de D a la tarea C-01
--
-- Consulta representativa sobre el registro de auditoría (05_auditoria.sql).
--
-- Pregunta que responde:
--   ¿Quién cambió la configuración del sistema en los últimos 30 días, qué
--   cambió exactamente, y qué cambios se hicieron por fuera de la aplicación?
--
-- Por qué es útil:
--   Es la consulta que se ejecuta cuando algo dejó de funcionar y nadie sabe por
--   qué. En un sistema que decide cuándo regar, la pregunta "¿quién deshabilitó
--   esta alarma?" o "¿desde cuándo este sensor figura en el sector B?" tiene
--   consecuencias sobre un cultivo real. Sin auditoría no hay respuesta posible:
--   la fila ya fue sobrescrita.
--
-- Elementos que aporta al conjunto exigido por la consigna:
--   - función de ventana (LAG) para medir el intervalo entre cambios
--   - operadores JSONB para extraer el valor de una columna del registro
--   - agregación con GROUP BY y filtros condicionados (FILTER)
--   - una consulta que justifica un índice (ix_registro_cambios_tabla_fecha)
--
-- Ejecutar como app_administrador (es el único rol con acceso a auditoria).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Detalle de cambios de configuración, con el tiempo transcurrido desde el
--    cambio anterior sobre el mismo registro.
--
-- LAG() sobre la partición (tabla, clave_registro) permite ver la cadencia de
-- modificaciones: varios cambios seguidos sobre la misma regla de alarma en
-- pocos minutos suele indicar que alguien estaba probando algo, y es
-- información distinta de un cambio aislado.
-- ----------------------------------------------------------------------------

SELECT
    rc.fecha_hora,
    rc.usuario_bd                                   AS rol_de_base,
    COALESCE(u.email, '(fuera de la aplicación)')   AS usuario,
    rc.tabla,
    rc.operacion,
    rc.clave_registro,
    array_to_string(rc.columnas_modificadas, ', ')  AS columnas,
    rc.fecha_hora - LAG(rc.fecha_hora) OVER (
        PARTITION BY rc.tabla, rc.clave_registro
        ORDER BY     rc.fecha_hora
    )                                               AS desde_el_cambio_anterior
FROM auditoria.registro_cambios rc
LEFT JOIN usuario u ON u.id_usuario = rc.usuario_app
WHERE rc.fecha_hora >= now() - INTERVAL '30 days'
  AND rc.tabla IN ('dispositivo', 'instalacion_dispositivo',
                   'asignacion_pivote', 'regla_alarma', 'alarma_dispositivo')
ORDER BY rc.fecha_hora DESC;


-- ----------------------------------------------------------------------------
-- 2. Reglas de alarma que fueron deshabilitadas, y por quién.
--
-- Una alarma deshabilitada es un silencio: el sistema deja de avisar sin que
-- nada falle visiblemente. Es el cambio de configuración con mayor potencial de
-- daño y el que menos se nota.
--
-- El operador ->> extrae el valor de una clave del JSONB de la fila auditada.
-- ----------------------------------------------------------------------------

SELECT
    rc.fecha_hora,
    COALESCE(u.email, rc.usuario_bd)                    AS quien,
    rc.clave_registro ->> 'id_regla'                    AS id_regla,
    rc.datos_nuevos   ->> 'descripcion'                 AS regla,
    rc.datos_anteriores ->> 'habilitada'                AS estaba,
    rc.datos_nuevos     ->> 'habilitada'                AS quedo
FROM auditoria.registro_cambios rc
LEFT JOIN usuario u ON u.id_usuario = rc.usuario_app
WHERE rc.tabla = 'regla_alarma'
  AND rc.operacion = 'UPDATE'
  AND 'habilitada' = ANY(rc.columnas_modificadas)
  AND rc.datos_nuevos ->> 'habilitada' = 'false'
ORDER BY rc.fecha_hora DESC;


-- ----------------------------------------------------------------------------
-- 3. Resumen por tabla y por usuario, con control de cambios sin trazabilidad.
--
-- La columna "sin_usuario_app" cuenta los cambios hechos por fuera de la
-- aplicación (psql, script de carga, migración). La carga inicial de datos
-- genera muchos, pero en régimen esta columna debería estar en cero: un número
-- alto significa que se está operando la base a mano.
-- ----------------------------------------------------------------------------

SELECT
    rc.tabla,
    count(*)                                                        AS cambios,
    count(*) FILTER (WHERE rc.operacion = 'INSERT')                 AS altas,
    count(*) FILTER (WHERE rc.operacion = 'UPDATE')                 AS modificaciones,
    count(*) FILTER (WHERE rc.operacion = 'DELETE')                 AS bajas,
    count(*) FILTER (WHERE rc.usuario_app IS NULL)                  AS sin_usuario_app,
    count(DISTINCT rc.usuario_app)                                  AS usuarios_distintos,
    max(rc.fecha_hora)                                              AS ultimo_cambio
FROM auditoria.registro_cambios rc
WHERE rc.fecha_hora >= now() - INTERVAL '30 days'
GROUP BY rc.tabla
ORDER BY cambios DESC;


-- ----------------------------------------------------------------------------
-- 4. Justificación del índice
--
-- Las tres consultas filtran por tabla y ordenan por fecha descendente, que es
-- exactamente la forma de ix_registro_cambios_tabla_fecha (tabla, fecha_hora DESC).
-- Sin ese índice, el registro de auditoría —que sólo crece— obliga a un recorrido
-- secuencial completo cada vez que alguien investiga un incidente.
--
-- Comprobarlo con:
--
--   EXPLAIN (ANALYZE, BUFFERS)
--   SELECT * FROM auditoria.registro_cambios
--    WHERE tabla = 'regla_alarma' AND fecha_hora >= now() - INTERVAL '30 days'
--    ORDER BY fecha_hora DESC;
--
-- Nota para C-02: con pocos datos el planificador elige Seq Scan igual, porque
-- para una tabla chica es más barato. Para que el EXPLAIN sea representativo hay
-- que correrlo después de una carga con volumen, o forzar la comparación con
-- SET enable_seqscan = off.
-- ----------------------------------------------------------------------------
