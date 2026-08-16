-- Consulta: Promedio de temperatura y humedad por sector en las últimas 24 horas
-- Propósito: detectar zonas con condiciones anómalas dentro del lote.
-- Responde: "¿Qué sectores tienen condiciones más extremas?"

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