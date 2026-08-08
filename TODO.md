# TODO — TP Integrador BDIA

Referencias de estado: `[ ]` sin empezar · `[~]` en curso · `[x]` hecho

## Cómo referenciar las tareas

Cada ítem tiene un identificador estable para poder mencionarlo en mensajes, commits y revisiones
(«¿cómo viene **B-01**?», «**C-03** depende de que cierre **C-01**»).

| Prefijo | Qué identifica |
| --- | --- |
| `A-` … `E-` | Tareas de cada responsable |
| `ENT-` | Entregables exigidos por la consigna |
| `RM-` | Secciones del README |
| `COORD-` | Acuerdos pendientes del equipo |
| `Q-` | Puntos a definir / discrepancias detectadas |

Las secciones del informe se referencian con `§` y su número (`§14`). **Siempre es la numeración de las 15
secciones del informe, no la de las 12 actividades** — la consigna usa ambas y no coinciden (`Q-01`, `Q-02`).
Los identificadores no se reutilizan: si una tarea se elimina, su ID queda vacante.

Los commits también se prefijan con el ID de la tarea que avanzan (`B-01: DDL inicial con hipertabla de
mediciones`); la convención completa está en `CLAUDE.md`.

## Responsables

Integrantes del grupo: **Ariel · Alex · Andrés · Alan · Federico**.

| Rol | Integrante |
| --- | --- |
| A — Modelado | TBD |
| B — Implementación física | TBD |
| C — Optimización y escalabilidad | TBD |
| D — Seguridad y arquitectura | TBD |
| E — Informe, integración y calidad | TBD |

> Falta asignar quién toma cada rol (`COORD-02`). La cátedra exige evidencia de participación de cada integrante
> mediante commits; el trabajo hecho fuera del repositorio debe quedar atribuido en el README (`RM-02`).

## Orden de dependencias

```
A (modelos) ──► B (DDL + datos) ──┬──► C (índices, EXPLAIN, escalabilidad)
                                  └──► D (roles y permisos por tabla)
                                            todos ──► E (integración, PDF, README)
```

B es el camino crítico: C no puede correr `EXPLAIN` ni D asignar permisos por tabla hasta que existan el esquema
y los datos sintéticos. B no debería esperar a que los diagramas de A estén terminados — alcanza con un borrador
acordado.

---

## A — Modelado

- [ ] **A-01** · `docs/modelo_conceptual.png` — DER a partir de `docs/DetallesParaModelado.ipynb` (las entidades,
      cardinalidades y restricciones de dominio ya están escritas en prosa ahí; falta el diagrama)
- [ ] **A-02** · `docs/modelo_logico.png` — tablas, columnas, PK/FK, restricciones de integridad, resolución de N:M
- [ ] **A-03** · `docs/modelo_fisico.png` — modelo físico (o `.md` si resulta más claro)
- [ ] **A-04** · Documentar normalización y decisiones de diseño: polimorfismo en `instalacion_dispositivo`
      (campo / sector / pivote), JSONB para `valoresMedidos`, tablas de historial temporal
- [~] **A-05** · Informe §3 — Clasificación de los datos según su tipo *(borrador en `docs/Informe.ipynb` §2;
      pendiente de cerrar junto con `E-01`, ver `Q-05`)*
- [ ] **A-06** · Informe §4 — Modelo conceptual
- [ ] **A-07** · Informe §5 — Modelo de implementación según la tecnología elegida
- [ ] **A-08** · Informe §6 — Decisiones de normalización / embebido / referencia / desnormalización

## B — Implementación física

- [x] **B-01** · `db/estructura/01_create_tables.sql` — DDL completo, hipertabla TimescaleDB para `medicion`,
      índices GIN sobre JSONB *(verificado corriendo contra Postgres 16 + TimescaleDB)*
- [x] **B-02** · Script de generación de datos sintéticos → `db/datos/` y `data/ejemplos/` *(`generar_datos.py` +
      `main.py`, cubre las 15 tablas respetando restricciones — historial temporal, instalación polimórfica,
      JSONB variable por tipo de dispositivo — y exporta muestra a `data/ejemplos/mediciones.csv`)*
- [x] **B-03** · `docker-compose.yml` — para que todos puedan levantar la base y probar su consulta *(el DDL se
      ejecuta solo al primer `docker compose up -d`, vía `/docker-entrypoint-initdb.d`)*
