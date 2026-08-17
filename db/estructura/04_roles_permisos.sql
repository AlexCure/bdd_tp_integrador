-- ============================================================================
-- 04_roles_permisos.sql
-- TP Integrador BDIA — CEIA FIUBA 2026 · tarea D-01 (Seguridad y arquitectura)
--
-- Define el modelo de seguridad de la base: roles, privilegios de mínimo
-- privilegio, vistas de enmascaramiento y verificación de credenciales.
-- Se ejecuta DESPUÉS de 01_create_tables.sql (los GRANT necesitan las tablas).
--
-- Se ejecuta con psql (usa \set y \getenv). En el arranque del contenedor esto
-- ya sucede: docker-entrypoint-initdb.d corre los .sql con psql, en orden
-- alfabético, de ahí el prefijo numérico.
--
-- El script es idempotente: puede reejecutarse sobre una base ya inicializada.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 0. Contraseñas de los roles de aplicación
--
-- Los valores por defecto son marcadores para el entorno local. Si existe la
-- variable de entorno correspondiente, \getenv la pisa; si no existe, deja el
-- default intacto. Así el script funciona sin configuración en la máquina de
-- cada integrante, y en un entorno real las contraseñas llegan desde el gestor
-- de secretos sin quedar versionadas en el repositorio.
--
-- Para usarlo, agregar a docker-compose.yml (servicio postgres, environment):
--     PWD_OPERADOR: ${PWD_OPERADOR}
--     PWD_CONFIGURADOR: ${PWD_CONFIGURADOR}
--     PWD_ADMINISTRADOR: ${PWD_ADMINISTRADOR}
--     PWD_INGESTA: ${PWD_INGESTA}
--     PWD_ANALITICO: ${PWD_ANALITICO}
-- y las mismas claves a .env.example.
-- ----------------------------------------------------------------------------

\set pwd_operador      'cambiar_operador'
\set pwd_configurador  'cambiar_configurador'
\set pwd_administrador 'cambiar_administrador'
\set pwd_ingesta       'cambiar_ingesta'
\set pwd_analitico     'cambiar_analitico'

\getenv pwd_operador      PWD_OPERADOR
\getenv pwd_configurador  PWD_CONFIGURADOR
\getenv pwd_administrador PWD_ADMINISTRADOR
\getenv pwd_ingesta       PWD_INGESTA
\getenv pwd_analitico     PWD_ANALITICO


-- ----------------------------------------------------------------------------
-- 1. Esquema y extensiones de seguridad
--
-- pgcrypto aporta crypt() y gen_salt(), usados para almacenar las contraseñas
-- de usuario como hash bcrypt en lugar de texto plano (ver punto 6).
-- ----------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS seguridad;

COMMENT ON SCHEMA seguridad IS
    'Objetos de control de acceso: verificación de credenciales, enmascaramiento y aislamiento por campo.';


-- ----------------------------------------------------------------------------
-- 2. Cierre de los privilegios que PostgreSQL otorga por defecto
--
-- Por defecto, el pseudo-rol PUBLIC (todo rol existente y futuro) puede
-- conectarse a cualquier base y usar el esquema public. Partimos de negar todo
-- y otorgar explícitamente: es la diferencia entre una lista de excepciones y
-- una de permisos, y es lo que hace que un rol nuevo no herede acceso por
-- olvido.
-- ----------------------------------------------------------------------------

DO $$
BEGIN
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database());
END
$$;

REVOKE ALL ON SCHEMA public FROM PUBLIC;


