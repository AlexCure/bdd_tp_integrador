-- ============================================================================
-- 05_auditoria.sql
-- TP Integrador BDIA — CEIA FIUBA 2026 · tarea D-01 (Seguridad y arquitectura)
--
-- Registro de cambios sobre las tablas de configuración e identidad.
--
-- El informe §2.7 declara entre los datos de auditoría los "cambios realizados
-- sobre configuraciones y alarmas". El modelo físico de 01_create_tables.sql no
-- los implementa: hoy un UPDATE sobre una regla de alarma o sobre la instalación
-- de un dispositivo no deja ningún rastro. Este script cierra esa distancia
-- entre lo relevado y lo implementado.
--
-- Se ejecuta DESPUÉS de 04_roles_permisos.sql.
-- Idempotente: puede reejecutarse sobre una base ya inicializada.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Esquema y tabla de auditoría
--
-- Vive en un esquema aparte, no en public: el registro de auditoría no es un
-- dato del negocio y no debe aparecer en un \dt ni quedar alcanzado por los
-- privilegios por defecto del esquema public.
-- ----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS auditoria;

COMMENT ON SCHEMA auditoria IS
    'Registro append-only de cambios sobre configuración e identidad. Sólo lo lee el Administrador.';

CREATE TABLE IF NOT EXISTS auditoria.registro_cambios (
    id_registro     BIGSERIAL PRIMARY KEY,
    fecha_hora      TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Doble identidad. usuario_bd es el rol con el que se abrió la conexión;
    -- usuario_app es el usuario de la aplicación, que la aplicación declara con
    --     SET app.id_usuario = '<id>';
    -- La distinción no es un lujo: con un pool de conexiones todas las sesiones
    -- comparten el mismo rol de base, y sin usuario_app la auditoría sólo puede
    -- decir "lo hizo app_configurador", que es tanto como no decir nada.
    --
    -- Si usuario_app viene nulo, el cambio se hizo por fuera de la aplicación
    -- (psql, script de carga, migración). Ver la consulta de control del punto 6.
    usuario_bd      TEXT NOT NULL,
    usuario_app     INTEGER,
    direccion_ip    INET,

    tabla           TEXT NOT NULL,
    operacion       TEXT NOT NULL,
    clave_registro  JSONB,

    datos_anteriores JSONB,
    datos_nuevos     JSONB,

    -- Qué columnas cambiaron en un UPDATE. Permite auditar la rotación de una
    -- credencial sin almacenar la credencial: el valor se enmascara, pero el
    -- hecho de que cambió queda registrado.
    columnas_modificadas TEXT[],

    CONSTRAINT ck_registro_cambios_operacion
        CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'))
);

COMMENT ON TABLE auditoria.registro_cambios IS
    'Una fila por operación de escritura sobre las tablas auditadas. Los valores sensibles se enmascaran antes de guardarse.';

CREATE INDEX IF NOT EXISTS ix_registro_cambios_fecha
    ON auditoria.registro_cambios (fecha_hora DESC);

CREATE INDEX IF NOT EXISTS ix_registro_cambios_tabla_fecha
    ON auditoria.registro_cambios (tabla, fecha_hora DESC);

-- La consulta "quién tocó este dispositivo" filtra por contenido de un JSONB,
-- igual que las de medicion.valores_medidos: mismo motivo para un índice GIN.
CREATE INDEX IF NOT EXISTS ix_registro_cambios_clave_gin
    ON auditoria.registro_cambios USING GIN (clave_registro);


