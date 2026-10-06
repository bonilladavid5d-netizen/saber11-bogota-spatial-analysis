# export_geom_shiny.R
# Genera 4 GeoJSON WGS84 ligeros (solo geometry + id + nombre) para la Shiny app.
# Output: shiny/data/geom_<escala>.geojson

library(sf)
library(dplyr)

ROOT    <- "C:/Users/windows/Documents/Esteban 2025-1/Maestria/Taller de programacion en R/Proyecto"
ANA_DIR <- file.path(ROOT, "data", "analysis")
CLN_DIR <- file.path(ROOT, "data", "cleaned")
OUT_DIR <- file.path(ROOT, "shiny", "data")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

configs <- list(
  sede = list(
    src     = file.path(ANA_DIR, "base_sede_pooled_anio_3116.gpkg"),
    id_col  = "cole_cod_dane_sede",
    nom_col = "NOMBRE_SED",
    out     = file.path(OUT_DIR, "geom_sede.geojson")
  ),
  zat = list(
    src     = file.path(ANA_DIR, "base_zat_pooled_anio_3116.gpkg"),
    id_col  = "zat_id",
    nom_col = NA,
    out     = file.path(OUT_DIR, "geom_zat.geojson")
  ),
  upl = list(
    src     = file.path(CLN_DIR, "spatial_layers_3116.gpkg"),
    layer   = "upl_poligonos",
    id_col  = "CODIGO_UPL",
    nom_col = "NOMBRE",
    out     = file.path(OUT_DIR, "geom_upl.geojson")
  ),
  upz = list(
    src     = file.path(ANA_DIR, "base_upz_pooled_anio_3116.gpkg"),
    id_col  = "CODIGO_UPZ",
    nom_col = "NOMBRE",
    out     = file.path(OUT_DIR, "geom_upz.geojson")
  )
)

for (esc in names(configs)) {
  cfg <- configs[[esc]]
  if (!is.null(cfg$layer)) {
    sf_obj <- sf::st_read(cfg$src, layer = cfg$layer, quiet = TRUE)
  } else {
    sf_obj <- sf::st_read(cfg$src, quiet = TRUE)
  }

  # Normalizar ID a character
  sf_obj$unit_id <- as.character(sf_obj[[cfg$id_col]])

  # Nombre
  if (!is.na(cfg$nom_col) && cfg$nom_col %in% names(sf_obj)) {
    sf_obj$nombre <- as.character(sf_obj[[cfg$nom_col]])
  } else {
    sf_obj$nombre <- as.character(sf_obj[[cfg$id_col]])
  }

  # Conservar solo id + nombre + geometria
  sf_simple <- sf_obj |> dplyr::select(unit_id, nombre)

  # Transformar a WGS84
  sf_wgs84 <- sf::st_transform(sf_simple, crs = 4326)

  # Exportar
  sf::st_write(sf_wgs84, cfg$out, delete_dsn = TRUE, quiet = TRUE)

  sz <- file.size(cfg$out) / 1024
  cat(sprintf("[OK] %s: %d unidades -> %s (%.1f KB)\n",
              esc, nrow(sf_wgs84), basename(cfg$out), sz))
}

cat("\nGeometrias exportadas.\n")
