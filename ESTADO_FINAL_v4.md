# Estado final — v4

Cierre: 5 de octubre de 2026. Aplica los cinco puntos de la revisión externa de
`ENTREGA_PORTAFOLIO_v3.zip` sobre la carpeta existente. Conserva el análisis, los cuatro
modelos y la app.

---

## 1. Los cinco puntos

| # | Punto | Cambio realizado | Evidencia | Estado |
|---|---|---|---|---|
| 1 | Exportación pública | Retirada la exportación `evolucion_periodo.csv`, que tenía celdas de 1 y 2 presentaciones; eliminados su carga y su requisito en `carga.R`; documentado el alcance exacto de la supresión | `R/06_exportar_shiny.R:81-88`, `shiny_corregido/data/` sin el archivo, `metadatos.json → alcance_supresion` | Cerrado |
| 2 | Interpretación de los modelos | I de Moran residual pasa a descriptivo con `p_valor = NA` y nota; retirada la frase sobre «los únicos sin autocorrelación»; comparación fundada en AIC; impactos de proporciones por 10 p.p.; retirado el mecanismo de «competencia»; LM simples y ajustadas distinguidas; caveat de inferencia pooled en nota, README y app; `rho_p` con precisión completa | Tabla 15, F6, `13_impactos_sdm.csv`, `12_pruebas_lm.csv`, `resumen_modelos.json` | Cerrado |
| 3 | Texto, figuras y evidencia | Regeneradas F1, F4 y F6 con sus textos corregidos y revisadas visualmente; rango del README corregido a 0,304–0,362 incluyendo k=10; retirada de la entrevista la afirmación sobre las validaciones originales; tabla 08 distingue 719.466 (CSV legacy) de 716.279 (1.132 sedes comunes); README abre con pregunta, resultado, utilidad y límites | PNG regenerados, `README.md`, `docs/EXPLICACION_ENTREVISTA.md`, `08_comparacion_con_original.csv` | Cerrado |
| 4 | Un fallo no reutiliza resultados | Impactos obligatorios: fallo ⇒ salida 1, productos renombrados a `.invalidado`, exportación bloqueada. `06` exige las ocho tablas antes de copiar ninguna. `02`, `03` y `05` marcan `EN_CURSO` al arrancar y `VALIDA` solo al terminar. `exigir_validacion()` comprueba que ambas huellas correspondan al parquet actual. Chequeo inicial de `data/raw` y de los cuatro componentes de cada shapefile | Tres pruebas dirigidas, abajo | Cerrado |
| 5 | Comprobación final y entrega | Cadena completa en código 0; 24 comprobaciones de la app; servidor verificado por HTTP; paquete v4 auditado | `outputs/portafolio/evidencia/app_verificacion.md` | Cerrado con un pendiente declarado |

---

## 2. Comandos y códigos de salida

| Comando | Código | Resultado |
|---|---:|---|
| `./run_analisis.sh` | **0** | Seis etapas sin fallos |
| `Rscript R/02_validar_fase1.R` | 0 | 15 PASS, 0 FAIL, 1 `N/A` |
| `Rscript R/03_validar_parquet.R` | 0 | 23 PASS, 0 FAIL |
| `Rscript shiny_corregido/test_app.R` | **0** | 24 comprobaciones, 0 fallos |
| `curl http://127.0.0.1:7788/` | HTTP 200 | 23.387 bytes, cuatro pestañas presentes |

### Pruebas dirigidas de bloqueo

| Prueba | Inyección | Resultado |
|---|---|---|
| A — fallo de impactos | Copia de `R/05` con `trMat` inválido | Salida **1**; `13_impactos_sdm.csv` y `f5_impactos_sdm.png` renombrados a `.invalidado`; estado `05_modelos = INVALIDA` |
| B — falta una tabla requerida | `18_robustez_sdm.csv` movida fuera del directorio | `R/06` salida **1**, nombra la tabla faltante; `metadatos.json` y el destino anterior **sin tocar** |
| C — validación que no terminó | `03_validar_parquet` forzado a `EN_CURSO` | `R/04` salida **1**, se niega a ejecutarse |