-- ----------------------------------------------------------------------------
-- 3. Roles de grupo (NOLOGIN)
--
-- Los privilegios se otorgan a roles de grupo, nunca a personas. Un alta o baja
-- de usuario se resuelve con GRANT/REVOKE del grupo, sin volver a tocar la
-- matriz de permisos.
--
-- Los tres primeros son los perfiles del dominio (tabla perfil). Los dos
-- últimos no son perfiles de persona sino identidades de servicio, que el
-- modelo de negocio no nombra pero la arquitectura sí necesita:
--
--   rol_ingesta   — el conector del network server LoRaWAN. Sólo inserta
--                   mediciones y eventos. No lee el histórico ni credenciales.
--   rol_analitico — consumidores analíticos: BI, notebooks y, sobre todo,
--                   aplicaciones conectadas a modelos de IA. Sólo ve vistas
--                   agregadas, sin datos personales ni credenciales (§13).
--
-- CREATE ROLE no admite IF NOT EXISTS, de ahí el bloque DO contra pg_roles.
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_rol text;
BEGIN
    FOREACH v_rol IN ARRAY ARRAY[
        'rol_operador', 'rol_configurador', 'rol_administrador',
        'rol_ingesta', 'rol_analitico'
    ]
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_rol) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', v_rol);
        END IF;
    END LOOP;
END
$$;

COMMENT ON ROLE rol_operador      IS 'Perfil Operador: consulta dispositivos, mediciones y alarmas. Sin acceso a credenciales ni a datos de usuarios.';
COMMENT ON ROLE rol_configurador  IS 'Perfil Configurador: hereda Operador y administra infraestructura, dispositivos y reglas de alarma.';
COMMENT ON ROLE rol_administrador IS 'Perfil Administrador: hereda Configurador y administra usuarios, perfiles y auditoría.';
COMMENT ON ROLE rol_ingesta       IS 'Identidad de servicio: conector LoRaWAN. Sólo alta de mediciones y eventos de alarma.';
COMMENT ON ROLE rol_analitico     IS 'Identidad de servicio: BI y aplicaciones de IA. Sólo lectura de vistas analíticas sin datos sensibles.';

-- Herencia acumulativa de los perfiles del dominio: Configurador incluye todo
-- lo del Operador, y Administrador todo lo del Configurador, tal como está
-- descripto en el informe §1.3. Los roles de servicio quedan fuera de esa
-- cadena a propósito: la ingesta no es "menos que" un operador, es otra cosa.
GRANT rol_operador     TO rol_configurador;
GRANT rol_configurador TO rol_administrador;


-- ----------------------------------------------------------------------------
-- 4. Acceso a la base y al esquema
-- ----------------------------------------------------------------------------

DO $$
BEGIN
    EXECUTE format(
        'GRANT CONNECT ON DATABASE %I TO rol_operador, rol_configurador, rol_administrador, rol_ingesta, rol_analitico',
        current_database()
    );
END
$$;

GRANT USAGE ON SCHEMA public    TO rol_operador, rol_configurador, rol_administrador, rol_ingesta, rol_analitico;
GRANT USAGE ON SCHEMA seguridad TO rol_operador, rol_configurador, rol_administrador, rol_ingesta, rol_analitico;


-- ----------------------------------------------------------------------------
-- 5. Privilegios por tabla
--
-- Criterio general:
--   Operador      → SELECT sobre infraestructura, dispositivos, mediciones y alarmas.
--   Configurador  → además, escritura sobre infraestructura, dispositivos y reglas.
--   Administrador → además, usuarios y perfiles.
--   Ingesta       → INSERT sobre medicion y evento_alarma, y nada más.
--   Analítico     → ninguna tabla: sólo las vistas del punto 7.
-- ----------------------------------------------------------------------------

-- 5.1 Infraestructura del establecimiento y catálogo de dispositivos ---------

GRANT SELECT ON
    campo, lote, sector, pivote, asignacion_pivote,
    categoria_dispositivo, tipo_dispositivo, variable, tipo_variable,
    instalacion_dispositivo, gateway,
    regla_alarma, alarma_dispositivo
TO rol_operador;

GRANT INSERT, UPDATE, DELETE ON
    campo, lote, sector, pivote, asignacion_pivote,
    categoria_dispositivo, tipo_dispositivo, variable, tipo_variable,
    instalacion_dispositivo, gateway,
    regla_alarma, alarma_dispositivo
