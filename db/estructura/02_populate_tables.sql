-- ============================================================================
-- POPUPLAR_TABLAS: procedimiento para popular todas las tablas con datos de prueba.
-- ============================================================================
DROP PROCEDURE IF EXISTS popular_tablas();

CREATE OR REPLACE PROCEDURE popular_tablas()
LANGUAGE plpgsql
AS $$
BEGIN
TRUNCATE TABLE
alarma_dispositivo,
evento_alarma,
regla_alarma,
medicion,
gateway,
instalacion_dispositivo,
dispositivo,
tipo_variable,
variable,
tipo_dispositivo,
categoria_dispositivo,
asignacion_pivote,
sector,
lote,
pivote,
usuario,
perfil,
campo
RESTART IDENTITY CASCADE;

INSERT INTO perfil (nombre, descripcion) VALUES
('Operador', 'Consulta dispositivos, mediciones, graficos, alarmas'),
('Configurador', 'Ademas del operador, administra configuraciones y alarmas'),
('Administrador', 'Ademas del configurador, administra usuarios y permisos');

INSERT INTO campo (nombre, ubicacion, superficie)
SELECT
'Campo ' || gs::text,
'Zona ' || gs::text,
round((50 + random() * 450)::numeric, 2)
FROM generate_series(1, 3) AS gs;

INSERT INTO lote (id_campo, nombre, superficie)
SELECT
c.id_campo,
s::text,
round((5 + random() * 45)::numeric, 2)
FROM campo c
CROSS JOIN generate_series(1, 3) AS s;

INSERT INTO sector (id_lote, nombre)
SELECT
l.id_lote,
chr(64 + s)
FROM lote l
CROSS JOIN generate_series(1, 2) AS s;

INSERT INTO pivote (id_campo, nombre, fabricante, modelo)
SELECT
c.id_campo,
'Pivote ' || s::text,
(ARRAY['John Deere', 'Valley', 'Reinke', 'Netafim'])[1 + floor(random() * 4)::int],
'Modelo ' || (100 + floor(random() * 900)::int)::text
FROM campo c
CROSS JOIN generate_series(1, 2) AS s;

INSERT INTO asignacion_pivote (id_pivote, id_lote)
SELECT
p.id_pivote,
(
SELECT l2.id_lote
FROM lote l2
WHERE l2.id_campo = p.id_campo
ORDER BY random()
LIMIT 1
)
FROM pivote p;

INSERT INTO categoria_dispositivo (nombre) VALUES
('Suelo'),
('Meteorológico'),
('Riego');

INSERT INTO tipo_dispositivo (id_categoria, nombre)
SELECT c.id_categoria, t.tipo
FROM categoria_dispositivo c
JOIN (
VALUES
('Suelo', 'Sonda de humedad'),
('Meteorológico', 'Estación meteorológica'),
('Riego', 'Caudalímetro')
) AS t(categoria, tipo)
ON t.categoria = c.nombre;

INSERT INTO variable (nombre, unidad) VALUES
('Humedad de suelo', '%'),
('Temperatura de suelo', '°C'),
('Conductividad eléctrica', 'dS/m'),
('Temperatura', '°C'),
('Humedad relativa', '%'),
('Velocidad de viento', 'km/h'),
('Radiación solar', 'W/m²'),
('Precipitaciones', 'mm'),
('Caudal', 'L/h'),
('Batería', '%');

INSERT INTO tipo_variable (id_tipo_dispositivo, id_variable)
SELECT td.id_tipo, v.id_variable
FROM (
VALUES
('Sonda de humedad', 'Humedad de suelo'),
('Sonda de humedad', 'Temperatura de suelo'),
('Sonda de humedad', 'Conductividad eléctrica'),
('Sonda de humedad', 'Batería'),
('Estación meteorológica', 'Temperatura'),
('Estación meteorológica', 'Humedad relativa'),
('Estación meteorológica', 'Velocidad de viento'),
('Estación meteorológica', 'Radiación solar'),
('Estación meteorológica', 'Precipitaciones'),
('Estación meteorológica', 'Batería'),
('Caudalímetro', 'Caudal'),
('Caudalímetro', 'Batería')
) AS m(tipo, variable)
JOIN tipo_dispositivo td ON td.nombre = m.tipo
JOIN variable v ON v.nombre = m.variable;

