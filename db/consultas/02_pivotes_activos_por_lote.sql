-- Consulta: Pivotes activos y el lote que están regando
-- Propósito: verificar la asignación actual de pivotes para el riego operativo.
-- Responde: "¿Qué pivote está regando cada lote en este momento?"

SELECT
    p.id_pivote,
    p.nombre AS pivote,
    l.id_lote,
    l.nombre AS lote,
    ap.fecha_inicio,
    ap.fecha_fin
FROM asignacion_pivote ap
JOIN pivote p
    ON p.id_pivote = ap.id_pivote
JOIN lote l
    ON l.id_lote = ap.id_lote
WHERE ap.fecha_fin IS NULL
ORDER BY p.id_pivote; 