TO rol_configurador;

-- 5.2 Dispositivo: privilegios por columna -----------------------------------
--
-- app_key, at_pin y ota_pin son las credenciales LoRaWAN del dispositivo. Quien
-- las conoce puede suplantarlo e inyectar mediciones falsas, y una medición
-- falsa de humedad de suelo se traduce en una decisión de riego equivocada. No
-- son "un dato más" de la ficha del dispositivo.
--
-- dev_eui y app_eui, en cambio, son identificadores: viajan en claro en el aire
-- y no habilitan por sí solos el alta en la red. Se tratan como datos comunes.
--
-- El corte es por columna, no por tabla:
--   - Operador y Configurador leen la ficha del dispositivo SIN las credenciales.
--   - El Configurador puede escribirlas (alta y rotación de claves) sin poder
--     leerlas: son columnas de sólo escritura para su rol.
--   - Sólo el Administrador puede leerlas, y para eso están las vistas del
--     punto 7 en el uso cotidiano.

GRANT SELECT (
    id_dispositivo, id_tipo, fabricante, modelo, numero_serie,
    dev_eui, app_eui, intervalo_transmision,
    estado_operativo, estado_comunicacion
) ON dispositivo TO rol_operador;

-- INSERT sobre todas las columnas: dar de alta un dispositivo exige cargar la
-- credencial, y app_key es NOT NULL. Escribir no implica poder leer.
GRANT INSERT (
    id_tipo, fabricante, modelo, numero_serie,
    dev_eui, app_eui, app_key, at_pin, ota_pin,
    intervalo_transmision, estado_operativo, estado_comunicacion
) ON dispositivo TO rol_configurador;

GRANT UPDATE (
    id_tipo, fabricante, modelo, numero_serie,
    dev_eui, app_eui, app_key, at_pin, ota_pin,
    intervalo_transmision, estado_operativo, estado_comunicacion
) ON dispositivo TO rol_configurador;

GRANT DELETE ON dispositivo TO rol_configurador;

-- El Administrador es el único que puede leer las credenciales en claro.
GRANT SELECT ON dispositivo TO rol_administrador;

-- 5.3 Mediciones y eventos ---------------------------------------------------

GRANT SELECT ON medicion, evento_alarma TO rol_operador;

-- La ingesta escribe, no lee: si el conector se ve comprometido, el atacante
-- puede ensuciar datos nuevos, pero no exfiltrar el histórico.
GRANT INSERT ON medicion, evento_alarma TO rol_ingesta;

-- Resuelve dev_eui → id_dispositivo al recibir un uplink y refleja el estado de
-- comunicación. Nada más: no accede a app_key, porque en esta arquitectura la
-- clave vive en el network server LoRaWAN y la copia de la base es inventario.
GRANT SELECT (id_dispositivo, dev_eui, estado_operativo, estado_comunicacion)
    ON dispositivo TO rol_ingesta;
GRANT UPDATE (estado_comunicacion) ON dispositivo TO rol_ingesta;

GRANT SELECT (id_gateway, nombre) ON gateway TO rol_ingesta;

-- 5.4 Identidad: usuarios y perfiles -----------------------------------------
--
-- Ni el Operador ni el Configurador acceden a la tabla usuario. Contiene datos
-- personales (nombre, apellido, email) y el hash de contraseña; ninguna función
-- de monitoreo los necesita. El login no requiere ese permiso: se resuelve con
-- seguridad.verificar_credenciales() (punto 6).

GRANT SELECT, INSERT, UPDATE, DELETE ON usuario, perfil TO rol_administrador;

-- 5.5 Secuencias -------------------------------------------------------------
--
-- Las PK son SERIAL: sin USAGE sobre la secuencia, el INSERT falla aunque el
-- privilegio sobre la tabla esté otorgado.

GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO rol_configurador;
GRANT USAGE ON SEQUENCE medicion_id_medicion_seq, evento_alarma_id_evento_alarma_seq
    TO rol_ingesta;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO rol_administrador;

-- 5.6 Privilegios por defecto ------------------------------------------------
--
-- Sólo para secuencias. NO se define un ALTER DEFAULT PRIVILEGES que otorgue
-- SELECT sobre las tablas y vistas futuras, y la omisión es deliberada.
--
-- La primera versión de este script sí lo hacía, para que las vistas y agregados
-- continuos de C-02 quedaran legibles sin tener que volver acá. El script de
-- verificación (anexos/verificacion_seguridad.sql) mostró la consecuencia: el
-- privilegio por defecto alcanzó también a v_medicion_analitica —creada más
-- abajo, en el mismo script— y el Operador terminó con acceso de lectura a la
-- única vista que cruza todos los establecimientos. Es decir, la comodidad de no
-- repetir GRANT anuló el aislamiento por campo del punto 04, en silencio y sin
-- que ninguna línea del script dijera "otorgar acceso al Operador".
--
-- Es el mismo razonamiento del punto 2: lo que se abre por defecto se abre
-- también para lo que todavía no existe, y nadie revisa un permiso que nunca se
-- escribió. Cada vista nueva se otorga a mano.
--
-- Para C-02: los índices no necesitan permisos, pero cada vista o agregado
-- continuo que se agregue necesita su GRANT explícito.

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE ON SEQUENCES TO rol_configurador;

-- Si alguien vuelve a definir el privilegio por defecto sobre tablas, esta línea
-- lo deja sin efecto. Se ejecuta por si acaso, no porque haga falta hoy.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE SELECT ON TABLES FROM rol_operador;

-- Nota sobre TimescaleDB: medicion es una hipertabla y sus datos viven en
-- chunks del esquema _timescaledb_internal. TimescaleDB propaga a los chunks
-- los privilegios otorgados sobre la hipertabla, incluidos los de este script.
-- Conviene verificarlo tras la primera carga:
--     SELECT * FROM timescaledb_information.hypertables;
--     \dp _timescaledb_internal.*


-- ----------------------------------------------------------------------------
-- 6. Contraseñas: hash en lugar de texto plano
--
-- El DDL define usuario.contrasena como TEXT y el generador de datos
-- (db/datos/generar_datos.py) inserta la contraseña tal cual la produce Faker.
-- Cualquiera con SELECT sobre la tabla —o una copia del backup— lee las
-- contraseñas de todos.
--
-- El trigger normaliza el problema sin cambiar el esquema de B ni el script de
-- carga: intercepta el valor antes de escribirlo y guarda un hash bcrypt. Si el
-- valor ya es un hash (alta desde una aplicación que hashea) lo deja pasar, con
-- lo cual la operación es idempotente y admite ambos orígenes.
--
-- Deuda documentada en §13: bcrypt vía pgcrypto implica que la contraseña en
-- claro viaja hasta el motor. Lo correcto en producción es hashear en la
-- aplicación; el trigger es la red de contención de que nada quede en claro.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION seguridad.fn_hash_contrasena()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Un hash bcrypt empieza con $2a$, $2b$ o $2y$. Si ya viene hasheada, no
    -- se vuelve a hashear (evita el doble hash en cada UPDATE de la fila).
    IF NEW.contrasena !~ '^\$2[aby]\$' THEN
        NEW.contrasena := crypt(NEW.contrasena, gen_salt('bf', 10));
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_usuario_hash_contrasena ON usuario;
CREATE TRIGGER tg_usuario_hash_contrasena
    BEFORE INSERT OR UPDATE OF contrasena ON usuario
    FOR EACH ROW
    EXECUTE FUNCTION seguridad.fn_hash_contrasena();

