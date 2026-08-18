# Auditoría de Incongruencias y Estado del Proyecto
**Trabajo Práctico Integrador — Bases de Datos para Inteligencia Artificial (CEIA FIUBA, 2026)**

Este documento consolida el análisis exhaustivo realizado sobre el notebook [`docs/Informe.ipynb`](docs/Informe.ipynb), contrastado contra el código DDL (`db/estructura/`), scripts de población (`02_populate_tables.sql`, `generar_datos.py`), archivos de configuración (`docker-compose.yml`), consultas representativas (`db/consultas/`) y el notebook de dominio (`docs/DetallesParaModelado.ipynb`).

---

## 1. Resumen de Secciones Faltantes o Incompletas en `Informe.ipynb`

| Sección en Informe | Estado | Observación |
| :--- | :--- | :--- |
| **§2.8 Ejemplos de datos** | ⚠️ Vacía | Solo existe el encabezado `## 2.8 Ejemplos de datos` sin contenido. |
| **§3. Clasificación de datos** | ⚠️ Omitida como H1 | El contenido de clasificación quedó absorbido dentro de la §2 en lugar de existir como la sección 3 independiente que pide la consigna. |
| **§6. Normalización / Desnormalización** | ❌ Faltante | No está redactada (tarea `A-08` en `TODO.md`). El informe salta directamente de la §5 a la §8. |
| **§7. Justificación tecnológica** | ❌ Faltante | No está redactada (tarea `E-03` en `TODO.md`). Falta la comparativa formal de los 10 criterios de la cátedra (Relacional + TimescaleDB vs NoSQL vs Vectorial). |
| **§15. Conclusiones** | ❌ Faltante | No está redactada (tarea `E-04` en `TODO.md`). |

---

## 2. Incongruencias entre el Informe y el Código

### 🔴 1. Número de tablas en §8.1 frente al resto del informe y al DDL
* **Ubicación:** `docs/Informe.ipynb` §8.1.
* **Texto actual:** *"El esquema físico se implementó en PostgreSQL 16 con la extensión TimescaleDB... El script define **15 tablas**, organizadas en cinco bloques..."*.
* **Incongruencia:**
  * En §4.1 y §5.1 se afirma explícitamente: *"el modelo conceptual tiene 16 entidades y el esquema físico **18 tablas**"*.
  * En §5.3 se listan las **18 tablas**.
  * En `db/estructura/01_create_tables.sql` se crean efectivamente **18 tablas**:
    1. `campo`
    2. `lote`
    3. `sector`
    4. `pivote`
    5. `asignacion_pivote`
    6. `categoria_dispositivo`
    7. `tipo_dispositivo`
    8. `variable`
    9. `tipo_variable` *(tabla asociativa N:M)*
    10. `dispositivo`
    11. `instalacion_dispositivo`
    12. `gateway`
    13. `medicion`
    14. `regla_alarma`
    15. `evento_alarma`
    16. `alarma_dispositivo` *(tabla asociativa N:M)*
    17. `perfil`
    18. `usuario`
* **Acción sugerida:** Corregir en §8.1 "15 tablas" por **"18 tablas"**, indicando que incluye las 2 tablas asociativas (`tipo_variable`, `alarma_dispositivo`) y la tabla de catálogo `variable`.

---

### 🔴 2. Volumen de datos de prueba y método de población en §9 frente a §10, §12, §13 y Docker
* **Ubicación:** `docs/Informe.ipynb` §9.1 y §9.2.
* **Texto actual:**
  * §9.1 afirma que los datos se generan con el script de Python (`db/datos/generar_datos.py` + `main.py`).
  * §9.2 lista en la tabla de volumen: *"Mediciones: 800"* (generadas en una ventana de 30 días).
* **Incongruencia:**
  * En la inicialización del contenedor Docker ([docker-compose.yml](docker-compose.yml)), el script que puebla automáticamente la base es `db/estructura/02_populate_tables.sql` (`popular_tablas()`), no Python.
  * El script SQL genera **50.000 mediciones** a lo largo de **1 año** (rango temporal: `2025-08-16` a `2026-08-16`).
  * Las secciones posteriores del informe (§10 Contexto de datos, §10.7 Validación de rendimiento / EXPLAIN, §12.3 Capa de ingesta, §13.6 Auditoría y §13.7 RLS) se basan y hacen referencia explícita a la corrida de **50.000 mediciones de 1 año**.
* **Acción sugerida:**
  * Actualizar §9.1 para explicar los dos mecanismos: la población SQL nativa en Docker (`02_populate_tables.sql`, 50.000 registros, 1 año) y el generador de Python (`main.py`) para casos específicos.
  * Actualizar la tabla de §9.2 reflejando las **50.000 mediciones** y el año de ventana temporal.

---

### 🟡 3. Estructura JSONB de la sonda de suelo (§2.2 y §11.1 vs DDL, SQL y Python)
* **Ubicación:** `docs/Informe.ipynb` §2.2 y §11.1.
* **Texto actual:**
  * *"Sondas de suelo: por cada nivel (6 niveles): humedad, temperatura, conductividad eléctrica → 18 valores"*.