- [ ] **B-04** · Informe §8 — Implementación mínima realizada
- [ ] **B-05** · Informe §9 — Datos de ejemplo utilizados

> Usa los diagramas de A (`A-01`…`A-03`) como referencia del esquema.

## C — Optimización y escalabilidad

- [ ] **C-01** · Juntar las 5+ consultas de todos, verificar que cubran lo exigido por la consigna (JOINs,
      agregaciones, `GROUP BY`, funciones de ventana, y una consulta que justifique el uso de un índice o vista)
      y completar las que falten → `db/consultas/`
- [ ] **C-02** · Índices, vistas y agregados continuos, cada uno respaldado con `EXPLAIN` → `db/indices_vistas/`
- [ ] **C-03** · Informe §10 — Consultas representativas (cada una necesita una explicación breve de qué pregunta
      responde y por qué es útil). Depende de `C-01`; no tenía responsable en la división original, ver `Q-03`
- [ ] **C-04** · Informe §14 — Consideraciones de escalabilidad y rendimiento (particionado, retención, precálculo,
      compromisos asumidos). **Es la sección 14, no la 12** — ver `Q-01`

> Usa el DDL y los datos de B (`B-01`, `B-02`) para correr los `EXPLAIN`, y las consultas de todos.

## D — Seguridad y arquitectura

- [ ] **D-01** · `db/estructura/02_roles_permisos.sql` — roles PostgreSQL para los tres perfiles (Operador,
      Configurador, Administrador), permisos y auditoría
- [ ] **D-02** · `docs/arquitectura.png` — arquitectura de datos de punta a punta: fuentes → ingesta →
      operacional → analítico → consumidores de IA
- [ ] **D-03** · Informe §11 — Datos semiestructurados, no estructurados y vectoriales, incluida la justificación
      de por qué **no** se usa una base vectorial
- [ ] **D-04** · Informe §12 — Propuesta de arquitectura de datos. **Es la sección 12, no la 10** — ver `Q-02`
- [ ] **D-05** · Informe §13 — Estrategia de seguridad, permisos y aislamiento (debe contemplar el riesgo de
      exposición indebida de datos en aplicaciones conectadas a modelos de IA)

> Usa el DDL de B (`B-01`) para asignar permisos por tabla.

## E — Informe, integración y calidad

- [~] **E-01** · Informe §1 — Descripción del caso de uso *(borrador en `docs/Informe.ipynb`; el caso de uso
      todavía no está definido al 100%)*
- [ ] **E-02** · Informe §2 — Relevamiento de datos necesarios — **falta §2.8 "Ejemplos de datos", que está vacía**
- [ ] **E-03** · Informe §7 — Justificación de la tecnología seleccionada: PostgreSQL + TimescaleDB frente a las
      alternativas, según los diez criterios que enumera la consigna
- [ ] **E-04** · Informe §15 — Conclusiones
- [ ] **E-05** · `README.md` — completar las 11 secciones exigidas (`RM-01`…`RM-11`) y documentar el aporte de
      cada integrante
- [ ] **E-06** · Exportar el informe integrado a `docs/informe.pdf`
- [ ] **E-07** · Verificar que todo corra desde cero: clonar → `docker compose up` → esquema → datos → consultas

> Usa el material de todos; al integrar y probar, termina revisando el trabajo completo.

---

## Entregables

| ID | Entregable | Tarea |
| --- | --- | --- |
| `ENT-01` | `docs/informe.pdf` — 15 secciones | `E-06` |
| `ENT-02` | `docs/modelo_conceptual.png` | `A-01` |
| `ENT-03` | `docs/modelo_logico.png` | `A-02` |
| `ENT-04` | `docs/modelo_fisico.png` (o `.md`) | `A-03` |
| `ENT-05` | `docs/arquitectura.png` | `D-02` |
| `ENT-06` | `db/estructura/` — DDL + roles | `B-01`, `D-01` |
| `ENT-07` | `db/datos/` — carga de datos de ejemplo | `B-02` |
| `ENT-08` | `db/consultas/` — 5 o más consultas con su explicación | `C-01` |
| `ENT-09` | `db/indices_vistas/` — índices, vistas y agregados continuos | `C-02` |
| `ENT-10` | `data/ejemplos/` — registros que validan entidades, relaciones y consultas | `B-02` |
| `ENT-11` | `README.md` — 11 secciones | `E-05` |
| `ENT-12` | Formulario de entrega con el enlace al repositorio (público, o con acceso de lectura para el usuario de la cátedra) | — |

