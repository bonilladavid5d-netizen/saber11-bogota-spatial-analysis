# Estado de validación — v4.1.2, cierre documental

## Estado vigente — 6 de octubre de 2026

**Interfaz cerrada por confirmación de David («todas pasan»)** después del protocolo de
revisión de la vista pequeña, el cambio de tamaño y los ciclos de filtros. La fuente y el
alcance están en `outputs/portafolio/evidencia/app_verificacion.md`.

El paquete contiene la versión corregida del mapa y el patrón de T15 con `[.]zip$` y
`[.]parquet$`. En este cierre solo se editaron cuatro documentos; los scripts, resultados,
figuras y agregados de Shiny permanecen idénticos al ZIP recibido.

**Siguiente acción: revisar y preparar el commit en `Proyecto - VP`.** El repositorio
local sigue siendo la fuente para comprobar el índice real. El PASS de T15 es el resultado
comunicado de esa ejecución local; no se ha vuelto a ejecutar R ni Git sobre el Mac desde
esta revisión. El ZIP no contiene un repositorio Git.

Los CSV y reportes de `outputs/audit/fase1/` conservan su corrida original, incluida la
marca `N/A — sin repositorio` de T15 en esa copia. No se cambian resultados de una prueba
por edición manual. El log `t15_repositorio_original.log` conserva sus dos ejecuciones
históricas; el registro final del índice se obtendrá localmente al preparar el commit.
`correcciones_visuales.log`, mencionado más abajo como archivo local, no vino en el ZIP;
no se ha fabricado un sustituto.

La lista de archivos y las instrucciones para integrar solo este cierre documental están
en `docs/CIERRE_ENTREGA.md`. Las secciones siguientes son el registro histórico y sus pendientes
visuales quedan superados por la confirmación de arriba. No se hizo commit ni push.

---

> **v4.1.2 (6 de octubre de 2026).** Corrige los dos fallos de presentación del mapa que
> quedaron tras la revisión en Chrome a 1014 × 719. Detalle en la sección 8.
>
> **v4.1.1 (6 de octubre de 2026).** Cierra los cuatro pendientes de la revisión del paquete
> integrado: el escape del patrón de T15 y los tres fallos visuales de la app. Detalle en la
> sección 7. El resto del documento describe la validación de la v4.1, que sigue vigente.


Fecha: 5 de octubre de 2026. Entorno: macOS (Darwin 25.2.0 arm64), R 4.4.0.

Esta versión **sí se ejecutó localmente**. Los resultados de abajo provienen de esta
corrida, no de la v4. Los logs reales están en `outputs/portafolio/evidencia/`.

---

## 1. Integración

Los 15 archivos del manifiesto se integraron en la carpeta original. **Ninguno presentaba
deriva**: los 12 modificados coincidían exactamente con su `sha256_v4` y los 3 nuevos no
existían localmente. No hubo nada que conciliar.

Tras copiar, los 15 archivos coinciden con su `sha256_v4_1`.

Los 12 archivos reemplazados se respaldaron **fuera de la carpeta pública**, en el
directorio temporal de la sesión (`scratchpad/respaldo_v4_pre_v4_1/`). No se reemplazó la
carpeta completa: microdatos, `data/`, `notebooks/main_report.Rmd`, `shiny/`, `audit/` y los
créditos quedaron intactos.

---

## 2. Comprobaciones ejecutadas

### Pruebas dirigidas

Log: `outputs/portafolio/evidencia/pruebas_dirigidas_v4_1.log`

| Prueba | Inyección | Resultado |
|---|---|---|
| Huella de `05_modelos` que no corresponde al parquet | `huella_parquet` de 05 forzada a 64 ceros | `R/06` **código 1**: «El parquet no coincide con el registrado por 05_modelos» |
| Falta una tabla requerida | `13_impactos_sdm.csv` retirada temporalmente | `R/06` **código 1**, nombra la tabla faltante |

**Prueba clave de la segunda:** se tomó la huella SHA-256 de los 12 archivos de
`shiny_corregido/data/` antes y después. Son **idénticas**. El bloqueo ocurre antes de
escribir cualquier export, que es exactamente el cambio de la v4.1 (mover `exigir_tablas()`
al inicio de `R/06`).

El estado de validación se restauró tras cada prueba.

### Ejecución

