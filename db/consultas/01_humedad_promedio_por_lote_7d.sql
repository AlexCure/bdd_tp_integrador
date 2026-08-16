-- Consulta: Humedad promedio por lote en los últimos 7 días
-- Propósito: evaluar el estado del suelo para decidir riego o detectar zonas secas.
-- Responde: "¿Qué lotes tienen menor humedad promedio en la última semana?"

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