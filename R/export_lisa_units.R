# export_lisa_units.R
# Genera 24 CSVs con clasificacion LISA por unidad (4 escalas x 6 areas).
# Usa las bases pooled de data/analysis/ y las W principales de outputs/models/.
# Output: outputs/tables/lisa_units/<escala>_<area>.csv

library(sf)
library(spdep)
library(readr)
library(dplyr)

# ---------- rutas -----------------------------------------------------------
ROOT    <- "C:/Users/windows/Documents/Esteban 2025-1/Maestria/Taller de programacion en R/Proyecto"
ANA_DIR <- file.path(ROOT, "data", "analysis")
MOD_DIR <- file.path(ROOT, "outputs", "models")
OUT_DIR <- file.path(ROOT, "outputs", "tables", "lisa_units")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ---------- configuracion ---------------------------------------------------
SCALES <- list(
  sede = list(
    gpkg    = "base_sede_pooled_anio_3116.gpkg",
    W_name  = "W_sede_knn5",
    id_col  = "cole_cod_dane_sede",
    name_col = "NOMBRE_SED",
    expected_n = 1132
  ),
  zat = list(
    gpkg    = "base_zat_pooled_anio_3116.gpkg",
    W_name  = "W_zat_knn5",
    id_col  = "zat_id",
    name_col = NA,
    expected_n = 495
  ),
  upl = list(
    gpkg    = "base_upl_pooled_anio_3116.gpkg",
    W_name  = "W_upl_queen",
    id_col  = "CODIGO_UPL",
    name_col = "NOMBRE",
    expected_n = 33
  ),
  upz = list(
    gpkg    = "base_upz_pooled_anio_3116.gpkg",
    W_name  = "W_upz_knn5",
    id_col  = "CODIGO_UPZ",
    name_col = "NOMBRE",
    expected_n = 102
  )
)

VARS <- list(
  punt_global        = "punt_global_z_periodo_media",
  matematicas        = "punt_matematicas_z_periodo_media",
  lectura_critica    = "punt_lectura_critica_z_periodo_media",
  ciencias_naturales = "punt_c_naturales_z_periodo_media",
  sociales_ciudadanas = "punt_sociales_ciudadanas_z_periodo_media",
  ingles             = "punt_ingles_z_periodo_media"
)

# ---------- funcion LISA ----------------------------------------------------
compute_lisa <- function(x, listw_obj, alpha = 0.05) {
  set.seed(42)
  loc <- spdep::localmoran(x, listw_obj, zero.policy = TRUE,
                           na.action = na.exclude)
  xs     <- x - mean(x, na.rm = TRUE)
  lag_x  <- spdep::lag.listw(listw_obj, x, zero.policy = TRUE)
  lag_xs <- lag_x - mean(lag_x, na.rm = TRUE)
  p      <- loc[, "Pr(z != E(Ii))"]

  cluster_type <- ifelse(
    is.na(p) | p > alpha, "NS",
    ifelse(xs > 0 & lag_xs > 0, "HH",
    ifelse(xs > 0 & lag_xs < 0, "HL",
    ifelse(xs < 0 & lag_xs > 0, "LH",
                                "LL")))
  )

  list(
    Ii           = loc[, "Ii"],
    p_valor      = p,
    cluster_type = factor(cluster_type, levels = c("HH", "LL", "HL", "LH", "NS"))
  )
}

# ---------- pipeline principal ----------------------------------------------
cat("\n=== EXPORTANDO CSVs LISA POR UNIDAD ===\n\n")
files_written <- character(0)

for (esc_name in names(SCALES)) {
  cfg <- SCALES[[esc_name]]

  cat(sprintf("Escala: %s\n", esc_name))

  # Cargar base
  gpkg_path <- file.path(ANA_DIR, cfg$gpkg)
  if (!file.exists(gpkg_path)) {
    stop(sprintf("FALTA: %s", gpkg_path))
  }
  base_sf <- sf::st_read(gpkg_path, quiet = TRUE)
  base_df <- sf::st_drop_geometry(base_sf)

  # Validar n
  if (nrow(base_df) != cfg$expected_n) {
    stop(sprintf("ERROR: %s tiene %d filas, esperaba %d",
                 esc_name, nrow(base_df), cfg$expected_n))
  }

  # Cargar W
  W_path <- file.path(MOD_DIR, paste0(cfg$W_name, ".rds"))
  if (!file.exists(W_path)) {
    stop(sprintf("FALTA W: %s", W_path))
  }
  W <- readRDS(W_path)

  # Validar alineacion W vs base
  n_W <- length(W$neighbours)
  if (n_W != nrow(base_df)) {
    stop(sprintf("DESALINEACION: W tiene %d nodos, base %s tiene %d filas",
                 n_W, esc_name, nrow(base_df)))
  }
  cat(sprintf("  W %s: %d nodos OK\n", cfg$W_name, n_W))

  # Iterar sobre areas tematicas
  for (area_short in names(VARS)) {
    var_col <- VARS[[area_short]]

    if (!var_col %in% names(base_df)) {
      cat(sprintf("  AVISO: columna '%s' no existe en %s, saltando\n",
                  var_col, esc_name))
      next
    }

    x <- base_df[[var_col]]
    n_missing <- sum(is.na(x))
    if (n_missing > 0) {
      cat(sprintf("  AVISO: %d NAs en %s-%s\n", n_missing, esc_name, area_short))
    }

    lisa_res <- compute_lisa(x, W)

    # Construir data.frame de salida
    out <- data.frame(
      unit_id      = as.character(base_df[[cfg$id_col]]),
      area         = area_short,
      valor_z      = round(x, 6),
      lisa_cluster = as.character(lisa_res$cluster_type),
      lisa_I_local = round(lisa_res$Ii, 6),
      lisa_p_valor = round(lisa_res$p_valor, 6),
      stringsAsFactors = FALSE
    )

    # Agregar nombre si existe
    if (!is.na(cfg$name_col) && cfg$name_col %in% names(base_df)) {
      out <- cbind(nombre = as.character(base_df[[cfg$name_col]]), out)
    } else {
      out <- cbind(nombre = out$unit_id, out)
    }

    out_path <- file.path(OUT_DIR, sprintf("%s_%s.csv", esc_name, area_short))
    readr::write_csv(out, out_path)
    files_written <- c(files_written, out_path)
    cat(sprintf("  [OK] %s_%s.csv  nrow=%d  NS=%d HH=%d LL=%d HL=%d LH=%d\n",
                esc_name, area_short, nrow(out),
                sum(out$lisa_cluster == "NS", na.rm = TRUE),
                sum(out$lisa_cluster == "HH", na.rm = TRUE),
                sum(out$lisa_cluster == "LL", na.rm = TRUE),
                sum(out$lisa_cluster == "HL", na.rm = TRUE),
                sum(out$lisa_cluster == "LH", na.rm = TRUE)))
  }
  cat("\n")
}

# ---------- resumen final ---------------------------------------------------
cat(sprintf("\n=== COMPLETADO: %d archivos escritos en %s ===\n",
            length(files_written), OUT_DIR))

# Preview primer CSV de cada escala
cat("\n--- HEAD(3) por escala (punt_global) ---\n")
for (esc_name in names(SCALES)) {
  f <- file.path(OUT_DIR, sprintf("%s_punt_global.csv", esc_name))
  if (file.exists(f)) {
    cat(sprintf("\n%s:\n", esc_name))
    df <- readr::read_csv(f, show_col_types = FALSE)
    print(head(df, 3))
  }
}