Log: `outputs/portafolio/evidencia/ejecucion_v4_1.log`

| Comando | Código | Resultado |
|---|---:|---|
| `bash run_analisis.sh` | **0** | Seis etapas sin fallos |
| `Rscript shiny_corregido/test_app.R` | **0** | **24 comprobaciones, 0 fallos** |

Conteos de la corrida: 791.073 presentaciones de Bogotá, 770.319 en la muestra principal,
ρ del SDM = 0,0609, impactos calculados para 7 covariables. `02`: 15 PASS, 0 FAIL, 1 `N/A`.
`03`: 23 PASS, 0 FAIL.

### F5 regenerada por R

Confirmado. La figura que ahora está en el repositorio la produjo `R/05_modelos.R` con
ggplot2 (SHA `71a0d51f…`, distinto del PNG de Matplotlib que traía el ZIP, `a2a1daaa…`).
Sus etiquetas llevan «(+10 p.p.)» y sus valores coinciden con las columnas
`*_presentado` de la tabla 13:

| Covariable | Directo | Indirecto | Total |
|---|---:|---:|---:|
| Estrato promedio (+1 unidad) | 0,340 | 0,029 | 0,369 |
| Internet en casa (+10 p.p.) | 0,156 | −0,056 | 0,100 |
| Jornada completa (+10 p.p.) | 0,053 | 0,015 | 0,067 |
| Colegio oficial (+10 p.p.) | 0,021 | 0,015 | 0,036 |

Concuerda con la tabla 13, el README y la app. El pie documenta las tres escalas y la
advertencia sobre significancia nominal bajo el modelo pooled.

No se ejecutó el auxiliar Python; no hacía falta.

---

## 3. Diferencias respecto de la v4

| Aspecto | v4 | v4.1 verificada aquí |
|---|---|---|
| Huella en `exigir_validacion()` | Solo se comprobaba la de `02` y `03` | Se comprueba la de **todas** las etapas requeridas, incluida `05` |
| Orden en `R/06` | `exigir_tablas()` después de escribir GeoJSON y CSV de evolución | `exigir_tablas()` **antes** de cualquier escritura |
| T15 | 5 reglas de `.gitignore`; patrón sin la carpeta de modelos | 6 reglas, incluida `outputs/portafolio/modelos/`; el patrón también la cubre |
| F5 | Valores sin reescalar | Columnas de presentación: +10 p.p. en proporciones |
| Pruebas de la app | 24 (v4) | 24, **reejecutadas sobre este código** |

Las cifras de estimación no cambiaron: los CSV de resultados son los mismos.

---

## 4. Git — T15 ejecutado en el repositorio original

**T15 pasa.** El caso se integró en `../Proyecto - VP` (rama `main`, HEAD `fbb8e14`, 35
commits) y se ejecutó el validador real desde su raíz.

```
$ Rscript R/02_validar_fase1.R        # desde Proyecto - VP
Pruebas: 16 PASS, 0 FAIL, 0 otros -> PASS
```

| | |
|---|---|
| T15 | **PASS** |
| Observado | repositorio presente; **0 archivos sensibles** versionados o preparados; reglas `.gitignore` **7/7** |
| Veredicto global | **PASS** (deja de ser `CONDITIONAL PASS`) |

Log: `outputs/portafolio/evidencia/t15_repositorio_original.log`.

### Fuga encontrada y cerrada

Al revisar qué entraría en la publicación apareció algo que T15 **no detectaba**: el
`.gitignore` del equipo excluye el directorio `data/raw/` pero no `data/raw.zip`. Esos
archivos comprimidos iban a publicarse:

| Archivo | Tamaño | Contenido |
|---|---:|---|
| `data/raw.zip` | 629 MB | los 18 TXT del ICFES |
| `data/cleaned.zip` | 206 MB | `saber11_consolidado.parquet`, 5,98 M de presentaciones |
| `data/analysis.zip` | 231 MB | bases geolocalizadas |

Es una condición preexistente del repositorio, no la introdujo la integración, pero el
validador debía atraparla. Se cerró en dos frentes:

1. `R/02_validar_fase1.R`: `data/*.zip` pasa a ser regla exigida (ahora 7) y
   `^data/.*\.zip$` entra en el patrón de rutas sensibles.
