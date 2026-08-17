-- ============================================================================
-- verificacion_seguridad.sql
-- TP Integrador BDIA — CEIA FIUBA 2026 · tarea D-01 (Seguridad y arquitectura)
--
-- Comprueba que los controles definidos en 04_roles_permisos.sql,
-- 05_auditoria.sql y 06_rls_aislamiento.sql efectivamente funcionan.
--
-- Un GRANT escrito no es un permiso verificado: este script ejercita cada
-- control desde el rol que corresponde y muestra si el motor permite o rechaza
-- la operación. Es la evidencia de que la estrategia de seguridad del §13 está
-- implementada y no sólo declarada.
--
-- Uso:
--     docker exec -i bdia_tp psql -U postgres -d bdia_tp < anexos/verificacion_seguridad.sql
--
-- Corre entero dentro de una transacción que termina en ROLLBACK: crea sus
-- propios datos de prueba (todos prefijados con "ZZ"), los usa y no deja nada.
-- Puede ejecutarse sobre una base vacía o ya cargada, y las veces que haga falta.
-- ============================================================================

\set ON_ERROR_STOP on
\pset border 2

BEGIN;


-- ----------------------------------------------------------------------------
-- 1. Datos de prueba
--
-- Dos campos de distinto dueño, un dispositivo en cada uno y una medición por
-- dispositivo. Es el mínimo para poder demostrar aislamiento: hace falta un
-- "otro campo" que el usuario no deba ver.
-- ----------------------------------------------------------------------------

INSERT INTO campo (nombre, ubicacion, superficie) VALUES
    ('ZZ Campo Prueba A', 'Pergamino',     100),
    ('ZZ Campo Prueba B', 'Venado Tuerto', 100);

INSERT INTO lote (id_campo, nombre, superficie)
SELECT id_campo, 'ZZ Lote', 10 FROM campo WHERE nombre LIKE 'ZZ Campo Prueba%';

INSERT INTO sector (id_lote, nombre)
SELECT id_lote, 'ZZ' FROM lote WHERE nombre = 'ZZ Lote';

INSERT INTO categoria_dispositivo (nombre) VALUES ('ZZ Categoria');
INSERT INTO tipo_dispositivo (id_categoria, nombre)
SELECT id_categoria, 'ZZ Tipo' FROM categoria_dispositivo WHERE nombre = 'ZZ Categoria';

INSERT INTO dispositivo (
    id_tipo, fabricante, modelo, numero_serie, dev_eui, app_eui,
    app_key, at_pin, ota_pin, intervalo_transmision, estado_operativo, estado_comunicacion)
SELECT td.id_tipo, 'ZZ', 'ZZ', s.serie, s.serie, 'ZZ',
       'CLAVE_LORAWAN_SECRETA', '0000', '0000', 900, 'on', 'connected'
  FROM tipo_dispositivo td
 CROSS JOIN (VALUES ('ZZ-SN-A'), ('ZZ-SN-B')) AS s(serie)
 WHERE td.nombre = 'ZZ Tipo';

-- Cada dispositivo se instala en el sector de su campo homónimo.
INSERT INTO instalacion_dispositivo (id_dispositivo, id_sector)
SELECT d.id_dispositivo, s.id_sector
  FROM dispositivo d
  JOIN lote  l ON l.nombre = 'ZZ Lote'
  JOIN campo c ON c.id_campo = l.id_campo
  JOIN sector s ON s.id_lote = l.id_lote
 WHERE d.numero_serie IN ('ZZ-SN-A', 'ZZ-SN-B')
   AND right(d.numero_serie, 1) = right(c.nombre, 1);

INSERT INTO gateway (nombre) VALUES ('ZZ Gateway');

INSERT INTO medicion (id_dispositivo, id_gateway, valores_medidos, rssi, snr, contador_mensajes)
SELECT d.id_dispositivo, g.id_gateway, '{"humedad_n1": 21.5}'::jsonb, -95, 7.0, 1
  FROM dispositivo d CROSS JOIN gateway g
 WHERE d.numero_serie IN ('ZZ-SN-A', 'ZZ-SN-B')
   AND g.nombre = 'ZZ Gateway';