INSERT INTO dispositivo (
id_tipo, fabricante, modelo, numero_serie, dev_eui, app_eui, app_key,
at_pin, ota_pin, intervalo_transmision, estado_operativo, estado_comunicacion
)
SELECT
td.id_tipo,
(ARRAY['Bosch', 'Davis', 'Decagon', 'Sensirion'])[1 + floor(random() * 4)::int],
'Modelo-' || (100 + floor(random() * 900)::int)::text,
upper(substr(md5(random()::text || clock_timestamp()::text || gs::text || td.id_tipo::text), 1, 10)),
upper(substr(md5(random()::text || clock_timestamp()::text || 'dev' || gs::text), 1, 16)),
upper(substr(md5(random()::text || clock_timestamp()::text || 'app' || gs::text), 1, 16)),
upper(substr(md5(random()::text || clock_timestamp()::text || 'key' || gs::text), 1, 32)),
upper(substr(md5(random()::text || clock_timestamp()::text || 'at' || gs::text), 1, 4)),
upper(substr(md5(random()::text || clock_timestamp()::text || 'ota' || gs::text), 1, 4)),
(ARRAY[60, 300, 600])[1 + floor(random() * 3)::int],
'on',
'connected'
FROM tipo_dispositivo td
CROSS JOIN generate_series(1, 3) AS gs;

INSERT INTO instalacion_dispositivo (id_dispositivo, id_campo, id_sector, id_pivote)
SELECT
d.id_dispositivo,
CASE
WHEN td.nombre = 'Estación meteorológica' THEN (SELECT id_campo FROM campo ORDER BY random() LIMIT 1)
ELSE NULL
END,
CASE
WHEN td.nombre = 'Sonda de humedad' THEN (SELECT id_sector FROM sector ORDER BY random() LIMIT 1)
ELSE NULL
END,
CASE
WHEN td.nombre = 'Caudalímetro' THEN (SELECT id_pivote FROM pivote ORDER BY random() LIMIT 1)
ELSE NULL
END
FROM dispositivo d
JOIN tipo_dispositivo td ON td.id_tipo = d.id_tipo;

INSERT INTO gateway (nombre)
SELECT 'Gateway ' || gs::text
FROM generate_series(1, 2) AS gs;

INSERT INTO medicion (
id_dispositivo, id_gateway, fecha_hora, valores_medidos, rssi, snr, contador_mensajes
)
SELECT
d.id_dispositivo,
g.id_gateway,
now() - make_interval(mins => floor(random() * (60 * 24 * 30))::int),
CASE td.nombre
WHEN 'Sonda de humedad' THEN jsonb_build_object(
'humedad_suelo', round((10 + random() * 50)::numeric, 1),
'temperatura_suelo', round((10 + random() * 25)::numeric, 1),
'conductividad_electrica', round((0.5 + random() * 2.5)::numeric, 2),
'bateria', round((20 + random() * 80)::numeric, 1)
)
WHEN 'Estación meteorológica' THEN jsonb_build_object(
'temperatura', round((-5 + random() * 45)::numeric, 1),
'humedad_relativa', round((20 + random() * 80)::numeric, 1),
'velocidad_viento', round((random() * 60)::numeric, 1),
'radiacion_solar', round((random() * 1000)::numeric, 1),
'precipitaciones', round((random() * 20)::numeric, 1),
'bateria', round((20 + random() * 80)::numeric, 1)
)
ELSE jsonb_build_object(
'caudal', round((random() * 500)::numeric, 1),
'bateria', round((20 + random() * 80)::numeric, 1)
)
END,
round((-120 + random() * 60)::numeric, 1),
round((-20 + random() * 30)::numeric, 1),
gs
FROM generate_series(1, 500000) AS gs
CROSS JOIN LATERAL (
SELECT id_dispositivo, id_tipo
FROM dispositivo
ORDER BY random()
LIMIT 1
) AS d
JOIN tipo_dispositivo td ON td.id_tipo = d.id_tipo
CROSS JOIN LATERAL (
SELECT id_gateway
FROM gateway
ORDER BY random()
LIMIT 1
) AS g;