-- ----------------------------------------------------------------------------
-- 2. Función de auditoría
--
-- Genérica: una sola función sirve para todas las tablas. Recibe como argumentos
-- del trigger los nombres de las columnas que forman la clave primaria, de modo
-- que también funciona con claves compuestas (alarma_dispositivo, tipo_variable).
--
-- SECURITY DEFINER es deliberado: se ejecuta con los privilegios del dueño, así
-- ningún rol de aplicación necesita INSERT sobre auditoria.registro_cambios. Un
-- usuario que puede escribir su propia auditoría puede maquillarla.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auditoria.fn_registrar_cambio()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    -- Columnas cuyo valor nunca se copia al registro de auditoría. Un log que
    -- guarda contraseñas y claves LoRaWAN convierte la pista de auditoría en el
    -- objetivo más apetecible de la base: concentra en una sola tabla los
    -- secretos de todas las demás, y encima en texto plano histórico.
    k_columnas_sensibles CONSTANT TEXT[] := ARRAY['contrasena', 'app_key', 'at_pin', 'ota_pin'];

    v_anteriores JSONB;
    v_nuevos     JSONB;
    v_clave      JSONB := '{}'::jsonb;
    v_modificadas TEXT[];
    v_col        TEXT;
    i            INTEGER;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        v_anteriores := to_jsonb(OLD);
    END IF;

    IF TG_OP <> 'DELETE' THEN
        v_nuevos := to_jsonb(NEW);
    END IF;

    -- Columnas efectivamente modificadas. Se calcula ANTES de enmascarar, para
    -- que la rotación de una credencial quede registrada como hecho.
    IF TG_OP = 'UPDATE' THEN
        SELECT array_agg(a.key ORDER BY a.key)
          INTO v_modificadas
          FROM jsonb_each(v_anteriores) a
          JOIN jsonb_each(v_nuevos)     n ON n.key = a.key
         WHERE a.value IS DISTINCT FROM n.value;
    END IF;

    -- Enmascarado de valores sensibles.
    FOREACH v_col IN ARRAY k_columnas_sensibles
    LOOP
        IF v_anteriores ? v_col THEN
            v_anteriores := jsonb_set(v_anteriores, ARRAY[v_col], '"***"'::jsonb);
        END IF;
        IF v_nuevos ? v_col THEN
            v_nuevos := jsonb_set(v_nuevos, ARRAY[v_col], '"***"'::jsonb);
        END IF;
    END LOOP;

    -- Clave primaria del registro afectado, según los argumentos del trigger.
    FOR i IN 0 .. TG_NARGS - 1
    LOOP
        v_clave := v_clave || jsonb_build_object(
            TG_ARGV[i],
            COALESCE(v_nuevos, v_anteriores) -> TG_ARGV[i]
        );
    END LOOP;

    INSERT INTO auditoria.registro_cambios (
        usuario_bd, usuario_app, direccion_ip,
        tabla, operacion, clave_registro,
        datos_anteriores, datos_nuevos, columnas_modificadas
    )
    VALUES (
        -- session_user, no current_user: dentro de una función SECURITY DEFINER
        -- current_user es el DUEÑO de la función (postgres), con lo cual toda la
        -- auditoría quedaría firmada por el mismo rol. session_user conserva el
        -- rol con el que se autenticó la conexión, que es lo que se quiere saber.
        session_user,
        -- El segundo argumento (missing_ok) evita que falle si la aplicación no
        -- declaró el usuario; en ese caso la columna queda nula y la consulta de
        -- control del punto 5 lo delata.
        NULLIF(current_setting('app.id_usuario', true), '')::integer,
        inet_client_addr(),
        TG_TABLE_NAME,
        TG_OP,
        v_clave,
        v_anteriores,
        v_nuevos,
        v_modificadas
    );

    RETURN NULL;  -- trigger AFTER: el valor de retorno se ignora
END;
$$;

COMMENT ON FUNCTION auditoria.fn_registrar_cambio() IS
    'Trigger genérico de auditoría. Recibe como argumentos las columnas de la clave primaria de la tabla auditada.';


-- ----------------------------------------------------------------------------
-- 2.1 Por qué hace falta un segundo trigger para TRUNCATE
--
-- Los triggers de fila NO se disparan con TRUNCATE: PostgreSQL vacía la tabla sin
-- recorrerla, así que no hay OLD por cada fila que registrar. El efecto práctico
-- es que la operación más destructiva del catálogo —borrar una tabla entera— es
-- justamente la que pasaría sin dejar rastro.
--
-- No es hipotético en este proyecto: el procedimiento popular_tablas() de
-- db/estructura/02_populate_tables.sql arranca con
--
--     TRUNCATE TABLE alarma_dispositivo, evento_alarma, … , campo
--         RESTART IDENTITY CASCADE;
--
-- Sin este trigger, una recarga completa de la base no aparecería en la auditoría.
--
-- El registro es necesariamente más pobre que el de fila: se anota qué tabla, quién
-- y cuándo, pero no el contenido borrado — precisamente porque el motor no lo lee.
-- Es el dato que importa: quién vació qué, y a qué hora.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auditoria.fn_registrar_truncate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO auditoria.registro_cambios (
        usuario_bd, usuario_app, direccion_ip, tabla, operacion
    )
    VALUES (
        session_user,
        NULLIF(current_setting('app.id_usuario', true), '')::integer,
        inet_client_addr(),
        TG_TABLE_NAME,
        'TRUNCATE'
    );
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION auditoria.fn_registrar_truncate() IS
    'Registra el vaciado de una tabla. TRUNCATE no dispara triggers de fila, de ahí este trigger de sentencia.';