-- Usuaria de prueba: perfil Operador, habilitada ÚNICAMENTE en el campo A.
INSERT INTO perfil (nombre, descripcion) VALUES ('Operador', 'ZZ perfil de prueba');

INSERT INTO usuario (nombre, apellido, email, contrasena, id_perfil)
SELECT 'ZZ', 'Prueba', 'zz.prueba@ejemplo.com', 'clave_original_en_claro', id_perfil
  FROM perfil WHERE descripcion = 'ZZ perfil de prueba';

INSERT INTO seguridad.acceso_campo (id_usuario, id_campo)
SELECT u.id_usuario, c.id_campo
  FROM usuario u, campo c
 WHERE u.email = 'zz.prueba@ejemplo.com'
   AND c.nombre = 'ZZ Campo Prueba A';


-- ----------------------------------------------------------------------------
-- 2. Arnés de verificación
--
-- Ejecuta una consulta bajo un rol determinado y compara con lo esperado:
--   'verdadero' → la consulta debe devolver TRUE
--   'denegado'  → el motor debe rechazar la operación por falta de privilegios
-- ----------------------------------------------------------------------------

CREATE TEMP TABLE resultado (
    orden      SERIAL,
    control    TEXT,
    caso       TEXT,
    rol        TEXT,
    esperado   TEXT,
    obtenido   TEXT,
    veredicto  TEXT
) ON COMMIT DROP;

