#!/usr/bin/env Rscript

# Exporta los agregados que consume shiny_corregido/.
#
# Todo lo que sale de aqui esta agregado a nivel de sede o superior. Las sedes
# con menos de 10 examenes en los nueve anos no publican su media: con n = 1 la
# media es el puntaje de una persona.
#
# Ejecutar desde la raiz del proyecto:  Rscript R/06_exportar_shiny.R

suppressPackageStartupMessages({
  library(readr); library(dplyr); library(tidyr); library(stringr)
  library(arrow); library(sf); library(spdep); library(jsonlite)
})

source(file.path("R", "utils", "validation_helpers.R"))
# 06 copia productos de 05: exige ademas que esa etapa haya terminado bien.
HUELLA_VALIDADA <- exigir_validacion(
  c("02_validar_fase1", "03_validar_parquet", "05_modelos"))

TAB <- file.path("outputs", "portafolio", "tablas")
# Verificar las ocho tablas antes de escribir cualquier producto de la app.
TABLAS_APP <- c("01_moran_global_periodo.csv", "02_lisa_sede_resumen.csv",
                "03_robustez_moran.csv", "11_comparacion_modelos.csv",
                "13_impactos_sdm.csv", "15_diagnosticos_modelos.csv",
                "18_robustez_sdm.csv", "05_discrepancia_territorial.csv")
exigir_tablas(TAB, TABLAS_APP)

DEST <- file.path("shiny_corregido", "data")
dir.create(DEST, recursive = TRUE, showWarnings = FALSE)

N_MINIMO_DIVULGACION <- 10
CRS_ANALISIS <- 3116
K_VECINOS <- 5
set.seed(20261001)

log_etapa <- function(...) cat(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), ..., "\n", sep = "")

log_etapa("Reconstruyendo agregados de sede")

base <- read_parquet(file.path(RUTAS_FASE1$privado, "saber11_bogota_sede_auditada.parquet")) %>%
  filter(is_main_sample) %>%
  mutate(anio = as.integer(str_sub(periodo_fuente, 1, 4)))

sedes_conflicto <- base %>% filter(conflicto_est_status == "conflicto_establecimiento") %>%
  distinct(cole_cod_dane_sede_norm) %>% pull()

sede_pooled <- base %>%
  group_by(sede = cole_cod_dane_sede_norm) %>%
  summarise(z_media = mean(z_punt_global_nacional), n_examenes = n(),
            n_anios = n_distinct(anio),
            nombre_sede = first(nombre_sede_catalogo),
            nombre_est = first(nombre_est_catalogo),
            nombre_upl = first(nombre_upl_catalogo),
            nombre_upz = first(nombre_upz_catalogo),
            lon = first(lon), lat = first(lat), .groups = "drop") %>%
  mutate(conflicto_est = sede %in% sedes_conflicto)

# LISA con la misma convencion del analisis principal.
pts <- st_transform(st_as_sf(sede_pooled, coords = c("lon", "lat"), crs = 4326), CRS_ANALISIS)
lw <- nb2listw(knn2nb(knearneigh(st_coordinates(pts), k = K_VECINOS)), style = "W")
li <- localmoran(sede_pooled$z_media, lw)
pv <- li[, ncol(li)]
xc <- sede_pooled$z_media - mean(sede_pooled$z_media)
lagc <- lag.listw(lw, sede_pooled$z_media) - mean(lag.listw(lw, sede_pooled$z_media))

sede_pooled <- sede_pooled %>%
  mutate(
    lisa_p = round(pv, 5),
    cluster = ifelse(pv >= 0.05, "NS",
              ifelse(xc > 0 & lagc > 0, "HH",
              ifelse(xc < 0 & lagc < 0, "LL",
              ifelse(xc > 0 & lagc < 0, "HL", "LH")))),
    divulgable = n_examenes >= N_MINIMO_DIVULGACION,
    z_publicado = ifelse(divulgable, round(z_media, 3), NA_real_)
  )

