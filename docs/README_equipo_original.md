# Análisis espacial del Saber 11 — Bogotá

Pipeline reproducible **en R** sobre los microdatos del examen ICFES Saber 11 (2016–2024) para estudiar el rendimiento académico y la desigualdad educativa en Bogotá usando **econometría espacial** (Moran global/local, SAR, SEM, **Spatial Durbin Model**).

Inspiración metodológica: Delprato / Chudgar / Frola (2024) y Xiao Li (2024).

---

## Stack

Todo el proyecto se desarrolla **únicamente en R**. No se usa Python ni Stata.

Punto de entrada único: [notebooks/main_report.Rmd](notebooks/main_report.Rmd). Es a la vez el orquestador del pipeline y el reporte. No hay scripts modulares separados; toda la lógica vive en el `.Rmd`.

### Paquetes R utilizados

Cargados al inicio del `.Rmd` vía `pacman::p_load(...)` y `library(...)`:

- **Wrangling y E/S:** `tidyverse`, `data.table`, `janitor`, `arrow`, `readxl`, `haven`, `openxlsx`, `foreign`
- **Visualización:** `ggplot2`, `ggdist`, `GGally`, `RColorBrewer`, `scales`, `reshape2`
- **Espacial:** `sf`, `tmap`, `spdep` (matrices W y autocorrelación), `spatialreg` (SAR/SEM/SDM, planeado para Fases ≥ 3)
- **Estadística clásica:** `psych`, `vcd`, `cluster`, `fpc`
- **Modelos (varios, no todos en uso):** `rpart`, `rpart.plot`, `caret`, `glmnet`, `esquisse`

Sin `renv.lock` (en evaluación). Para reproducibilidad mínima, las versiones de R y paquetes quedan registradas en el `sessionInfo()` al final del knit.

---

## Estructura del repositorio

```
.
├── README.md
├── CLAUDE.md
├── .gitignore
│
├── notebooks/
│   └── main_report.Rmd         # pipeline + reporte único
│
├── data/                        # ignorada por git por tamaño/licenciamiento
│   ├── raw/                    # microdatos ICFES + capas espaciales originales
│   ├── cleaned/                # consolidados intermedios (parquet, gpkg saneado)
│   └── analysis/               # bases analíticas finales (csv, geojson, gpkg)
│
└── outputs/                     # productos del análisis (vacíos al inicio)
    ├── tables/
    ├── figures/
    ├── maps/
    └── models/
```

Las carpetas de `data/` y `outputs/` están en `.gitignore`. El repositorio versiona solo el código y la documentación.

---

## CRS canónico del proyecto: EPSG:3116

Todo el análisis espacial se realiza en **EPSG:3116 — MAGNA-SIRGAS / Colombia Bogotá zone** (proyectado, unidad metro, false E/N = 1,000,000).

Razones:

1. **Convención histórica del Distrito.** Es el CRS estándar de la Secretaría Distrital de Planeación (SDP), del Catastro de Bogotá y de la mayoría de capas históricas de la ciudad.
2. **Cero reproyección sobre `Zats.geojson`.** Tras corregir su etiqueta (declarada como EPSG:4686 pero en realidad ya en 3116), la capa queda lista sin transformación adicional.
3. **Distorsión despreciable a la escala de Bogotá** (< 1/2500), suficiente para distancias entre colegios y para construir matrices de pesos espaciales W.

Las capas `raw/colegios06_2025.gpkg`, `raw/ZATS2019.geojson` y `raw/geopanel1523date.geojson` se reproyectan a 3116 antes de cualquier operación espacial. La capa saneada vive en `data/cleaned/spatial_layers_3116.gpkg` (varias capas dentro del mismo GeoPackage).

---

## Datasets clave

### Datos crudos (`data/raw/`)

