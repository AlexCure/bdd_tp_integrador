-- Consulta: Eventos de alarma por regla en los últimos 30 días
-- Propósito: medir frecuencia de incidentes y priorizar atención.
-- Responde: "¿Qué alarmas están ocurriendo con mayor frecuencia?"

SELECT
    ra.id_regla,
    ra.descripcion,
    COUNT(*) AS total_eventos
FROM evento_alarma ea
JOIN regla_alarma ra
    ON ra.id_regla = ea.id_regla
WHERE ea.fecha_hora >= NOW() - INTERVAL '30 days'
GROUP BY ra.id_regla, ra.descripcion
ORDER BY total_eventos DESC;