## Secciones del informe — mapa de cobertura

| § | Sección | Responsable | Tarea | Estado |
| --- | --- | --- | --- | --- |
| 1 | Descripción del caso de uso | E | `E-01` | `[~]` borrador, sin cerrar |
| 2 | Relevamiento de datos necesarios | E | `E-02` | `[~]` falta §2.8 |
| 3 | Clasificación de los datos según su tipo | A | `A-05` | `[~]` borrador, sin cerrar |
| 4 | Modelo conceptual | A | `A-06` | `[~]` en prosa, sin diagrama |
| 5 | Modelo de implementación según la tecnología | A | `A-07` | `[ ]` |
| 6 | Decisiones de normalización / desnormalización | A | `A-08` | `[ ]` |
| 7 | Justificación de la tecnología seleccionada | E | `E-03` | `[ ]` |
| 8 | Implementación mínima realizada | B | `B-04` | `[ ]` |
| 9 | Datos de ejemplo utilizados | B | `B-05` | `[ ]` |
| 10 | Consultas representativas | C | `C-03` | `[ ]` |
| 11 | Datos semiestructurados / no estructurados / vectoriales | D | `D-03` | `[ ]` |
| 12 | Propuesta de arquitectura de datos | D | `D-04` | `[ ]` |
| 13 | Estrategia de seguridad, permisos y aislamiento | D | `D-05` | `[ ]` |
| 14 | Escalabilidad y rendimiento | C | `C-04` | `[ ]` |
| 15 | Conclusiones | E | `E-04` | `[ ]` |

Todas las secciones tienen responsable y ninguna está asignada dos veces.

## Secciones del README (11, todas obligatorias) — responsable E, tarea `E-05`

- [~] **RM-01** · Título del trabajo
- [ ] **RM-02** · Integrantes del grupo
- [~] **RM-03** · Caso de uso elegido
- [~] **RM-04** · Descripción breve de la solución
- [ ] **RM-05** · Datos principales identificados
- [ ] **RM-06** · Tecnología o tecnologías propuestas
- [~] **RM-07** · Estructura del repositorio
- [ ] **RM-08** · Instrucciones para ejecutar la implementación mínima
- [ ] **RM-09** · Principales decisiones de diseño
- [ ] **RM-10** · Consultas incluidas
- [ ] **RM-11** · Limitaciones y posibles mejoras

## Coordinación

- [ ] **COORD-01** · Avisar al equipo de la reestructuración `sql/` → `db/` (ya aplicada en esta rama)
- [ ] **COORD-02** · Mapear A–E a los nombres reales en la tabla de responsables
- [ ] **COORD-03** · Listar los cinco integrantes en el README (`RM-02`)
- [ ] **COORD-04** · Definir si `docs/Informe.ipynb` sigue siendo notebook o pasa a Markdown/LaTeX para exportar
      el PDF (`E-06`)

## Puntos a definir

- **Q-01** — *La "Sección 12" de C se renumeró a §14 (`C-04`).* La sección 12 del informe es *arquitectura de
  datos* (de D), mientras que escalabilidad / particionado / retención — lo que describe el paréntesis de C — es
  la sección 14. El número original corresponde a la *actividad* 12, no a la sección del informe.
- **Q-02** — *La "Sección 10" de D se renumeró a §12 (`D-04`).* La sección 10 es *consultas representativas*;
  como D hace el diagrama de arquitectura (`D-02`), la sección de arquitectura le corresponde. Las secciones 11
  y 13 ya estaban bien.
- **Q-03** — *La sección 10 no tenía responsable.* Alguien tiene que redactar las consultas en el informe, no
  solo dejar los archivos `.sql`. Quedó asignada a C como `C-03`, que ya las está consolidando en `C-01`.
- **Q-04** — *Nombres de los scripts SQL.* La división los llama `create_tables.sql` y `roles_permisos.sql`; acá
  quedaron con prefijo `01_` / `02_` para que el orden de ejecución sea explícito — los `GRANT` de `D-01`
  dependen de que existan las tablas de `B-01`. Es trivial revertirlo si el equipo prefiere los nombres sin prefijo.
- **Q-05** — *Solapamiento entre A y E en la §3.* El contenido de la clasificación de datos ya está escrito en
  `docs/Informe.ipynb` §2, que es territorio de E (`E-02`). A y E deberían acordar quién revisa `A-05` para no
  duplicar trabajo.