-- Verificación de credenciales sin exponer la tabla.
--
-- SECURITY DEFINER: se ejecuta con los privilegios del dueño de la función
-- (postgres), de modo que el rol que la invoca puede autenticar sin tener
-- SELECT sobre usuario. El SET search_path es obligatorio en una función
-- SECURITY DEFINER: sin él, quien la llama podría anteponer un esquema propio y
-- hacer que resuelva a objetos que él controla.
--
-- La comparación crypt(p_contrasena, u.contrasena) = u.contrasena vuelve a
-- hashear el intento con la sal almacenada; nunca se descifra nada.
CREATE OR REPLACE FUNCTION seguridad.verificar_credenciales(
    p_email      text,
    p_contrasena text
)
RETURNS TABLE (id_usuario integer, nombre text, apellido text, perfil text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT u.id_usuario, u.nombre, u.apellido, p.nombre
      FROM usuario u
      JOIN perfil  p ON p.id_perfil = u.id_perfil
     WHERE u.email = p_email
       AND u.contrasena = crypt(p_contrasena, u.contrasena);
$$;

-- EXECUTE se otorga a PUBLIC por defecto: hay que revocarlo antes de asignarlo.
REVOKE ALL ON FUNCTION seguridad.verificar_credenciales(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION seguridad.verificar_credenciales(text, text)
    TO rol_operador, rol_configurador, rol_administrador;


-- ----------------------------------------------------------------------------
-- 7. Vistas
--
-- Hay dos modos de ejecución de una vista y la diferencia es de seguridad, no
-- de estilo:
--
--   security_invoker = false (por defecto) — la vista corre con los privilegios
--     de su DUEÑO. Sirve para enmascarar: un rol sin SELECT sobre la tabla base
--     ve a través de la vista exactamente las columnas que la vista expone. El
--     efecto colateral es que también saltea la seguridad a nivel de fila (RLS)
--     de las tablas base.
--
--   security_invoker = true — la vista corre con los privilegios de QUIEN LA
--     CONSULTA. No enmascara nada, pero respeta la RLS.
--
-- Las tres vistas se sueltan antes de crearse: CREATE OR REPLACE VIEW no admite
-- quitar ni reordenar columnas, así que un cambio de definición haría fallar la
-- reejecución del script sobre una base ya inicializada.
--
-- Elegir mal acá abre un agujero silencioso: una vista de conveniencia definida
-- con el modo por defecto se convierte en un camino para leer filas que la RLS
-- del punto 04 prohíbe. Cada vista de abajo declara cuál usa y por qué.
-- ----------------------------------------------------------------------------

-- 7.1 Ficha de dispositivo sin credenciales ----------------------------------
--
-- security_invoker = true: esta vista NO enmascara —las credenciales ya están
-- fuera por los privilegios de columna del punto 5.2— y sí tiene que respetar
-- el aislamiento por campo de 06_rls_aislamiento.sql.
--
-- Su utilidad es otra: resuelve los joins con tipo y categoría, y sobre todo
-- permite que la aplicación haga SELECT * sin chocar con "permission denied for
-- table dispositivo". Un SELECT * sobre la tabla falla para el Operador porque
-- alcanza columnas que no puede leer; sobre la vista funciona.

DROP VIEW IF EXISTS v_dispositivo;
CREATE VIEW v_dispositivo
WITH (security_invoker = true) AS
SELECT
    d.id_dispositivo,
    d.id_tipo,
    td.nombre AS tipo,
    cd.nombre AS categoria,
    d.fabricante,
    d.modelo,
    d.numero_serie,
    d.dev_eui,
    d.intervalo_transmision,
    d.estado_operativo,
    d.estado_comunicacion
FROM dispositivo d
JOIN tipo_dispositivo      td ON td.id_tipo      = d.id_tipo
JOIN categoria_dispositivo cd ON cd.id_categoria = td.id_categoria;

COMMENT ON VIEW v_dispositivo IS
    'Ficha operativa del dispositivo sin credenciales LoRaWAN. security_invoker: respeta el aislamiento por campo.';

GRANT SELECT ON v_dispositivo TO rol_operador, rol_configurador, rol_administrador;

-- 7.2 Usuarios sin hash de contraseña ----------------------------------------

DROP VIEW IF EXISTS v_usuario;
CREATE VIEW v_usuario AS
SELECT
    u.id_usuario,
    u.nombre,
    u.apellido,
    u.email,
    p.nombre AS perfil
FROM usuario u
JOIN perfil p ON p.id_perfil = u.id_perfil;

COMMENT ON VIEW v_usuario IS
    'Padrón de usuarios sin el hash de contraseña. Ni siquiera el Administrador necesita leer la columna para gestionar altas y bajas.';

GRANT SELECT ON v_usuario TO rol_administrador;

-- 7.3 Vista analítica: la superficie que ve la IA ----------------------------
--
-- Esta es la única puerta de rol_analitico, y está construida a la inversa de
-- las otras: no se parte de la tabla y se quitan columnas, se parte de la
-- pregunta analítica y se agrega sólo lo que ésta necesita. Una medición se
-- explica por su variable, su ubicación y su momento; el dispositivo aparece
-- como identificador y tipo, nunca con sus credenciales, y ningún dato de
-- persona entra en la vista.
--
-- El argumento está desarrollado en §13: un asistente conversacional o un
-- agente con acceso a la base responde con lo que puede leer, y todo lo que
-- pueda leer es potencialmente citable en una respuesta. El control efectivo no
-- es instruir al modelo, es que el rol no tenga el dato.

DROP VIEW IF EXISTS v_medicion_analitica;
CREATE VIEW v_medicion_analitica AS
SELECT
    m.fecha_hora,
    m.id_dispositivo,
    td.nombre AS tipo_dispositivo,
    cd.nombre AS categoria_dispositivo,
    c.id_campo,
    c.nombre  AS campo,
    l.id_lote,
    l.nombre  AS lote,
    s.id_sector,
    s.nombre  AS sector,
    m.valores_medidos,
    m.rssi,
    m.snr
FROM medicion m
JOIN dispositivo           d  ON d.id_dispositivo = m.id_dispositivo
JOIN tipo_dispositivo      td ON td.id_tipo       = d.id_tipo
JOIN categoria_dispositivo cd ON cd.id_categoria  = td.id_categoria
-- Instalación vigente en el momento de la medición: la ubicación es histórica,
-- no la actual. Un sensor reinstalado en otro sector no reescribe el pasado.
LEFT JOIN instalacion_dispositivo i
       ON i.id_dispositivo = m.id_dispositivo
      AND m.fecha_hora >= i.fecha_inicio
      AND (i.fecha_fin IS NULL OR m.fecha_hora < i.fecha_fin)
LEFT JOIN sector s ON s.id_sector = i.id_sector
LEFT JOIN lote   l ON l.id_lote   = s.id_lote
LEFT JOIN campo  c ON c.id_campo  = COALESCE(l.id_campo, i.id_campo);

COMMENT ON VIEW v_medicion_analitica IS
    'Mediciones con su ubicación histórica, sin datos personales ni credenciales. Única superficie de acceso de rol_analitico (BI e IA).';

-- Se otorga SÓLO a rol_analitico, y esto es deliberado.
--
-- La vista usa el modo por defecto (corre como su dueño), porque su propósito es
-- justamente atravesar todos los campos para poder agregar: un modelo entrenado
-- sobre un único establecimiento no sirve. Ese mismo atributo la convierte en un
-- desvío alrededor del aislamiento por campo de 06_rls_aislamiento.sql. Si se le
-- otorgara al Operador, un operador del Campo Norte leería las mediciones del
-- Campo Sur simplemente consultando la vista en lugar de la tabla.
--
-- El aislamiento del Operador y la agregación analítica son objetivos opuestos;
-- se resuelven con dos caminos distintos, no con una vista compartida.
REVOKE ALL ON v_medicion_analitica FROM PUBLIC, rol_operador, rol_configurador;
GRANT SELECT ON v_medicion_analitica TO rol_analitico;


-- 7.4 Vistas creadas fuera de este script -----------------------------------
--
-- db/indices_vistas/02_view_mediciones_resumen.sql (tarea C-02) crea
-- v_mediciones_resumen. Ese directorio NO se monta en docker-entrypoint-initdb.d
-- —sólo se monta db/estructura—, así que la vista no existe al momento de correr
-- este script y no se le puede otorgar nada por adelantado.
--
-- El bloque de abajo le asigna el permiso si ya está creada. Si no está, no hace
-- nada y avisa: alcanza con volver a ejecutar este script después de crear las
-- vistas de C-02.
--
-- ATENCIÓN — v_mediciones_resumen agrega mediciones de TODOS los campos y está
-- definida con el modo por defecto, es decir que corre con los privilegios de su
-- dueño y por lo tanto NO respeta la RLS de 06_rls_aislamiento.sql. Otorgársela
-- al Operador reproduciría exactamente el agujero descripto en §13.9. Por eso
-- acá se otorga sólo a rol_analitico.
--
-- Si la intención de C-02 era que la consulte también la aplicación de
-- monitoreo, la corrección va del lado de la vista, agregando a su definición:
--
--     CREATE VIEW v_mediciones_resumen WITH (security_invoker = true) AS …
--
-- Con eso la vista pasa a respetar el aislamiento por campo y se le puede
-- otorgar a rol_operador sin filtrar datos de otros establecimientos.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_views
                WHERE schemaname = 'public' AND viewname = 'v_mediciones_resumen') THEN
        EXECUTE 'GRANT SELECT ON v_mediciones_resumen TO rol_analitico';
        RAISE NOTICE 'v_mediciones_resumen: SELECT otorgado a rol_analitico.';
    ELSE
        RAISE NOTICE 'v_mediciones_resumen no existe todavía (se crea en db/indices_vistas/). '
                     'Reejecutar este script después de crearla.';
    END IF;
END
$$;


-- ----------------------------------------------------------------------------
-- 8. Roles de login
--
-- Roles con contraseña que representan a las aplicaciones y servicios que se
-- conectan. Los privilegios los reciben por pertenencia al grupo, nunca de
-- forma directa.
--
-- Ninguna aplicación debería conectarse como postgres. Hoy .env.example define
-- DB_USER=postgres y así corre el script de carga: aceptable para poblar la
-- base desde cero, no para operar.
--
-- La contraseña se asigna con ALTER ROLE, fuera del bloque DO, porque psql no
-- interpola variables dentro de cadenas dolarizadas.
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_par text[];
BEGIN
    FOREACH v_par SLICE 1 IN ARRAY ARRAY[
        ['app_operador',      'rol_operador'],
        ['app_configurador',  'rol_configurador'],
        ['app_administrador', 'rol_administrador'],
        ['svc_ingesta',       'rol_ingesta'],
        ['svc_analitico',     'rol_analitico']
    ]
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_par[1]) THEN
            EXECUTE format('CREATE ROLE %I LOGIN', v_par[1]);
        END IF;
        EXECUTE format('GRANT %I TO %I', v_par[2], v_par[1]);
    END LOOP;
END
$$;

ALTER ROLE app_operador      PASSWORD :'pwd_operador';
ALTER ROLE app_configurador  PASSWORD :'pwd_configurador';
ALTER ROLE app_administrador PASSWORD :'pwd_administrador';
ALTER ROLE svc_ingesta       PASSWORD :'pwd_ingesta';
ALTER ROLE svc_analitico     PASSWORD :'pwd_analitico';

-- Límite de conexiones por identidad de servicio: acota el impacto de un
-- conector en bucle o de un cliente analítico que abra sesiones sin cerrarlas.
ALTER ROLE svc_ingesta   CONNECTION LIMIT 10;
ALTER ROLE svc_analitico CONNECTION LIMIT 5;