-- ----------------------------------------------------------------------------
-- 3. Triggers sobre las tablas auditadas
--
-- Se auditan las tablas de configuración e identidad: son las que cambian por
-- decisión de una persona y las que hay que poder reconstruir ante una
-- discusión ("¿quién deshabilitó esta alarma?", "¿desde cuándo este sensor
-- figura en el sector B?").
--
-- NO se auditan medicion ni evento_alarma, a propósito. Son series de sólo
-- inserción y altísimo volumen: auditarlas duplicaría la tabla más grande del
-- sistema para registrar que la ingesta hizo lo único que sabe hacer. Su
-- trazabilidad ya está dada por fecha_hora, contador_mensajes y el gateway
-- receptor. La decisión está justificada en §13.
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_def text[];
BEGIN
    FOREACH v_def SLICE 1 IN ARRAY ARRAY[
        -- {tabla, columnas de la clave primaria separadas por coma}
        ['campo',                   'id_campo'],
        ['lote',                    'id_lote'],
        ['sector',                  'id_sector'],
        ['pivote',                  'id_pivote'],
        ['asignacion_pivote',       'id_asignacion'],
        ['gateway',                 'id_gateway'],
        ['dispositivo',             'id_dispositivo'],
        ['instalacion_dispositivo', 'id_instalacion'],
        ['tipo_dispositivo',        'id_tipo'],
        ['categoria_dispositivo',   'id_categoria'],
        ['variable',                'id_variable'],
        ['regla_alarma',            'id_regla'],
        ['alarma_dispositivo',      'id_regla_alarma,id_dispositivo'],
        ['tipo_variable',           'id_tipo_dispositivo,id_variable'],
        ['perfil',                  'id_perfil'],
        ['usuario',                 'id_usuario']
    ]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS tg_auditoria ON %I', v_def[1]);
        EXECUTE format(
            'CREATE TRIGGER tg_auditoria
                 AFTER INSERT OR UPDATE OR DELETE ON %I
                 FOR EACH ROW EXECUTE FUNCTION auditoria.fn_registrar_cambio(%s)',
            v_def[1],
            (SELECT string_agg(quote_literal(c), ', ')
               FROM unnest(string_to_array(v_def[2], ',')) AS c)
        );

        -- Segundo trigger, a nivel de sentencia, para TRUNCATE (ver punto 2.1).
        EXECUTE format('DROP TRIGGER IF EXISTS tg_auditoria_truncate ON %I', v_def[1]);
        EXECUTE format(
            'CREATE TRIGGER tg_auditoria_truncate
                 AFTER TRUNCATE ON %I
                 FOR EACH STATEMENT EXECUTE FUNCTION auditoria.fn_registrar_truncate()',
            v_def[1]
        );
    END LOOP;
END
$$;



-- ----------------------------------------------------------------------------
-- 4. La auditoría es inmutable
--
-- Un registro de auditoría que se puede editar o borrar no prueba nada. El
-- trigger impide UPDATE y DELETE incluso para el dueño de la tabla; sólo un
-- superusuario que primero desactive el trigger podría alterarla, y ese acto
-- queda a su vez en el log del servidor.
--
-- La purga por antigüedad, cuando haga falta, se implementa con particionado por
-- rango de fecha y DROP de la partición vencida (§13 y §14).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auditoria.fn_bloquear_modificacion()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'El registro de auditoría es inmutable: no se admite % sobre auditoria.registro_cambios', TG_OP
        USING ERRCODE = 'insufficient_privilege';
END;
$$;

DROP TRIGGER IF EXISTS tg_registro_cambios_inmutable ON auditoria.registro_cambios;
CREATE TRIGGER tg_registro_cambios_inmutable
    BEFORE UPDATE OR DELETE ON auditoria.registro_cambios
    FOR EACH STATEMENT
    EXECUTE FUNCTION auditoria.fn_bloquear_modificacion();


-- ----------------------------------------------------------------------------
-- 5. Permisos sobre la auditoría
--
-- Lectura sólo para el Administrador. Ningún rol recibe INSERT: las filas entran
-- únicamente por los triggers, que corren como SECURITY DEFINER.
-- ----------------------------------------------------------------------------

REVOKE ALL ON SCHEMA auditoria FROM PUBLIC;
GRANT USAGE ON SCHEMA auditoria TO rol_administrador;

REVOKE ALL ON auditoria.registro_cambios FROM PUBLIC;
GRANT SELECT ON auditoria.registro_cambios TO rol_administrador;


-- ----------------------------------------------------------------------------
-- 6. Consulta de control
--
-- Cambios sin usuario de aplicación declarado: son los que se hicieron por
-- fuera de la aplicación (psql, script de carga, migración). Que aparezcan no
-- es un error —la carga inicial de datos genera muchos—, pero en régimen esta
-- consulta debería devolver poco y nada.
--
--   SELECT fecha_hora, usuario_bd, tabla, operacion
--     FROM auditoria.registro_cambios
--    WHERE usuario_app IS NULL
--    ORDER BY fecha_hora DESC;
-- ----------------------------------------------------------------------------
