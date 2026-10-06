# App de resultados corregidos

Consume únicamente agregados de la base reconstruida y validada en la Fase 1.
No contiene microdatos.

## Ejecutar con los agregados incluidos

Desde la raíz del proyecto, con las dependencias instaladas:

```bash
R -e 'shiny::runApp("shiny_corregido", launch.browser = TRUE)'
```

Los archivos de `shiny_corregido/data/` ya están incluidos. No es necesario reconstruir
la base privada ni ejecutar el exportador para explorar estos resultados. El mapa base
necesita conexión a internet para cargar las teselas de OpenStreetMap.

Para **regenerar** los agregados después de una nueva corrida del análisis:

```bash
Rscript R/06_exportar_shiny.R
```

El exportador exige que `R/02`, `R/03` y `R/05` tengan validación vigente sobre el mismo
parquet y que estén presentes las tablas requeridas; en caso contrario se detiene.

## Dependencias

`shiny`, `bslib`, `leaflet`, `sf`, `ggplot2`, `dplyr`, `tidyr`, `readr`, `jsonlite`.

No usa `DT` ni `bsicons` deliberadamente: no están instalados en el entorno comprobado y no
se instalaron paquetes para esta entrega. Las tablas se renderizan con `renderTable`.

## Prueba

```bash
Rscript shiny_corregido/test_app.R
```

Ejercita los reactivos con `shiny::testServer`: 26 comprobaciones de lógica del servidor,
consistencia de conteos con las tablas del análisis y configuración del mapa base. Esta
prueba no verifica la interacción del navegador. La revisión visual fue confirmada por
David el 6 de octubre de 2026; véase
[`app_verificacion.md`](../outputs/portafolio/evidencia/app_verificacion.md).

## Relación con la app original

La app del equipo se conserva sin modificar en `shiny/`. Esta versión reutiliza su
estructura de navegación, su tema y sus créditos. La original no arranca en este entorno
porque requiere `DT`, `bsicons` y `outputs/tables/lisa_units/`, que no están presentes.

## Privacidad

Las sedes con menos de 10 presentaciones en los nueve años no publican su media: con n = 1
la media es el puntaje de una persona. Son 12 de 1.224 y conservan su clasificación LISA.
