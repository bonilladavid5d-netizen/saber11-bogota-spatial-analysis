# Carga de los agregados exportados por R/06_exportar_shiny.R.
# Asume que el directorio de trabajo es shiny_corregido/.

LISA_COLORES <- c(HH = "#B2182B", LL = "#2166AC", HL = "#E08214",
                  LH = "#92C5DE", NS = "#CFCFCF")

LISA_ETIQUETAS <- c(
  HH = "Alto rodeado de altos",
  LL = "Bajo rodeado de bajos",
  HL = "Alto rodeado de bajos",
  LH = "Bajo rodeado de altos",
  NS = "Sin significancia")

PAL_CAT <- c("#2166AC", "#B35806", "#762A83", "#1B7837")

leer_tabla <- function(nombre) {
  p <- file.path("data", nombre)
  if (!file.exists(p)) {
    stop("Falta una tabla requerida de la app: ", p,
         "\nEjecute desde la raiz del proyecto: Rscript R/06_exportar_shiny.R")
  }
  readr::read_csv(p, show_col_types = FALSE, progress = FALSE)
}

cargar_datos <- function() {
  requeridos <- c("sedes.geojson", "upl.geojson", "evolucion_total.csv",
                  "metadatos.json", "01_moran_global_periodo.csv",
                  "02_lisa_sede_resumen.csv", "03_robustez_moran.csv",
                  "11_comparacion_modelos.csv", "13_impactos_sdm.csv",
                  "15_diagnosticos_modelos.csv", "18_robustez_sdm.csv",
                  "05_discrepancia_territorial.csv")
  faltan <- requeridos[!file.exists(file.path("data", requeridos))]
  if (length(faltan) > 0) {
    stop("Faltan datos de la app: ", paste(faltan, collapse = ", "),
         "\nEjecute desde la raiz del proyecto: Rscript R/06_exportar_shiny.R")
  }
  list(
    sedes        = sf::st_read(file.path("data", "sedes.geojson"), quiet = TRUE),
    upl          = sf::st_read(file.path("data", "upl.geojson"), quiet = TRUE),
    evol_total   = leer_tabla("evolucion_total.csv"),
    moran        = leer_tabla("01_moran_global_periodo.csv"),
    lisa_resumen = leer_tabla("02_lisa_sede_resumen.csv"),
    robustez_moran = leer_tabla("03_robustez_moran.csv"),
    modelos      = leer_tabla("11_comparacion_modelos.csv"),
    impactos     = leer_tabla("13_impactos_sdm.csv"),
    diagnosticos = leer_tabla("15_diagnosticos_modelos.csv"),
    robustez_sdm = leer_tabla("18_robustez_sdm.csv"),
    territorial  = leer_tabla("05_discrepancia_territorial.csv"),
    meta         = jsonlite::fromJSON(file.path("data", "metadatos.json"))
  )
}

ETIQUETAS_COV <- c(
  estrato_promedio      = "Estrato promedio del hogar",
  prop_oficial          = "Proporcion de colegio oficial",
  prop_internet_hogar   = "Proporcion con internet en casa",
  prop_jornada_completa = "Proporcion en jornada completa",
  prop_calendario_a     = "Proporcion en calendario A",
  prop_genero_femenino  = "Proporcion de mujeres",
  n_estudiantes_log     = "Tamano de la sede (log)")

tema_app <- function() {
  ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(colour = "grey90", linewidth = 0.3),
      plot.title = ggplot2::element_text(face = "bold", size = 13),
      plot.subtitle = ggplot2::element_text(colour = "grey40", size = 10),
      legend.position = "top", legend.title = ggplot2::element_blank())
}
