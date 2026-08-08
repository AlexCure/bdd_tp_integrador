-- ============================================================================
-- BLOQUE 1: Organización del establecimiento
-- Campo, Lote, Sector, Pivote, AsignaciónPivote
-- ============================================================================

CREATE TABLE campo(
    id_campo SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL,
    ubicacion TEXT NOT NULL,
    superficie NUMERIC NOT NULL
);

CREATE TABLE lote(
    id_lote SERIAL PRIMARY KEY,
    id_campo INTEGER NOT NULL REFERENCES campo(id_campo),
    nombre TEXT NOT NULL,
    superficie NUMERIC NOT NULL
);

CREATE TABLE sector(
    id_sector SERIAL PRIMARY KEY,
    id_lote INTEGER NOT NULL REFERENCES lote(id_lote),
    nombre TEXT NOT NULL
);

CREATE TABLE pivote(
    id_pivote SERIAL PRIMARY KEY,
    id_campo INTEGER NOT NULL REFERENCES campo(id_campo),
    nombre TEXT NOT NULL,
    fabricante TEXT NOT NULL,
    modelo TEXT NOT NULL
);

CREATE TABLE asignacion_pivote (
    id_asignacion SERIAL PRIMARY KEY,
    id_pivote INTEGER NOT NULL REFERENCES pivote(id_pivote),
    id_lote INTEGER NOT NULL REFERENCES lote(id_lote),
    fecha_inicio TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_fin TIMESTAMP
);

-- Un pivote solo puede tener una asignación activa (fecha_fin NULL) a la vez.
CREATE UNIQUE INDEX ux_asignacion_pivote_activa
    ON asignacion_pivote(id_pivote)
    WHERE fecha_fin IS NULL;


-- ============================================================================
-- BLOQUE 2: Dispositivos IoT
-- Categoría, Tipo, Variable, Dispositivo, InstalaciónDispositivo
-- ============================================================================

CREATE TABLE categoria_dispositivo(
    id_categoria SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL
);

CREATE TABLE tipo_dispositivo(
    id_tipo SERIAL PRIMARY KEY,
    id_categoria INTEGER NOT NULL REFERENCES categoria_dispositivo(id_categoria),
    nombre TEXT NOT NULL
);

CREATE TABLE variable(
    id_variable SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL,
    unidad TEXT NOT NULL
);

-- Tabla intermedia N:M: un tipo de dispositivo sensa varias variables.
CREATE TABLE tipo_variable(
    id_tipo_dispositivo INTEGER NOT NULL REFERENCES tipo_dispositivo(id_tipo),
    id_variable INTEGER NOT NULL REFERENCES variable(id_variable),
    PRIMARY KEY (id_tipo_dispositivo, id_variable)
);

CREATE TABLE dispositivo(
    id_dispositivo SERIAL PRIMARY KEY,
    id_tipo INTEGER NOT NULL REFERENCES tipo_dispositivo(id_tipo),
    fabricante TEXT NOT NULL,
    modelo TEXT NOT NULL,
    numero_serie TEXT NOT NULL,
    dev_eui TEXT NOT NULL,
    app_eui TEXT NOT NULL,
    app_key TEXT NOT NULL,
    at_pin TEXT NOT NULL,
    ota_pin TEXT NOT NULL,
    intervalo_transmision INTEGER NOT NULL,
    estado_operativo TEXT NOT NULL CHECK (estado_operativo IN ('on', 'off')),
    estado_comunicacion TEXT NOT NULL CHECK (estado_comunicacion IN ('connected', 'disconnected'))
);

-- Instalación polimórfica: un dispositivo se instala en un Campo, Sector o Pivote (nunca en más de uno a la vez). Historial temporal igual que asignacion_pivote.
CREATE TABLE instalacion_dispositivo(
    id_instalacion SERIAL PRIMARY KEY,
    id_dispositivo INTEGER NOT NULL REFERENCES dispositivo(id_dispositivo),
    id_campo   INTEGER REFERENCES campo(id_campo),
    id_sector  INTEGER REFERENCES sector(id_sector),
    id_pivote  INTEGER REFERENCES pivote(id_pivote),
    fecha_inicio TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_fin TIMESTAMP,
    CHECK (
        (id_campo IS NOT NULL)::INTEGER
        + (id_sector IS NOT NULL)::INTEGER
        + (id_pivote IS NOT NULL)::INTEGER = 1
    )
);

-- Un dispositivo solo puede tener una instalación activa a la vez.
CREATE UNIQUE INDEX ux_instalacion_dispositivo_activa
    ON instalacion_dispositivo(id_dispositivo)
    WHERE fecha_fin IS NULL;


-- ============================================================================
-- BLOQUE 3: Mediciones
-- Gateway, Medición
-- ============================================================================
CREATE TABLE gateway(
    id_gateway SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL
);

CREATE TABLE medicion(
    id_medicion SERIAL,
    id_dispositivo INTEGER NOT NULL REFERENCES dispositivo(id_dispositivo),
    id_gateway INTEGER NOT NULL REFERENCES gateway(id_gateway),
    fecha_hora TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valores_medidos JSONB NOT NULL,
    rssi NUMERIC,
    snr NUMERIC,
    contador_mensajes INTEGER NOT NULL,
    PRIMARY KEY(id_medicion, fecha_hora)
);

-- ============================================================================
-- BLOQUE 4: Alarmas
-- ReglaAlarma, EventoAlarma
-- ============================================================================
CREATE TABLE regla_alarma(
    id_regla SERIAL PRIMARY KEY,
    id_variable INTEGER NOT NULL REFERENCES variable(id_variable),
    descripcion TEXT NOT NULL,
    umbral_inferior NUMERIC,
    umbral_superior NUMERIC,
    habilitada BOOLEAN NOT NULL,
    CHECK (umbral_inferior IS NOT NULL OR umbral_superior IS NOT NULL)
);


CREATE TABLE evento_alarma(
    id_evento_alarma SERIAL PRIMARY KEY,
    id_regla INTEGER NOT NULL REFERENCES regla_alarma(id_regla),
    fecha_hora TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valor_detectado NUMERIC NOT NULL
);

CREATE TABLE alarma_dispositivo(
    id_regla_alarma INTEGER NOT NULL REFERENCES regla_alarma(id_regla),
    id_dispositivo INTEGER NOT NULL REFERENCES dispositivo(id_dispositivo),
    PRIMARY KEY (id_regla_alarma, id_dispositivo)
);
-- ============================================================================
-- BLOQUE 5: Usuarios
-- Perfil, Usuario
-- ============================================================================
CREATE TABLE perfil(
    id_perfil SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL CHECK (nombre IN ('Operador', 'Configurador', 'Administrador')),
    descripcion TEXT NOT NULL
);

CREATE TABLE usuario(
    id_usuario SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL,
    apellido TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    contrasena TEXT NOT NULL,
    id_perfil INTEGER NOT NULL REFERENCES perfil(id_perfil)
);

-- ============================================================================
-- Configuración especial de la tabla medicion
-- ============================================================================

-- Convierte medicion en hipertabla
SELECT create_hypertable('medicion', 'fecha_hora');

-- Índice GIN sobre el JSONB: acelera consultas que filtran por contenido de valores_medidos usando el operador @>
CREATE INDEX ix_medicion_valores_gin ON medicion USING GIN (valores_medidos);