* **Incongruencia:**
  * Tanto en `02_populate_tables.sql` (línea 203) como en `db/datos/generar_datos.py` (línea 226), el JSONB insertado es plano con 4 claves:
    ```json
    {
      "humedad_suelo": 35.2,
      "temperatura_suelo": 21.4,
      "conductividad_electrica": 1.2,
      "bateria": 88.0
    }
    ```
  * Las consultas SQL de la sección 10 (ej. §10.1 y §10.5) leen directamente `m.valores_medidos ->> 'humedad_suelo'`, asumiendo esta estructura plana.
* **Acción sugerida:** Aclarar en el informe que para la implementación mínima y representativa se modeló un nivel consolidado/superficial (`humedad_suelo`, `temperatura_suelo`, `conductividad_electrica`, `bateria`), extensible a múltiples niveles por JSONB sin cambios en el esquema.

---

### 🟡 4. Consulta representativa 06 de Auditoría ausente en §10
* **Ubicación:** `docs/Informe.ipynb` §10 vs `db/consultas/`.
* **Incongruencia:**
  * En la carpeta `db/consultas/` existen 6 archivos:
    1. `01_humedad_promedio_por_lote_7d.sql` *(en §10.1)*
    2. `02_pivotes_activos_por_lote.sql` *(en §10.2)*
    3. `03_dispositivos_bateria_baja.sql` *(en §10.3)*
    4. `04_eventos_alarma_por_regla.sql` *(en §10.4)*
    5. `05_analisis_temperatura_humedad_sector.sql` *(en §10.5)*
    6. `06_auditoria_cambios_configuracion.sql` *(aporte del módulo de seguridad/auditoría)*
  * La sección 10 del informe solo documenta las consultas 1 a 5.
* **Acción sugerida:** Incorporar como §10.6 la consulta de auditoría de configuración (muy valiosa porque justifica el índice sobre `auditoria.registro_cambios` y el uso de `LAG` / funciones de ventana).

---

### 🟡 5. Puerto publicado de pgAdmin (§13.2 / §13.10 vs `docker-compose.yml`)
* **Ubicación:** `docs/Informe.ipynb` §13.2 (Hallazgo 7) y §13.10.
* **Texto actual:** Se menciona pgAdmin publicado en el puerto `8080`.
* **Incongruencia:** En `docker-compose.yml`, el puerto de pgAdmin está mapeado a `5050` (`5050:80`) para evitar conflictos con Airflow u otros servicios locales que suelen ocupar el puerto 8080.
* **Acción sugerida:** Actualizar la mención del puerto a `5050` en las notas de seguridad de §13.

---

### 🟡 6. Atribución de `evento_alarma` (Punto Q-07 en TODO.md)
* **Ubicación:** `docs/Informe.ipynb` §4.4 vs §5.3 y `01_create_tables.sql`.
* **Incongruencia:**
  * El modelo conceptual (§4.4) declara la relación `medicion — evento_alarma` (1 : 0..N, indicando que una medición concreta dispara un evento).
  * El modelo lógico (§5.3) y el DDL solo referencian `id_regla` desde `evento_alarma`. No existe FK hacia `medicion` ni hacia `dispositivo`, por lo que un evento no permite saber directamente qué dispositivo o qué lectura exacta lo originó.
* **Acción sugerida:** Documentar en las limitaciones / decisiones del informe por qué no se enlazó `medicion` (al ser hipertabla particionada con PK compuesta, referenciarla requiere FK compuesta `(id_medicion, fecha_hora)`).

---

### 🟡 7. Cardinalidad `tipo_dispositivo` ↔ `variable` en `DetallesParaModelado.ipynb` vs `Informe.ipynb` (Punto Q-06 en TODO.md)
* **Ubicación:** `docs/DetallesParaModelado.ipynb` celda 12 frente a `Informe.ipynb` §4.4, §4.6, §5.4 y DDL.
* **Incongruencia:**
  * `DetallesParaModelado.ipynb` afirma: *"Una variable es sensada por un único tipo de dispositivo"* (1:N).
  * `Informe.ipynb` y el DDL (`tipo_variable`) implementan correctamente **N:M** (justificado porque la variable "Batería" es sensada por todos los tipos de dispositivo).
* **Acción sugerida:** Corregir esa línea en `DetallesParaModelado.ipynb` para que coincida con el informe y el DDL.

---

## 3. Checklist de Acciones Recomendadas para el Cierre

- [ ] **1.** Completar la subsección `§2.8 Ejemplos de datos` en `Informe.ipynb`.
- [ ] **2.** Redactar `§6. Normalización / Desnormalización` (Tarea `A-08`).
- [ ] **3.** Redactar `§7. Justificación de la tecnología seleccionada` comparando 10 criterios (Tarea `E-03`).
- [ ] **4.** Corregir en `§8.1` "15 tablas" por "18 tablas".
- [ ] **5.** Actualizar `§9.1` y `§9.2` con los datos de `02_populate_tables.sql` (50.000 registros, 1 año).
- [ ] **6.** Aclarar en `§2.2` y `§11.1` la estructura plana del JSONB de sondas de suelo.
- [ ] **7.** Opcional: Agregar `06_auditoria_cambios_configuracion.sql` a la sección 10 del informe.
- [ ] **8.** Ajustar la mención del puerto de pgAdmin a 5050 en `§13.2` y `§13.10`.
- [ ] **9.** Redactar `§15. Conclusiones` (Tarea `E-04`).
