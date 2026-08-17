-- ============================================================================
-- 06_rls_aislamiento.sql
-- TP Integrador BDIA — CEIA FIUBA 2026 · tarea D-01 (Seguridad y arquitectura)
--
-- Aislamiento por establecimiento mediante Row Level Security (RLS).
--
-- Los perfiles de 04_roles_permisos.sql responden "qué puede hacer un usuario".
-- Falta la otra mitad: "sobre qué filas". Sin esto, un operador contratado por
-- el Campo Norte consulta las mediciones del Campo Sur, y la plataforma no puede
-- dar servicio a más de un establecimiento —ni a un contratista que trabaja para
-- varios— sin exponer los datos de unos a otros.
--
-- Se ejecuta DESPUÉS de 04_roles_permisos.sql.
-- Idempotente: puede reejecutarse sobre una base ya inicializada.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Qué campos ve cada usuario
--
-- Relación N:M entre usuario y campo. Es la única tabla que agrega este script
-- al modelo, y hay que decidir en equipo si se incorpora al modelo lógico (A-02)
-- o queda documentada como parte de la arquitectura de seguridad.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS seguridad.acceso_campo (
    id_usuario INTEGER NOT NULL REFERENCES usuario(id_usuario) ON DELETE CASCADE,
    id_campo   INTEGER NOT NULL REFERENCES campo(id_campo)     ON DELETE CASCADE,
    fecha_alta TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_acceso_campo PRIMARY KEY (id_usuario, id_campo)
);

COMMENT ON TABLE seguridad.acceso_campo IS
    'Campos que cada usuario tiene habilitados. Base de las políticas de aislamiento.';

GRANT SELECT, INSERT, DELETE ON seguridad.acceso_campo TO rol_administrador;


-- ----------------------------------------------------------------------------
-- 2. Funciones de contexto
--
-- Las políticas necesitan saber quién pregunta. La identidad de aplicación llega
-- por la variable de sesión app.id_usuario, que la aplicación fija al tomar una
-- conexión del pool:
--
--     SET app.id_usuario = '42';
--
-- Es la misma variable que usa la auditoría (05), de modo que hay un único punto
-- donde la aplicación declara quién está operando.
--
-- IMPORTANTE: si la variable no está fijada, usuario_actual() devuelve NULL y las
-- políticas no dejan ver NADA. El default es cerrado, no abierto: olvidarse de
-- fijar el contexto produce una pantalla vacía, no una fuga.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION seguridad.usuario_actual()
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.id_usuario', true), '')::integer;
$$;

-- Roles que operan sobre toda la plataforma y por lo tanto no se filtran por
-- campo: el Administrador (gestiona la plataforma completa) y la ingesta (recibe
-- uplinks de todos los gateways, sin contexto de usuario).
CREATE OR REPLACE FUNCTION seguridad.sin_restriccion_de_campo()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT pg_has_role(current_user, 'rol_administrador', 'MEMBER')
        OR pg_has_role(current_user, 'rol_ingesta',       'MEMBER');
$$;

-- SECURITY DEFINER: consulta seguridad.acceso_campo sin que el rol que ejecuta
-- necesite privilegios sobre esa tabla. Si el usuario pudiera escribirla, se
-- otorgaría acceso a sí mismo; ni siquiera necesita poder leerla.
CREATE OR REPLACE FUNCTION seguridad.campos_visibles()
RETURNS SETOF integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = seguridad, public, pg_temp
AS $$
    SELECT ac.id_campo
      FROM seguridad.acceso_campo ac
     WHERE ac.id_usuario = seguridad.usuario_actual();
$$;

-- Lotes y dispositivos derivados de esos campos. Se resuelven en funciones
-- SECURITY DEFINER en lugar de subconsultas dentro de las políticas para evitar
-- que la política de una tabla dispare la evaluación de la política de otra:
-- además del costo, las dependencias circulares entre políticas terminan en
-- errores de recursión difíciles de diagnosticar.
CREATE OR REPLACE FUNCTION seguridad.lotes_visibles()
RETURNS SETOF integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = seguridad, public, pg_temp
AS $$
    SELECT l.id_lote
      FROM lote l
     WHERE l.id_campo IN (SELECT seguridad.campos_visibles());
$$;