n_suprimidas <- sum(!sede_pooled$divulgable)
log_etapa("  ", nrow(sede_pooled), " sedes | ", n_suprimidas,
          " con media suprimida por tener menos de ", N_MINIMO_DIVULGACION, " examenes")

st_write(
  st_as_sf(sede_pooled %>%
             select(sede, nombre_sede, nombre_est, nombre_upl, nombre_upz,
                    z_publicado, n_examenes, n_anios, cluster, lisa_p, conflicto_est,
                    lon, lat),
           coords = c("lon", "lat"), crs = 4326),
  file.path(DEST, "sedes.geojson"), delete_dsn = TRUE, quiet = TRUE)

# La evolucion por periodo y conglomerado no se exporta: con 18 periodos por 5
# conglomerados quedan celdas de 1 y 2 presentaciones, y con n = 1 la media es
# el z de una persona redondeado. La app nunca la consumio.
ruta_retirada <- file.path(DEST, "evolucion_periodo.csv")
if (file.exists(ruta_retirada)) {
  file.remove(ruta_retirada)
  log_etapa("  retirado export sobrante: evolucion_periodo.csv")
}

evolucion_total <- base %>%
  group_by(periodo = periodo_fuente) %>%
  summarise(z_medio = round(mean(z_punt_global_nacional), 4),
            punt_medio = round(mean(punt_global_num), 2),
            examenes = n(), sedes = n_distinct(cole_cod_dane_sede_norm), .groups = "drop") %>%
  mutate(etiqueta = paste0(str_sub(periodo, 1, 4), "-", str_sub(periodo, 5, 5)))
write_csv(evolucion_total, file.path(DEST, "evolucion_total.csv"))

# Poligonos UPL simplificados para el fondo del mapa.
upl <- st_read("data/raw/unidadplaneamientolocal/UnidadPlaneamientoLocal.shp", quiet = TRUE) %>%
  st_transform(4326) %>%
  transmute(nombre_upl = NOMBRE) %>%
  st_simplify(dTolerance = 0.0002, preserveTopology = TRUE)
st_write(upl, file.path(DEST, "upl.geojson"), delete_dsn = TRUE, quiet = TRUE)

# Tablas del analisis y de los modelos que la app muestra tal cual.
# Su presencia se comprobo antes de iniciar la exportacion.
for (f in TABLAS_APP) {
  stopifnot(file.copy(file.path(TAB, f), file.path(DEST, f), overwrite = TRUE))
}

meta <- list(
  generado = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  huella_parquet_validada = substr(HUELLA_VALIDADA, 1, 16),
  sedes = nrow(sede_pooled),
  examenes = sum(sede_pooled$n_examenes),
  sedes_media_suprimida = n_suprimidas,
  n_minimo_divulgacion = N_MINIMO_DIVULGACION,
  periodos = n_distinct(base$periodo_fuente),
  catalog_vintage = CATALOG_VINTAGE,
  alcance_supresion = paste(
    "Se suprime la media (z_publicado) de las sedes con menos de",
    N_MINIMO_DIVULGACION, "presentaciones en los nueve anos.",
    "Esas sedes conservan su clasificacion LISA, su conteo y su ubicacion:",
    "la supresion limita la divulgacion de un promedio, no convierte la",
    "entrega en anonima."),
  limitaciones = c(
    "Geografia armonizada al catalogo de sedes de 2025 aplicado a resultados de 2016 a 2024. No es geocodificacion historica.",
    "Lo que se muestra son asociaciones espaciales y condicionales, no efectos causales.",
    "LISA usa el p analitico de localmoran() sin ajuste por comparaciones multiples: el mapa es exploratorio.",
    "El z se calcula contra la poblacion nacional de cada periodo, antes de filtrar Bogota.",
    sprintf("Las sedes con menos de %d examenes no publican su media.", N_MINIMO_DIVULGACION),
    "La unidad es la presentacion del examen, no la persona."
  )
)
write_json(meta, file.path(DEST, "metadatos.json"), auto_unbox = TRUE, pretty = TRUE)

log_etapa("Exportacion lista en ", DEST)