INSERT INTO regla_alarma (id_variable, descripcion, umbral_inferior, umbral_superior, habilitada)
SELECT v.id_variable, r.descripcion, r.umbral_inferior, r.umbral_superior, true
FROM (
VALUES
('Batería', 'Batería baja', 20::numeric, NULL::numeric),
('Temperatura de suelo', 'Temperatura suelo alta', NULL::numeric, 35::numeric),
('Humedad de suelo', 'Humedad suelo baja', 15::numeric, NULL::numeric),
('Caudal', 'Caudal fuera de rango', 10::numeric, 450::numeric)
) AS r(variable, descripcion, umbral_inferior, umbral_superior)
JOIN variable v ON v.nombre = r.variable;

INSERT INTO alarma_dispositivo (id_regla_alarma, id_dispositivo)
SELECT r.id_regla, d.id_dispositivo
FROM regla_alarma r
CROSS JOIN dispositivo d
WHERE r.descripcion = 'Batería baja';

INSERT INTO alarma_dispositivo (id_regla_alarma, id_dispositivo)
SELECT r.id_regla, d.id_dispositivo
FROM regla_alarma r
JOIN dispositivo d ON true
JOIN tipo_dispositivo td ON td.id_tipo = d.id_tipo
WHERE r.descripcion IN ('Temperatura suelo alta', 'Humedad suelo baja')
AND td.nombre = 'Sonda de humedad';

INSERT INTO alarma_dispositivo (id_regla_alarma, id_dispositivo)
SELECT r.id_regla, d.id_dispositivo
FROM regla_alarma r
JOIN dispositivo d ON true
JOIN tipo_dispositivo td ON td.id_tipo = d.id_tipo
WHERE r.descripcion = 'Caudal fuera de rango'
AND td.nombre = 'Caudalímetro';

INSERT INTO evento_alarma (id_regla, fecha_hora, valor_detectado)
SELECT
r.id_regla,
now() - make_interval(hours => floor(random() * (24 * 15))::int),
CASE
WHEN r.umbral_inferior IS NOT NULL AND r.umbral_superior IS NOT NULL THEN
CASE
WHEN random() < 0.5 THEN round((r.umbral_inferior - random() * 10)::numeric, 2)
ELSE round((r.umbral_superior + random() * 10)::numeric, 2)
END
WHEN r.umbral_inferior IS NOT NULL THEN round((r.umbral_inferior - random() * 10)::numeric, 2)
ELSE round((r.umbral_superior + random() * 10)::numeric, 2)
END
FROM regla_alarma r
CROSS JOIN generate_series(1, 3) AS gs;

INSERT INTO usuario (nombre, apellido, email, contrasena, id_perfil)
SELECT
'Usuario' || gs::text,
'Apellido' || gs::text,
'usuario' || gs::text || '_' || floor(random() * 100000)::int::text || '@tp.local',
upper(substr(md5(random()::text || clock_timestamp()::text || gs::text), 1, 12)),
(SELECT id_perfil FROM perfil ORDER BY random() LIMIT 1)
FROM generate_series(1, 6) AS gs;

RAISE NOTICE 'Carga finalizada: campo=% lote=% sector=% pivote=% dispositivo=% medicion=%',
(SELECT count(*) FROM campo),
(SELECT count(*) FROM lote),
(SELECT count(*) FROM sector),
(SELECT count(*) FROM pivote),
(SELECT count(*) FROM dispositivo),
(SELECT count(*) FROM medicion);
END;
$$;