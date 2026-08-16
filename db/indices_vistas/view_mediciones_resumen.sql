-- Vista: resumen de mediciones por dispositivo y hora
-- Propósito: acelerar consultas de análisis temporal y reducir trabajo repetido.
-- Útil para dashboards, monitoreo y comparación de tendencias.

CREATE VIEW v_mediciones_resumen AS
SELECT
    id_dispositivo,
    DATE_TRUNC('hour', fecha_hora) AS hora,
    AVG((valores_medidos ->> 'humedad_suelo')::numeric) AS humedad_promedio,
    AVG((valores_medidos ->> 'temperatura_suelo')::numeric) AS temp_promedio,
    AVG((valores_medidos ->> 'caudal')::numeric) AS caudal_promedio
FROM medicion
GROUP BY id_dispositivo, DATE_TRUNC('hour', fecha_hora); 