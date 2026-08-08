# Trabajo Práctico Integrador — Bases de Datos para Inteligencia Artificial

Diseño de una solución de datos para un **sistema de Agricultura de Precisión basado en IoT y LoRaWAN**.

Carrera de Especialización en Inteligencia Artificial (CEIA) — FIUBA, 2026.
Docente: Martín Lacheski.

## Integrantes

<!-- TODO: completar nombre y apellido de los cinco integrantes -->

- Ariel Matías Cabello
- Alex
- Andrés
- Alan
- Federico

## Caso de uso elegido

**Caso 3 — Monitoreo IoT con análisis predictivo.**

Un establecimiento agrícola opera dispositivos IoT distribuidos en campo (sondas de suelo, estaciones
meteorológicas, sensores de riego) que transmiten mediciones de forma continua a través de una red LoRaWAN.

## Descripción breve de la solución

La solución centraliza las mediciones generadas por los dispositivos, administra la infraestructura del
establecimiento (campos, lotes, sectores y pivotes de riego), conserva el historial de instalación de cada
dispositivo y de asignación de cada pivote, y expone la información necesaria para el monitoreo en tiempo real,
la gestión del riego, la generación de alarmas y futuras aplicaciones de Inteligencia Artificial.

## Datos principales identificados

<!-- TODO: resumir las entidades principales y la clasificación de datos (estructurados, semiestructurados,
     operacionales, analíticos, sensibles, de auditoría). Detalle completo en docs/Informe.ipynb §2 -->

## Tecnologías propuestas

<!-- TODO: completar tras la actividad 6 (selección tecnológica). La justificación debe comparar la alternativa
     elegida contra bases NoSQL y vectoriales, no darla por sentada. -->

## Estructura del repositorio

```
.
├── README.md
├── CLAUDE.md                  Contexto del proyecto para asistentes de IA
├── TODO.md                    Seguimiento de las 12 actividades y los entregables
├── docs/                      Informe, consignas, diagramas
├── data/
│   └── ejemplos/              Datos de ejemplo que validan el modelo
├── db/
│   ├── estructura/            Scripts DDL, numerados según orden de ejecución
│   ├── datos/                 Carga de datos de ejemplo
│   ├── consultas/             Consultas representativas (mínimo 5)
│   └── indices_vistas/        Índices, vistas y vistas materializadas
├── nosql/                     Propuesta de modelo NoSQL, si el caso lo justifica
├── vectorial/                 Propuesta de modelo vectorial, si el caso lo justifica
└── anexos/                    Material complementario
```

## Instrucciones para ejecutar la implementación mínima

Requisitos: Docker, y [uv](https://docs.astral.sh/uv/) para el script de carga de datos (Python).

1. Copiar `.env.example` a `.env`. Los valores por defecto sirven para levantar todo en local; no hace falta
   tocar nada salvo que el puerto 5432 ya esté ocupado en tu máquina.

2. Levantar la base:

   ```bash
   docker compose up -d
   ```

   La primera vez que el contenedor arranca con un volumen vacío, Postgres ejecuta automáticamente todo `.sql`
   que encuentre en `db/estructura/` — así que `01_create_tables.sql` corre solo y las tablas quedan creadas
   sin ningún paso manual. Podés confirmarlo con:

   ```bash
   docker exec -i bdia_tp psql -U postgres -d bdia_tp -c "\dt"
   ```

3. Instalar las dependencias del script de datos y generar la carga de ejemplo:

   ```bash
   uv sync
   uv run python db/datos/main.py
   ```

   Esto puebla las 15 tablas (establecimiento, dispositivos, mediciones, alarmas, usuarios) respetando las
   restricciones del modelo — incluida la instalación polimórfica de dispositivos y el JSONB variable de
   `medicion` según el tipo de sensor — y exporta una muestra a `data/ejemplos/mediciones.csv`.

4. Ejecutar las consultas representativas de `db/consultas/` contra la base ya cargada (pendiente: ver
   `TODO.md` §C).

Si en algún momento hace falta reiniciar todo desde cero (por ejemplo, para repetir la carga sin datos viejos
mezclados):

```bash
docker compose down -v
docker compose up -d
```

`down -v` borra también el volumen de datos, así que la próxima vez que Postgres arranque vuelve a correr el
DDL desde cero.

## Principales decisiones de diseño

<!-- TODO: resumir las decisiones y enlazar a la sección del informe donde cada una está justificada. -->

## Consultas incluidas

<!-- TODO: listar las consultas de db/consultas/ indicando qué pregunta responde cada una. -->

## Limitaciones y posibles mejoras

<!-- TODO: completar al cierre del trabajo. -->
