# Verificación de la app — cierre de v4.1.2

## Estado vigente — 6 de octubre de 2026

**Revisión visual cerrada por confirmación de David Bonilla.** Tras recibir el protocolo
siguiente, David respondió «todas pasan» en esta conversación. Los PASS de esta sección
registran esa confirmación; no son una ejecución del navegador por el revisor de este ZIP.
No se adjuntaron capturas de la última ronda.

| Comprobación solicitada | Resultado comunicado |
|---|---|
| Vista inicial a 1014 × 719: mapa de aproximadamente 500 px, calles, puntos, atribución, 1.224 sedes y sin botón de ampliación | PASS |
| Desplazamiento por filtros, mapa y tabla de conteos sin recortes | PASS |
| Fichas de LICEO FRANCES LOUIS PASTEUR y otra sede completas, incluido p | PASS |
| Dos ciclos HH + USAQUÉN (12 sedes, 7.003 presentaciones), HH + SUMAPAZ (0) y Todos/Todas (1.224), con recuperación del mapa | PASS |
| Cambio a 1440 × 1000 y regreso al tamaño pequeño sin recargar; mapa y filtros funcionales y modelos legibles | PASS |

El ZIP revisado contiene `fillable = FALSE`, mapa de `500px`, teselas de OpenStreetMap,
atribución y ausencia del botón de ampliación. La comprobación estática del paquete
coincide con los cambios declarados por la ejecución local. Esta revisión no crea commits,
no publica la app y no sustituye la revisión del índice de Git.

## Registro histórico de las rondas previas

Las secciones siguientes se conservan como historia de la corrección. Sus menciones a
comprobaciones pendientes describen el estado anterior a la confirmación de arriba.

Fecha: 5 de octubre de 2026. Entorno: macOS (Darwin 25.2.0 arm64), R 4.4.0.

## Comprobado en esta corrida

### Servidor

```
R -e 'shiny::runApp("shiny_corregido", port=7788, host="127.0.0.1", launch.browser=TRUE)'
curl -s -o root.html -w "%{http_code} %{size_download}" http://127.0.0.1:7788/
```

**HTTP 200, 23.387 bytes**, con 8 referencias a activos de leaflet y las cuatro pestañas
presentes en el HTML servido.

### Reactivos, filtros y consistencia

```
Rscript shiny_corregido/test_app.R     # código de salida 0
```

**24 comprobaciones, 0 fallos**, ejecutadas sobre el código de la v4.1. Cubren:

- Filtro base: 1.224 sedes.
- Conglomerado HH: 120 sedes, el mismo conteo de `02_lisa_sede_resumen.csv`.
- Excluir conflicto de establecimiento: quita exactamente 26 sedes.
- Umbral de presentaciones: filtra y todas las resultantes lo cumplen.
- Filtro por UPL: 33 sedes en el caso probado.
- **Selección vacía** (HH + SUMAPAZ): 0 sedes; resumen y tabla renderizan sin error.
- Evolución filtrada a primer semestre (9), segundo (9) y ambos (18).
- Renderizan sin error: resumen del mapa, tabla LISA, mapa leaflet, gráficos de evolución,
  de Moran y de impactos, tablas de modelos, robustez, diagnósticos y territorial, textos de
  limitaciones y procedencia.

## Correcciones aplicadas tras la revisión en Chrome (1014 × 719)

| Fallo observado | Causa | Corrección |
|---|---|---|
| Mapa base con mosaicos «API KEY REQUIRED» | `leaflet.providers` 3.0.0 enruta las teselas de CartoDB por un servicio que exige clave | Se usan las teselas estándar de OpenStreetMap vía `addTiles()` con URL explícita y su atribución, como exige su licencia |
| La leyenda tapaba la última línea del popup de LICEO FRANCES LOUIS PASTEUR | El popup se abría bajo la leyenda fija en la esquina inferior derecha | `popupOptions(autoPan = TRUE, keepInView = TRUE)` con margen reservado de 240 × 210 px en esa esquina: el mapa se desplaza para mostrar la ficha completa. La leyenda sigue visible en su sitio |
| En «Resultados del modelo» el gráfico se comprimía y las tablas se recortaban | `page_navbar` hacía rellenables todas las pestañas, forzando el contenido al alto de la ventana | `fillable = "Mapa de conglomerados"`: solo esa pestaña llena la ventana; las demás crecen con su contenido y la página se desplaza. Gráficos con alto explícito (460 px en impactos, 360 px en evolución), `card(fill = FALSE)` en 9 tarjetas y `overflow-x: auto` en las 5 tablas |

Datos, modelos, filtros y resultados no cambiaron. La escala de +10 p.p. se conserva.

### Comprobado automáticamente

```
Rscript shiny_corregido/test_app.R      # desde Proyecto - VP, código de salida 0
```

**26 comprobaciones, 0 fallos.** Dos son nuevas y verifican la primera corrección
inspeccionando el widget generado, no solo el código HTTP:

- `el mapa base usa teselas de OpenStreetMap, sin clave de API`
- `la atribucion de OpenStreetMap esta presente`

## Segunda ronda: presentación del mapa (v4.1.2)

Revisión real en Chrome: a 1440 × 1000 pasaban las cinco comprobaciones; a 1014 × 719 el
mapa inicial quedaba en una franja de unos 46 px, y tras ampliar, abrir fichas y cerrar la
ampliación las fichas salían cortadas y el mapa podía desaparecer al cambiar filtros.

| Fallo | Causa comprobada en el código | Corrección |
|---|---|---|
| Mapa de ~46 px a 1014 × 719 | `page_navbar()` trae `fillable = TRUE` por defecto y la pestaña del mapa estaba declarada rellenable. El contenedor repartía el alto de la ventana entre el banner, los filtros, el mapa y la tabla de conteos; con esa distribución el `height` del `leafletOutput` no se respetaba | `fillable = FALSE` en `page_navbar()` y en el `layout_sidebar()` del mapa; `card(fill = FALSE)` y `leafletOutput(height = "500px")`. La página se desplaza cuando el contenido no cabe |
| Fichas cortadas y mapa en blanco tras ampliar y cerrar | La tarjeta tenía `full_screen = TRUE`. Entrar y salir de pantalla completa redimensiona el contenedor, y Leaflet conserva el tamaño que cacheó al inicializarse salvo que se invoque `invalidateSize()`. Los contadores seguían correctos porque los datos nunca estuvieron en juego: el fallo era de tamaño de contenedor, no de filtrado | Se retiró el botón de ampliación. Con una vista fija de 500 px y página desplazable deja de hacer falta, y se elimina por completo la vía de redimensionado |

La segunda causa es la explicación documentada del comportamiento de Leaflet en contenedores
que cambian de tamaño; **no se reprodujo en un navegador desde este entorno**. Lo que sí está
comprobado es que el botón de ampliación ya no se emite y que el mapa sale con alto fijo.

### Evidencia en el HTML servido

```
$ curl -s http://127.0.0.1:7788/ | grep -c 'height:500px'    -> 1
$ curl -s http://127.0.0.1:7788/ | grep -c 'full-screen'     -> 0
```

Datos, modelos, filtros, resultados, atribución de OpenStreetMap y pestaña de modelos sin
cambios.

## Estado histórico: revisión visual pendiente antes de la confirmación

**Las tres correcciones no se verificaron en un navegador.** Este entorno no permite
interactuar con uno. `testServer` confirma que el mapa pide teselas de OpenStreetMap y que
todos los reactivos renderizan, pero no muestra cómo se ven la leyenda, el popup ni el
gráfico de impactos a un tamaño concreto.

La app quedó corriendo desde `Proyecto - VP/shiny_corregido`, servida en el puerto 7788
(HTTP 200 comprobado, `cwd` del proceso verificado). Hay que repetir las cinco
comprobaciones **a 1014 × 719**, el tamaño donde aparecieron los fallos, y confirmar
además que:

- el mapa se ve con una altura utilizable **desde la vista inicial**, sin ampliar nada;
- la página se desplaza verticalmente hasta la tabla de conteos;
- al cambiar filtros varias veces seguidas el mapa se mantiene y las fichas salen completas.

### Cómo comprobarlo

La app quedó corriendo. Abre:

```
http://127.0.0.1:7788
```

Si ya no responde, relánzala desde la raíz del proyecto:

```r
shiny::runApp("shiny_corregido", launch.browser = TRUE)
```

Cinco comprobaciones, en orden:

1. **Marcadores.** En «Mapa de conglomerados» deben aparecer puntos de colores sobre
   Bogotá: rojo oscuro para HH, azul para LL, naranja y celeste para los atípicos, gris
   claro para los no significativos.
2. **Popup.** Pulsa un punto rojo del norte. Debe abrirse con nombre de sede,
   establecimiento, UPL, número de presentaciones, z medio y el conglomerado con su p.
3. **Filtros combinados.** Elige «HH» en Conglomerado y una UPL del norte, por ejemplo
   USAQUÉN. El mapa debe quedarse solo con esos puntos y el contador del panel izquierdo
   debe bajar en consecuencia.
4. **Selección vacía.** Deja «HH» y cambia la UPL a SUMAPAZ. El mapa debe quedar sin
   puntos, sin error, y el contador en 0 sedes. Devuelve ambos filtros a «Todos» / «Todas»
   y los puntos deben reaparecer.
5. **Pestaña de modelos.** En «Resultados del modelo», las etiquetas del gráfico de
   impactos deben decir «(+10 p.p.)» en las proporciones, y «Estrato promedio del hogar»
   debe ir sin ese sufijo. La tabla de comparación debe mostrar el SDM con el AIC más bajo
   (9047,1).

Si algo falla, la captura y el mensaje de la consola de R bastan para diagnosticarlo.