-- Un dispositivo se considera visible si su instalación VIGENTE cae en un campo
-- habilitado. La instalación es polimórfica (campo, sector o pivote), así que hay
-- que resolver las tres ramas hasta el campo.
--
-- Los dispositivos SIN instalación activa son visibles para todos: son el stock
-- todavía no asignado. Sin esta salvedad, un dispositivo recién dado de alta
-- sería invisible para el Configurador que tiene que instalarlo — el aislamiento
-- volvería imposible la operación que lo precede.
CREATE OR REPLACE FUNCTION seguridad.dispositivos_visibles()
RETURNS SETOF integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = seguridad, public, pg_temp
AS $$
    SELECT d.id_dispositivo
      FROM dispositivo d
      LEFT JOIN instalacion_dispositivo i
             ON i.id_dispositivo = d.id_dispositivo
            AND i.fecha_fin IS NULL
      LEFT JOIN sector s ON s.id_sector = i.id_sector
      LEFT JOIN lote   l ON l.id_lote   = s.id_lote
      LEFT JOIN pivote p ON p.id_pivote = i.id_pivote
     WHERE i.id_instalacion IS NULL                    -- sin instalar: stock común
        OR COALESCE(i.id_campo, l.id_campo, p.id_campo)
           IN (SELECT seguridad.campos_visibles());
$$;


-- ----------------------------------------------------------------------------
-- 3. Políticas
--
-- Se habilita RLS sobre la jerarquía del establecimiento, sobre el inventario de
-- dispositivos y sobre las mediciones.
--
-- Dos aclaraciones sobre el alcance:
--
--   a) El dueño de las tablas (postgres) y los superusuarios NO están sujetos a
--      RLS salvo que se declare FORCE ROW LEVEL SECURITY. No se declara, y es
--      intencional: db/datos/main.py carga la base como postgres y debe poder
--      escribir en todos los campos. Ninguna aplicación debería conectarse con
--      ese rol (ver punto 8 de 04_roles_permisos.sql).
--
--   b) Las políticas son permisivas y se combinan con OR. Por eso conviven una
--      política de aislamiento y una de excepción por rol, en lugar de una sola
--      expresión con todos los casos mezclados.
-- ----------------------------------------------------------------------------

-- 3.1 Jerarquía del establecimiento ------------------------------------------

ALTER TABLE campo  ENABLE ROW LEVEL SECURITY;
ALTER TABLE lote   ENABLE ROW LEVEL SECURITY;
ALTER TABLE sector ENABLE ROW LEVEL SECURITY;
ALTER TABLE pivote ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_campo_aislamiento ON campo;
CREATE POLICY pol_campo_aislamiento ON campo
    FOR ALL
    USING      ((SELECT seguridad.sin_restriccion_de_campo()) OR id_campo IN (SELECT seguridad.campos_visibles()))
    WITH CHECK ((SELECT seguridad.sin_restriccion_de_campo()) OR id_campo IN (SELECT seguridad.campos_visibles()));

DROP POLICY IF EXISTS pol_lote_aislamiento ON lote;
CREATE POLICY pol_lote_aislamiento ON lote
    FOR ALL
    USING      ((SELECT seguridad.sin_restriccion_de_campo()) OR id_campo IN (SELECT seguridad.campos_visibles()))
    WITH CHECK ((SELECT seguridad.sin_restriccion_de_campo()) OR id_campo IN (SELECT seguridad.campos_visibles()));

DROP POLICY IF EXISTS pol_pivote_aislamiento ON pivote;
CREATE POLICY pol_pivote_aislamiento ON pivote
    FOR ALL
    USING      ((SELECT seguridad.sin_restriccion_de_campo()) OR id_campo IN (SELECT seguridad.campos_visibles()))
    WITH CHECK ((SELECT seguridad.sin_restriccion_de_campo()) OR id_campo IN (SELECT seguridad.campos_visibles()));

-- sector no tiene id_campo: se filtra por su lote.
DROP POLICY IF EXISTS pol_sector_aislamiento ON sector;
CREATE POLICY pol_sector_aislamiento ON sector
    FOR ALL
    USING      ((SELECT seguridad.sin_restriccion_de_campo()) OR id_lote IN (SELECT seguridad.lotes_visibles()))
    WITH CHECK ((SELECT seguridad.sin_restriccion_de_campo()) OR id_lote IN (SELECT seguridad.lotes_visibles()));

-- 3.2 Dispositivos e instalaciones -------------------------------------------

ALTER TABLE dispositivo             ENABLE ROW LEVEL SECURITY;
ALTER TABLE instalacion_dispositivo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_dispositivo_aislamiento ON dispositivo;
CREATE POLICY pol_dispositivo_aislamiento ON dispositivo
    FOR ALL
    USING      ((SELECT seguridad.sin_restriccion_de_campo()) OR id_dispositivo IN (SELECT seguridad.dispositivos_visibles()))
    WITH CHECK ((SELECT seguridad.sin_restriccion_de_campo()) OR id_dispositivo IN (SELECT seguridad.dispositivos_visibles()));

DROP POLICY IF EXISTS pol_instalacion_aislamiento ON instalacion_dispositivo;
CREATE POLICY pol_instalacion_aislamiento ON instalacion_dispositivo
    FOR ALL
    USING      ((SELECT seguridad.sin_restriccion_de_campo()) OR id_dispositivo IN (SELECT seguridad.dispositivos_visibles()))
    WITH CHECK ((SELECT seguridad.sin_restriccion_de_campo()) OR id_dispositivo IN (SELECT seguridad.dispositivos_visibles()));