| Archivo | Tipo | Tamaño | Notas |
|---|---|---:|---|
| `Examen_Saber_11_YYYYS.txt` × 18 | microdatos ICFES | ~3.7 GB | períodos 2016-1 a 2024-2; encoding UTF-8, separador `;` |
| `colegios06_2025.gpkg` | GeoPackage de colegios (puntos) | 1.2 MB | 2221 colegios; CRS declarado EPSG:3857 pero coordenadas en lon/lat — ver §5.x del `.Rmd` |
| `ZATS2019.geojson` | polígonos de Zonas de Análisis Transporte | 9.5 MB | EPSG:4686, 1141 polígonos |
| `Zats.geojson` | puntos de colegios con puntaje promedio (panel) | 0.8 MB | etiqueta EPSG:4686 incorrecta; en realidad EPSG:3116 |
| `geopanel1523date.geojson` | colegios con panel anual | 7.2 MB | EPSG:4686, 6290 puntos |

### Datos procesados (`data/cleaned/`)

| Archivo | Tamaño | Filas | Generado por |
|---|---:|---:|---|
| `saber11_consolidado.parquet` | 232 MB | 5,982,829 | secciones 5–10 del `.Rmd` desde los 18 TXT crudos |
| `spatial_layers_3116.gpkg` | — | — | sección de saneamiento del `.Rmd` (Fase 1.3); 4 capas en EPSG:3116: `colegios`, `zats_puntos`, `zats_poligonos`, `geopanel_colegios` |

### Datos analíticos (`data/analysis/`)

| Archivo | Tamaño | Notas |
|---|---:|---|
| `estudiantes_bogota_geolocalizados.csv` | 374 MB | 719,466 estudiantes de Bogotá con lon/lat heredados del cruce a `colegios06_2025.gpkg` |
| `estudiantes_bogota_geolocalizados.geojson` | 526 MB | misma base, formato espacial |
| `mapa_homologacion_colegios.csv` | 240 KB | mapa de homologación ICFES↔gpkg con tres niveles de match |
| `diagnostico_columnas_saber11.csv` | 1.6 KB | columnas esperadas vs observadas |
| `control_calidad_saber11.csv` | 3.2 KB | reporte por variable del consolidado |

---

## Cómo ejecutar el pipeline

1. Instalar **R ≥ 4.5** y los paquetes listados arriba.
2. Colocar los 18 archivos `Examen_Saber_11_YYYYS.txt` en `data/raw/` y las 4 capas espaciales originales (`colegios06_2025.gpkg`, `ZATS2019.geojson`, `Zats.geojson`, `geopanel1523date.geojson`) en `data/raw/`.
3. Abrir [notebooks/main_report.Rmd](notebooks/main_report.Rmd) en RStudio.
4. En el chunk de configuración de directorio, ajustar `usuario <- "..."` o agregar el bloque `else if` con la ruta de tu equipo.
5. Hacer **Knit** (HTML).

Tiempo aproximado de knit completo desde TXT crudos: ~15–25 minutos según hardware. Si `data/cleaned/saber11_consolidado.parquet` ya existe y está completo, la consolidación se reutiliza en cache y el knit baja a ~3–5 minutos.

---

## Estado del proyecto

Pipeline de ETL espacial **funcional y completo** hasta la base geolocalizada de Bogotá. La capa de **modelación econométrica espacial** (Moran, SAR/SEM/SDM) se desarrolla por fases en el mismo `.Rmd`:

- ✅ Fase 1: saneamiento de archivos espaciales y limpieza del repositorio
- ⏳ Fase 2: agregación a unidades espaciales (colegio / ZAT / UPZ / UPL × transversal / pooled / panel)
- ⏳ Fase 3: matrices de pesos espaciales W (k-NN, banda de distancia, inverso, contigüidad)
- ⏳ Fase 4: autocorrelación espacial (Moran global y LISA)
- ⏳ Fase 5: SAR / SEM / SDM con descomposición de efectos directos / indirectos / totales


<!-- repo cleaned: 2026-04-27 -->
