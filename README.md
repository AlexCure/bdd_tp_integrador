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

<!-- TODO: completar tras la actividad 7. Debe permitir levantar el esquema, cargar los datos de ejemplo y
     ejecutar las consultas representativas desde cero. -->

## Principales decisiones de diseño

<!-- TODO: resumir las decisiones y enlazar a la sección del informe donde cada una está justificada. -->

## Consultas incluidas

<!-- TODO: listar las consultas de db/consultas/ indicando qué pregunta responde cada una. -->

## Limitaciones y posibles mejoras

<!-- TODO: completar al cierre del trabajo. -->