Tras cada prueba se restauró el estado y la cadena volvió a correr en código 0. No se
modificó ningún original.

**Defecto encontrado y corregido durante estas pruebas.** La primera versión de
`exigir_validacion()` exigía que *todas* las entradas del estado fueran `VALIDA`, de modo
que `05` quedaba en bloqueo mutuo consigo mismo tras marcarse `INVALIDA` y no podía
reintentarse. Ahora la función recibe la lista de scripts que debe exigir: por defecto los
dos validadores, y `06` añade `05` porque copia sus tablas.

---

## 3. Limitaciones reales

1. **La app no se verificó en un navegador.** El entorno no tiene navegador ni
   automatización disponible. `testServer` cubre la lógica de servidor y el HTML servido
   contiene los activos de leaflet, pero no se comprobaron visualmente los marcadores, un
   popup, el repintado al combinar filtros ni el aspecto de la pestaña de modelos. Declarado
   como pendiente en `outputs/portafolio/evidencia/app_verificacion.md`.
2. **La supresión no hace anónima la entrega.** Se suprime la media de 12 sedes con menos de
   10 presentaciones. Esas sedes conservan clasificación LISA, conteo y ubicación. Es una
   limitación de divulgación de un promedio, no una afirmación de que sin ella se
   identificaría a una persona.
3. **Inferencia bajo supuestos pooled.** No se corrigió por dependencia temporal entre
   observaciones de una misma sede; los efectos fijos de año no la resuelven.
4. **El I de Moran residual es descriptivo.** No se incorporó `lm.morantest()`; este cierre
   no amplía métodos.
5. **Asociaciones, no efectos causales.** Ninguna covariable tiene variación exógena.
6. **Geografía armonizada, no histórica.** Catálogo de 2025 sobre resultados desde 2016.
7. **20.754 presentaciones fuera de la muestra principal** y **14.114 en 26 sedes con
   conflicto de establecimiento**: documentadas, no resueltas.
8. **Las cifras de UPZ y UPL no son comparables con las del estudio original**, que usaba
   otra referencia de estandarización.
9. **La app original del equipo no arranca en este entorno**: requiere `DT`, `bsicons` y
   `outputs/tables/lisa_units/`, ausentes. No se instalaron paquetes.

---

## 4. Situación de Git

**No hay repositorio en esta carpeta y no se inicializó ninguno**, conforme a la decisión
vigente. `T15` queda en `N/A — sin repositorio`, con su alcance limitado a verificar las
reglas de `.gitignore` por inspección (5 de 5 presentes).

La prueba real existe en `R/02_validar_fase1.R`: cuando haya repositorio en la raíz,
inspecciona `git ls-files` y `git diff --cached` contra un patrón de rutas sensibles, porque
una regla en `.gitignore` no desversiona un archivo ya rastreado. **Hasta que esa
comprobación corra sobre el repositorio original, la entrega no está certificada para
publicación.** No se publicó, no se hizo push.

Se añadió `outputs/portafolio/modelos/` a `.gitignore`: los objetos ajustados contienen el
panel sede-año sin la supresión que sí se aplica a la exportación pública. No es una
prohibición genérica de archivos RDS; son regenerables con `Rscript R/05_modelos.R`.

---

## 5. Qué está listo y qué queda pendiente

**Listo.** La cadena de seis etapas corre con un comando y sale en 0. Los cuatro modelos y
sus diagnósticos están estimados sobre la base validada. El texto, las figuras y las tablas
dicen lo mismo y lo que dicen está respaldado. Un fallo en cualquier etapa invalida los
productos afectados, bloquea la exportación y retiene las afirmaciones. La app corre en
local, con 24 comprobaciones automáticas, sobre agregados y sin microdatos.

**Pendiente.** Dos cosas, ambas fuera de lo que puedo resolver aquí: la verificación visual
de la app en un navegador, y la ejecución real de `T15` sobre el repositorio original. Las
decisiones abiertas sobre exclusiones, conflictos de establecimiento y geografía de 2025
siguen documentadas como limitaciones, con las sensibilidades ya calculadas.

No se abre otra fase.