2. `.gitignore` de `Proyecto - VP`: se añadieron `data/*.zip`, `outputs.zip` y
   `FASE1_HANDOFF.zip`.

Tras el cierre, el conjunto de publicación son **101 entradas** y **ninguna** corresponde a
microdatos, parquet o comprimidos de datos.

### Lo que no se tocó

HEAD sigue en `fbb8e14`, 35 commits, sin stash. **No se hizo commit, ni push, ni se
reescribió historial, ni se inicializó otro repositorio.** Los cambios pendientes del equipo
se conservan tal cual, incluidas las eliminaciones: `D .claude/settings.local.json`,
`D CLAUDE.md`, `M notebooks/main_report.Rmd`.

## 5. Paquete

`ENTREGA_PORTAFOLIO_v4_1.zip` se auditó tras extraerlo: sin microdatos, sin `.parquet`, sin
`outputs/portafolio/modelos/`, sin `evolucion_periodo.csv`, sin restos `.invalidado` y sin
identificadores individuales. Incluye los logs de esta corrida.

---

## 6. Pendientes registrados antes del cierre visual

1. **Revisión visual de la app en el navegador.** No puedo interactuar con un navegador
   desde este entorno. Las instrucciones para comprobarla están en
   `outputs/portafolio/evidencia/app_verificacion.md`.
2. **El commit queda a tu criterio.** La integración está en el árbol de trabajo de
   `Proyecto - VP`, sin confirmar. Revisa el conjunto de 101 entradas antes de versionarlo.
3. Las limitaciones metodológicas de la v4 siguen vigentes sin cambios: asociaciones y no
   efectos causales, geografía armonizada de 2025, inferencia bajo supuestos pooled, I de
   Moran residual descriptivo, 20.754 presentaciones excluidas y 14.114 en 26 sedes con
   conflicto de establecimiento.

**La entrega no está certificada para publicación** mientras la revisión visual de la
app siga pendiente y el commit no se haya revisado.

---

## 7. Correcciones de la v4.1.1

### 7.1 Patrón de T15 — aplicado y comprobado

El patrón usaba escapes anidados: `"\\\\.zip$"` en una cadena de R produce la regex
`\\.zip$`, que busca una barra invertida literal y **no casaba con `data/raw.zip`**. T15
pasaba solo porque la regla de `.gitignore` ya excluía esos archivos del índice; la
detección por patrón estaba muerta.

Corregido a `^data/.*[.]zip$` y `[.]parquet$`. Comprobado en R sobre cadenas, sin añadir
ningún archivo sensible a Git:

| Ruta de ejemplo | Esperado | Resultado |
|---|---|---|
| `data/raw.zip` | detectar | detectado |
| `data/cleaned.zip` | detectar | detectado |
| `data/analysis.zip` | detectar | detectado |
| `otra_carpeta/base.parquet` | detectar | detectado |
| `outputs/portafolio/modelos/modelo.rds` | detectar | detectado |
| `outputs/portafolio/tablas/13_impactos_sdm.csv` | permitir | permitida |

Validador real reejecutado desde la raíz del repositorio: **16 PASS, 0 FAIL → PASS**, T15
con 7/7 reglas y 0 archivos sensibles. Log en
`outputs/portafolio/evidencia/t15_repositorio_original.log`.

### 7.2 Tres fallos visuales — aplicados, pendientes de verificación visual

| Fallo | Corrección |
|---|---|
| Mapa base «API KEY REQUIRED» | Teselas estándar de OpenStreetMap vía `addTiles()`, con atribución explícita |
| La leyenda tapaba la última línea del popup | `popupOptions(autoPan, keepInView)` con margen reservado en la esquina de la leyenda |
| Gráfico comprimido y tablas recortadas en «Resultados del modelo» | `fillable = "Mapa de conglomerados"` (solo el mapa llena la ventana), alturas explícitas, `card(fill = FALSE)` y `overflow-x: auto` en las tablas |

Datos, modelos, filtros y resultados sin cambios. No se reestimó nada.

`Rscript shiny_corregido/test_app.R` desde `Proyecto - VP`: **26 comprobaciones, 0 fallos**,
código de salida 0. Dos son nuevas y verifican el mapa base inspeccionando el widget
generado, no el código HTTP.

