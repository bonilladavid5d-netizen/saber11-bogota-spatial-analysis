# Decisiones humanas

Registro de las decisiones metodológicas y de alcance que ha tomado David.
**Ningún script sobrescribe este archivo.** Las decisiones que siguen abiertas, derivadas
de los datos, se regeneran en `outputs/audit/fase1/DECISIONES_PENDIENTES.md`.

---

## 15 de septiembre de 2026 — Reconstrucción de la base

**CRS del catálogo de sedes.** Reinterpretar la etiqueta con `st_set_crs(4326)`, nunca con
`st_transform()`. Conservar evidencia del CRS declarado y las coordenadas originales. No
sobrescribir el GPKG.

**Población nacional elegible.** Todos los registros nacionales con `punt_global` válido
dentro de `[0, 500]`, sin restringir por `estu_estudiante` ni `estu_grado`. La composición
de esas variables se reporta aparte, pero no cambia el denominador principal.

**Ventana de coordenadas plausibles.** `lon ∈ [−74,50, −73,95]`, `lat ∈ [3,70, 4,85]`,
incluyendo la ruralidad de Sumapaz. Las coordenadas centinela o fuera de ventana se
conservan en la base auditada y quedan fuera de la muestra principal por su estado, no
eliminadas.

**Estados del cruce.** Orden de prioridad aprobado. Los candidatos por nombre pueden
identificar casos para revisión manual, pero no asignan coordenadas, no cambian
`match_method` ni entran a la muestra principal.

**Git.** No inicializar un repositorio en esta carpeta. Crear `.gitignore` y verificar sus
reglas por inspección. La integración con el repositorio original se hará después de
revisar la Fase 1.

**Comparación con la base original.** Solo agregada por `periodo × cole_cod_dane_sede`,
porque el CSV heredado no conserva `estu_consecutivo`. Vocabulario de cobertura y
presencia; sin afirmar cambios individuales.

**Insumos preliminares.** `audit/01_reconstruir_base_geocodificada.R` y
`audit/AUDITORIA_PRELIMINAR_GEOCODIFICACION.md` son referencias, no fuentes de verdad, y no
se sobrescriben. La versión definitiva vive en `R/`.

**`.gitignore`.** Sin regla global `*.parquet`; exclusiones específicas.

**Descarga de insumos.** Materializar únicamente `data/raw/` desde iCloud. No usar la copia
de `../Proyecto - VP/` como fuente de lectura, para conservar rutas relativas puras.

---

## 30 de septiembre de 2026 — Cierre del caso de portafolio

**Pregunta central.** Qué tan concentrado espacialmente está el rendimiento escolar en
Bogotá, y cuánto de la concentración reportada depende de cómo se vinculan los colegios con
su ubicación.

**Parche 1.1.** Corregir `pct()` para que opere sobre vectores y regenerar las tablas
afectadas.

**Alcance.** No reconstruir automáticamente los 16 modelos del estudio original. Distinguir
asociaciones de efectos causales.

---

## 1 de octubre de 2026 — Revisión independiente y ampliación

**Correcciones de la revisión.** Aplicar las cuatro correcciones del cierre acotado:
atribución y comparación con el original, conclusiones ajustadas a lo realmente calculado,
bloqueo de la entrega ante fallo de validación, y receta de reproducción completa con
comprobación real de Git.

**README principal.** El caso corregido pasa a ser `README.md`. El README original del
equipo se conserva en `docs/README_equipo_original.md`, con créditos y referencia visible al
trabajo original.

**Ampliación de alcance.** Incluir modelación econométrica y una aplicación Shiny funcional.
Seleccionar una especificación principal coherente con la pregunta, documentar qué se
conserva y qué se reconstruye, y evaluar cuáles de los demás modelos aportan información en
lugar de reconstruir los 16.

**Publicación.** No publicar, no hacer push, no inicializar otro repositorio.

---

## Decisiones que siguen abiertas

Se regeneran con los datos de cada corrida en
`outputs/audit/fase1/DECISIONES_PENDIENTES.md`. Al cierre de esta fase son tres: qué hacer
con los registros sin coincidencia exacta de sede, cómo tratar los desacuerdos de
establecimiento, y si la asignación territorial debe recalcularse por cruce espacial.
