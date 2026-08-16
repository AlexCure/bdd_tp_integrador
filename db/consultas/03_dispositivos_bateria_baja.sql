-- Consulta: Dispositivos con batería baja
-- Propósito: detectar equipos que requieren mantenimiento o reemplazo.
-- Responde: "¿Qué dispositivos tienen batería crítica?"

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