**La verificación visual sigue pendiente.** No tengo navegador en este entorno. La app está
servida desde `Proyecto - VP/shiny_corregido` en el puerto 7788. Las cinco comprobaciones, a
1014 × 719 y en una ventana más amplia, están en
`outputs/portafolio/evidencia/app_verificacion.md`.

### 7.3 Archivos modificados en esta corrección

```
R/02_validar_fase1.R              patrón de T15
shiny_corregido/app.R             teselas, popup y comportamiento de llenado
shiny_corregido/test_app.R        dos comprobaciones nuevas del mapa base
outputs/portafolio/evidencia/     app_verificacion.md y tres logs
ESTADO_VALIDACION_v4_1.md         esta sección
```

Aplicados en `Proyecto - VP` y sincronizados a la copia de trabajo. **Sin commit, sin push,
sin tocar los cambios pendientes del equipo.**

---

## 8. Correcciones de la v4.1.2 — presentación del mapa

Revisión real en Chrome: a 1440 × 1000 pasaban las cinco comprobaciones; a **1014 × 719** el
mapa inicial quedaba en una franja de unos 46 px, y tras ampliar, abrir fichas y cerrar la
ampliación las fichas salían cortadas y el mapa podía desaparecer al cambiar filtros. Los
contadores seguían siendo correctos. La pestaña de modelos ya funcionaba en ambos tamaños.

### 8.1 Causa comprobada

| Fallo | Causa | Evidencia |
|---|---|---|
| Mapa de ~46 px | `page_navbar()` trae `fillable = TRUE` por defecto y la pestaña del mapa estaba declarada rellenable; el contenedor repartía el alto de la ventana entre banner, filtros, mapa y tabla, de modo que el `height` del `leafletOutput` no se respetaba | `formals(bslib::page_navbar)$fillable` es `TRUE`; la app pasaba `fillable = "Mapa de conglomerados"` |
| Fichas cortadas y mapa en blanco tras ampliar y cerrar | La tarjeta tenía `full_screen = TRUE`; al entrar y salir se redimensiona el contenedor y Leaflet conserva el tamaño cacheado salvo que se invoque `invalidateSize()` | El fallo acompaña al redimensionado, no al filtrado: **los contadores eran correctos**, lo que descarta los datos como causa |

### 8.2 Corrección aplicada

- `fillable = FALSE` en `page_navbar()` y en el `layout_sidebar()` del mapa: ninguna pestaña
  llena la ventana y la página se desplaza cuando el contenido no cabe.
- Mapa con alto fijo utilizable: `card(fill = FALSE)` y `leafletOutput(height = "500px")`.
- **Se retiró el botón de ampliación.** Con una vista fija de 500 px y página desplazable no
  hace falta, y se elimina por completo la vía de redimensionado que provocaba el segundo
  fallo. Es la opción más simple de las tres posibles.

Datos, modelos, filtros, resultados, atribución de OpenStreetMap y pestaña de modelos sin
cambios. No se reestimó nada.

### 8.3 Comprobado

```
$ Rscript shiny_corregido/test_app.R        # desde Proyecto - VP
26 comprobaciones OK, 0 fallos              # codigo de salida 0

$ curl -s http://127.0.0.1:7788/ | grep -c 'height:500px'   -> 1
$ curl -s http://127.0.0.1:7788/ | grep -c 'full-screen'    -> 0
```

App reiniciada y sirviendo desde `Proyecto - VP/shiny_corregido` en el puerto 7788,
`cwd` del proceso verificado.

### 8.4 Archivos modificados

```
shiny_corregido/app.R                              fillable, alto del mapa, sin pantalla completa
outputs/portafolio/evidencia/app_verificacion.md   causa, correccion y que falta verificar
outputs/portafolio/evidencia/correcciones_visuales.log
ESTADO_VALIDACION_v4_1.md                          esta seccion
```

Aplicados en `Proyecto - VP` y sincronizados a la copia de trabajo. Sin commit ni push.

### 8.5 Pendiente registrado antes de la confirmación de David

**La revisión visual no está aprobada.** No tengo navegador en este entorno: la segunda
causa es la explicación documentada del comportamiento de Leaflet al redimensionarse, no una
reproducción observada. Falta confirmar a 1014 × 719 que el mapa se ve utilizable desde la
vista inicial sin ampliar, que la página se desplaza hasta la tabla de conteos, y que al
cambiar filtros repetidamente el mapa se mantiene y las fichas salen completas.