-- 3.3 Mediciones -------------------------------------------------------------
--
-- Es la tabla caliente del sistema y la que más peso tiene esta decisión.
--
-- La política filtra por dispositivo visible en lugar de reconstruir la cadena
-- medición → instalación → sector → lote → campo en cada fila.
--
-- Sobre el (SELECT ...) que envuelve a sin_restriccion_de_campo(): no es adorno,
-- es la diferencia entre ~27 ms y ~7 ms sobre 50.000 mediciones.
--
-- Declarar una función STABLE NO garantiza que el motor la evalúe una sola vez.
-- Escrita directamente en la política, la llamada se incorpora al Filter del plan
-- y se ejecuta UNA VEZ POR FILA: con dos pg_has_role() adentro, son 100.000
-- resoluciones de pertenencia a rol para contar unos cientos de filas. Envolverla en una
-- subconsulta escalar la convierte en un InitPlan, que el planificador evalúa una
-- sola vez antes de recorrer la tabla.
--
-- Medido sobre la carga de popular_tablas() (50.000 mediciones, PostgreSQL 16):
--
--   sin RLS (dueño de la tabla)          ~0,2 ms
--   RLS con la llamada directa           ~27 ms
--   RLS con la llamada como InitPlan      ~7 ms
--
-- El recorrido sigue siendo secuencial: el predicado de seguridad se evalúa antes
-- que el del usuario, de modo que el índice sobre fecha_hora no llega a aplicarse.
-- Se probó además desnormalizar id_campo dentro de medicion con su propio índice
-- —la salida "obvia"— y NO cambió nada: el costo no
-- estaba en resolver el campo sino en la llamada por fila. Por eso la columna
-- desnormalizada no se agrega: sería complejidad y un dato duplicado a mantener,
-- a cambio de nada. Ver §13.7.

ALTER TABLE medicion      ENABLE ROW LEVEL SECURITY;
ALTER TABLE evento_alarma ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_medicion_aislamiento ON medicion;
CREATE POLICY pol_medicion_aislamiento ON medicion
    FOR ALL
    USING      ((SELECT seguridad.sin_restriccion_de_campo()) OR id_dispositivo IN (SELECT seguridad.dispositivos_visibles()))
    WITH CHECK ((SELECT seguridad.sin_restriccion_de_campo()) OR id_dispositivo IN (SELECT seguridad.dispositivos_visibles()));

-- evento_alarma no referencia al dispositivo: sólo a la regla. El evento se
-- filtra por los dispositivos alcanzados por esa regla; si la regla no aplica a
-- ningún dispositivo visible, el evento no se ve.
DROP POLICY IF EXISTS pol_evento_alarma_aislamiento ON evento_alarma;
CREATE POLICY pol_evento_alarma_aislamiento ON evento_alarma
    FOR ALL
    USING (
        (SELECT seguridad.sin_restriccion_de_campo())
        OR EXISTS (
            SELECT 1
              FROM alarma_dispositivo ad
             WHERE ad.id_regla_alarma = evento_alarma.id_regla
               AND ad.id_dispositivo IN (SELECT seguridad.dispositivos_visibles())
        )
    )
    WITH CHECK (true);   -- la ingesta escribe eventos de cualquier campo


-- ----------------------------------------------------------------------------
-- 4. Alta de accesos
--
-- Función de conveniencia para que el Administrador habilite un campo a un
-- usuario sin escribir directamente en la tabla.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION seguridad.otorgar_acceso_campo(
    p_id_usuario integer,
    p_id_campo   integer
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = seguridad, public, pg_temp
AS $$
    INSERT INTO seguridad.acceso_campo (id_usuario, id_campo)
    VALUES (p_id_usuario, p_id_campo)
    ON CONFLICT (id_usuario, id_campo) DO NOTHING;
$$;

REVOKE ALL ON FUNCTION seguridad.otorgar_acceso_campo(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION seguridad.otorgar_acceso_campo(integer, integer) TO rol_administrador;


-- ----------------------------------------------------------------------------
-- 5. Cómo verificarlo
--
-- Habilitar un usuario en un campo y comprobar que sólo ve ese campo:
--
--   -- como administrador
--   SELECT seguridad.otorgar_acceso_campo(1, 1);
--
--   -- como operador, declarando el usuario de aplicación
--   SET app.id_usuario = '1';
--   SELECT nombre FROM campo;                  -- sólo el campo 1
--   SELECT count(*) FROM medicion;             -- sólo sus mediciones
--
--   RESET app.id_usuario;
--   SELECT count(*) FROM campo;                -- 0: sin contexto no se ve nada
-- ----------------------------------------------------------------------------
