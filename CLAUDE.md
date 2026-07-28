# CLAUDE.md

## Project

Trabajo Práctico Integrador — **Bases de Datos para Inteligencia Artificial**, CEIA FIUBA, 2026.
Instructor: Martín Lacheski. Group work (Ariel, Alex, Andrés, Alan, Federico).

Chosen use case: **#3 — IoT monitoring with predictive analysis**, instantiated as a precision-agriculture platform.
Field devices communicate over LoRaWAN, emit measurements continuously, and the system must centralize them for
monitoring, irrigation management, and future AI workloads.

The assignment is a **data-solution design**, not an application build and not model training. Deliverables are the
technical report, the models (conceptual / logical / physical), an architecture proposal, and a minimal working
implementation with representative queries.

Source of truth for the assignment: `docs/Consignas TP Integrador BDIA_A23_2026.pdf`.

## Language rule

- **Spanish** — everything the team or the cátedra reads: informe, `README.md`, `TODO.md`, SQL comments,
  diagram labels, sample data.
- **English** — this file only, plus any future tooling notes that nobody but an agent reads.

Do not translate domain terms in deliverables. `lote`, `pivote`, `sector` and `medición` are the vocabulary the report
uses; keep identifiers and prose consistent with it.

## Domain glossary

Authoritative definitions live in `docs/DetallesParaModelado.ipynb` — consult it before modeling anything.

| Term | Meaning |
| --- | --- |
| Campo | Agricultural establishment. Contains lotes and pivotes. |
| Lote | Plot within a campo. Subdivided into sectores. |
| Sector | Subdivision of a lote (A, B, C…). |
| Pivote | Center-pivot irrigation machine. Belongs to one campo; irrigates one lote at a time. |
| AsignaciónPivote | Temporal history of which pivote irrigates which lote. |
| Categoría / Tipo de dispositivo | Device taxonomy (suelo, riego, meteorológico → sonda, ph, pluviómetro…). |
| Variable | Magnitude sensed by a device type, with its unit. |
| Dispositivo | Physical IoT device, with LoRaWAN credentials and operational state. |
| InstalaciónDispositivo | Temporal history of where a device is installed (campo, sector or pivote). |
| Gateway | LoRaWAN receiver that relays measurements. |
| Medición | Single reading: timestamp, JSONB values, RSSI, SNR, message counter. |
| ReglaAlarma / EventoAlarma | Threshold definition and the event raised when a measurement satisfies it. |
| Perfil / Usuario | Access profiles (Operador, Configurador, Administrador) and their users. |

The notebook also records **domain constraints** (e.g. a device cannot be powered on without an active installation,
a connected device must be powered on and installed, an alarm rule needs at least one threshold). These are
requirements for the physical model — every one of them should map to a constraint, trigger, or documented exception.

## Technology (provisional)

Current leaning: **PostgreSQL** as the primary store, **TimescaleDB** for the measurement time series, **JSONB** for
`valoresMedidos` so different device types can report different variable sets without schema changes.

This is *not* settled. Activity 6 requires justifying the choice against relational / NoSQL / vectorial alternatives
across ten criteria. Do not present it as a foregone conclusion in the report, and do not skip the comparison.

## Repository map

```
docs/       Report notebook, assignment PDF, exported diagrams (.png) and informe.pdf
data/       Sample data
  ejemplos/   Representative records used to validate the model
db/         Relational implementation
  estructura/     DDL — numbered scripts, executed in order
  datos/          Seed / sample data loads
  consultas/      Representative queries (minimum 5 required)
  indices_vistas/ Indexes, views, materialized views
nosql/      NoSQL model proposal, if the case justifies one
vectorial/  Vector model proposal, if the case justifies one
anexos/     Supplementary material
```

## Conventions

- **Identifiers**: `snake_case`, singular table names (`dispositivo`, not `dispositivos`).
- **SQL scripts**: numbered prefix (`01_`, `02_`) reflecting execution order; idempotent where practical
  (`CREATE TABLE IF NOT EXISTS`, `DROP … IF EXISTS`) so the schema can be rebuilt from scratch.
- **Constraint naming**: `pk_<table>`, `fk_<table>_<referenced>`, `ck_<table>_<rule>`, `ix_<table>_<columns>`,
  `uq_<table>_<columns>`.
- **Diagrams**: author as Mermaid `erDiagram` so the source is diffable and reviewable; export the PNG into `docs/`
  and commit both. The PNG is what the cátedra reads; the source is what we edit.
- **Temporal history tables** (`asignacion_pivote`, `instalacion_dispositivo`): `fecha_fin IS NULL` marks the active
  row. Only one active row per entity — enforce it.

### Commit messages

Prefix every commit with the `TODO.md` task ID it advances, then a short description in Spanish:

```
B-01: DDL inicial con hipertabla de mediciones
A-06: informe §4 — modelo conceptual
COORD-02: asignación de responsables A–E
```

Rules:

- One ID per commit. If a change spans two tasks, either split the commit or lead with the dominant ID and
  mention the other in the body.
- Valid prefixes are the ones defined in `TODO.md`: `A-`…`E-`, `ENT-`, `RM-`, `COORD-`, `Q-`.
- Housekeeping that maps to no task (typos, `.gitignore`, file moves) needs no prefix.
- When a commit completes a task, tick its checkbox in `TODO.md` in the same commit.

This matters beyond tidiness: the cátedra assesses each member's participation by reading the commit history,
so `git log --oneline` should read as a progress report with visible ownership.

## Grading rubric

Effort should track these weights:

| Criterion | Weight |
| --- | --- |
| Use-case understanding and data survey | 15% |
| Data-solution modeling | 20% |
| Minimal implementation and representative queries | 20% |
| Technology-selection justification | 15% |
| Data architecture, scalability, performance | 15% |
| Security, permissions, isolation | 10% |
| Clarity of report, README, repo organization | 5% |

## Hard constraints

- **Every relevant decision must be justified in writing.** Diagrams and scripts alone earn nothing — the assignment
  states this explicitly. When adding a model, a script, or a query, add the reasoning to the report in the same pass.
- **Every member must show commit evidence.** Work that happens outside the repo has to be documented in the README,
  stating who contributed what.
- The report must contain **15 numbered sections** and the README **11**; see `TODO.md` for the checklists.