CREATE FUNCTION pg_temp.chequear(
    p_control  text,
    p_caso     text,
    p_rol      text,
    p_email    text,   -- usuario de aplicación a declarar (NULL = sin contexto)
    p_sql      text,
    p_esperado text
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_res      boolean;
    v_obtenido text;
    v_ok       boolean;
BEGIN
    -- El contexto de aplicación se fija ANTES de cambiar de rol: la consulta a
    -- usuario se hace todavía como postgres.
    IF p_email IS NOT NULL THEN
        PERFORM set_config('app.id_usuario',
                           (SELECT id_usuario::text FROM usuario WHERE email = p_email),
                           true);
    ELSE
        PERFORM set_config('app.id_usuario', '', true);
    END IF;

    BEGIN
        EXECUTE format('SET LOCAL ROLE %I', p_rol);
        EXECUTE p_sql INTO v_res;
        v_obtenido := CASE WHEN v_res THEN 'devolvió verdadero' ELSE 'devolvió falso' END;
        v_ok       := (p_esperado = 'verdadero' AND v_res);
    EXCEPTION
        WHEN insufficient_privilege THEN
            v_obtenido := 'rechazado por el motor';
            v_ok       := (p_esperado = 'denegado');
    END;

    RESET ROLE;

    INSERT INTO resultado (control, caso, rol, esperado, obtenido, veredicto)
    VALUES (p_control, p_caso, p_rol, p_esperado, v_obtenido,
            CASE WHEN v_ok THEN 'PASA' ELSE '>>> FALLA' END);
END;
$$;


-- ----------------------------------------------------------------------------
-- 3. Controles
-- ----------------------------------------------------------------------------

-- 3.1 Credenciales LoRaWAN: escribibles por quien las administra, ilegibles ---

SELECT pg_temp.chequear('Credenciales', 'El Operador NO puede leer app_key',
    'app_operador', NULL,
    $q$ SELECT count(*) > 0 FROM dispositivo WHERE app_key IS NOT NULL $q$,
    'denegado');

SELECT pg_temp.chequear('Credenciales', 'El Configurador NO puede leer app_key',
    'app_configurador', 'zz.prueba@ejemplo.com',
    $q$ SELECT count(*) > 0 FROM dispositivo WHERE app_key IS NOT NULL $q$,
    'denegado');

SELECT pg_temp.chequear('Credenciales', 'El Configurador SÍ puede rotar app_key (columna de sólo escritura)',
    'app_configurador', 'zz.prueba@ejemplo.com',
    $q$ WITH u AS (UPDATE dispositivo SET app_key = 'CLAVE_ROTADA'
                    WHERE numero_serie = 'ZZ-SN-A' RETURNING 1)
        SELECT count(*) > 0 FROM u $q$,
    'verdadero');

SELECT pg_temp.chequear('Credenciales', 'El Administrador SÍ puede leer app_key',
    'app_administrador', NULL,
    $q$ SELECT count(*) > 0 FROM dispositivo WHERE numero_serie = 'ZZ-SN-A' AND app_key IS NOT NULL $q$,
    'verdadero');

-- 3.2 Contraseñas ------------------------------------------------------------

SELECT pg_temp.chequear('Contraseñas', 'La contraseña NO queda almacenada en claro',
    'postgres', NULL,
    $q$ SELECT contrasena <> 'clave_original_en_claro' AND contrasena LIKE '$2%'
          FROM usuario WHERE email = 'zz.prueba@ejemplo.com' $q$,
    'verdadero');

SELECT pg_temp.chequear('Contraseñas', 'El login funciona sin dar acceso a la tabla usuario',
    'app_operador', NULL,
    $q$ SELECT count(*) = 1 FROM seguridad.verificar_credenciales(
            'zz.prueba@ejemplo.com', 'clave_original_en_claro') $q$,
    'verdadero');

SELECT pg_temp.chequear('Contraseñas', 'Una contraseña incorrecta es rechazada',
    'app_operador', NULL,
    $q$ SELECT count(*) = 0 FROM seguridad.verificar_credenciales(
            'zz.prueba@ejemplo.com', 'clave_equivocada') $q$,
    'verdadero');

SELECT pg_temp.chequear('Datos personales', 'El Operador NO accede a la tabla usuario',
    'app_operador', NULL,
    $q$ SELECT count(*) > 0 FROM usuario $q$,
    'denegado');

-- 3.3 Ingesta: escribe pero no lee -------------------------------------------

-- Resuelve el dispositivo por dev_eui: es el identificador que viaja en el
-- uplink LoRaWAN y la única columna de dispositivo que la ingesta puede leer.
-- Con numero_serie el INSERT falla, y está bien que falle.
SELECT pg_temp.chequear('Ingesta', 'La ingesta SÍ puede insertar mediciones',
    'svc_ingesta', NULL,
    $q$ WITH i AS (INSERT INTO medicion (id_dispositivo, id_gateway, valores_medidos, contador_mensajes)
                   SELECT d.id_dispositivo, g.id_gateway, '{"humedad_n1": 30}'::jsonb, 2
                     FROM dispositivo d, gateway g
                    WHERE d.dev_eui = 'ZZ-SN-A' AND g.nombre = 'ZZ Gateway'
                   RETURNING 1)
        SELECT count(*) > 0 FROM i $q$,
    'verdadero');

SELECT pg_temp.chequear('Ingesta', 'La ingesta NO puede leer el histórico de mediciones',
    'svc_ingesta', NULL,
    $q$ SELECT count(*) > 0 FROM medicion $q$,
    'denegado');

-- 3.4 Rol analítico: la superficie que ve una aplicación de IA ---------------

SELECT pg_temp.chequear('Rol analítico (IA)', 'SÍ puede leer la vista analítica',
    'svc_analitico', NULL,
    $q$ SELECT count(*) > 0 FROM v_medicion_analitica $q$,
    'verdadero');

SELECT pg_temp.chequear('Rol analítico (IA)', 'NO puede leer la tabla medicion',
    'svc_analitico', NULL,
    $q$ SELECT count(*) > 0 FROM medicion $q$,
    'denegado');

SELECT pg_temp.chequear('Rol analítico (IA)', 'NO puede leer datos personales',
    'svc_analitico', NULL,
    $q$ SELECT count(*) > 0 FROM usuario $q$,
    'denegado');

SELECT pg_temp.chequear('Rol analítico (IA)', 'NO puede leer la ficha del dispositivo',
    'svc_analitico', NULL,
    $q$ SELECT count(*) > 0 FROM dispositivo $q$,
    'denegado');

SELECT pg_temp.chequear('Rol analítico (IA)', 'La vista analítica NO expone datos personales',
    'svc_analitico', NULL,
    $q$ SELECT NOT EXISTS (
            SELECT 1 FROM information_schema.columns
             WHERE table_name = 'v_medicion_analitica'
               AND column_name IN ('email', 'contrasena', 'app_key', 'at_pin', 'ota_pin')) $q$,
    'verdadero');

-- 3.5 Aislamiento por establecimiento ----------------------------------------

SELECT pg_temp.chequear('Aislamiento', 'La operadora SÍ ve el campo en el que está habilitada',
    'app_operador', 'zz.prueba@ejemplo.com',
    $q$ SELECT count(*) = 1 FROM campo WHERE nombre = 'ZZ Campo Prueba A' $q$,
    'verdadero');

SELECT pg_temp.chequear('Aislamiento', 'La operadora NO ve el campo ajeno',
    'app_operador', 'zz.prueba@ejemplo.com',
    $q$ SELECT count(*) = 0 FROM campo WHERE nombre = 'ZZ Campo Prueba B' $q$,
    'verdadero');

SELECT pg_temp.chequear('Aislamiento', 'La operadora NO ve mediciones del campo ajeno',
    'app_operador', 'zz.prueba@ejemplo.com',
    $q$ SELECT count(*) = 0
          FROM medicion m JOIN dispositivo d ON d.id_dispositivo = m.id_dispositivo
         WHERE d.numero_serie = 'ZZ-SN-B' $q$,
    'verdadero');

SELECT pg_temp.chequear('Aislamiento', 'Sin contexto de usuario no se ve NADA (default cerrado)',
    'app_operador', NULL,
    $q$ SELECT count(*) = 0 FROM campo WHERE nombre LIKE 'ZZ Campo Prueba%' $q$,
    'verdadero');

SELECT pg_temp.chequear('Aislamiento', 'La vista analítica NO es un desvío para el Operador',
    'app_operador', 'zz.prueba@ejemplo.com',
    $q$ SELECT count(*) > 0 FROM v_medicion_analitica $q$,
    'denegado');

-- 3.6 Auditoría --------------------------------------------------------------

SELECT pg_temp.chequear('Auditoría', 'La rotación de credencial quedó registrada',
    'app_administrador', NULL,
    $q$ SELECT count(*) > 0 FROM auditoria.registro_cambios
         WHERE tabla = 'dispositivo' AND operacion = 'UPDATE'
           AND 'app_key' = ANY(columnas_modificadas) $q$,
    'verdadero');

SELECT pg_temp.chequear('Auditoría', 'PERO la credencial NO quedó guardada en la auditoría',
    'app_administrador', NULL,
    $q$ SELECT count(*) = 0 FROM auditoria.registro_cambios
         WHERE datos_nuevos::text LIKE '%CLAVE_ROTADA%'
            OR datos_anteriores::text LIKE '%CLAVE_LORAWAN_SECRETA%' $q$,
    'verdadero');

SELECT pg_temp.chequear('Auditoría', 'Tampoco quedó guardado el hash de contraseña',
    'app_administrador', NULL,
    $q$ SELECT count(*) = 0 FROM auditoria.registro_cambios
         WHERE tabla = 'usuario' AND datos_nuevos->>'contrasena' <> '***' $q$,
    'verdadero');

SELECT pg_temp.chequear('Auditoría', 'La auditoría es inmutable: no admite DELETE',
    'app_administrador', NULL,
    $q$ WITH d AS (DELETE FROM auditoria.registro_cambios RETURNING 1)
        SELECT count(*) >= 0 FROM d $q$,
    'denegado');

SELECT pg_temp.chequear('Auditoría', 'El Operador NO accede al registro de auditoría',
    'app_operador', NULL,
    $q$ SELECT count(*) > 0 FROM auditoria.registro_cambios $q$,
    'denegado');


-- ----------------------------------------------------------------------------
-- 4. Resultado
-- ----------------------------------------------------------------------------

SELECT control, caso, rol, esperado, obtenido, veredicto
  FROM resultado
 ORDER BY orden;

SELECT
    count(*)                                   AS controles,
    count(*) FILTER (WHERE veredicto = 'PASA') AS pasan,
    count(*) FILTER (WHERE veredicto <> 'PASA') AS fallan
  FROM resultado;

-- Nada de lo anterior se conserva: los datos ZZ y las mediciones insertadas
-- durante la prueba desaparecen al deshacer la transacción.
ROLLBACK;
