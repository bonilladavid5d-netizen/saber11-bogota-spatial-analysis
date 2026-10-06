#!/usr/bin/env Rscript

# Fase 1: reconstruccion auditable de la base Saber 11 para colegios de Bogota.
#
# Regla principal: una observacion solo hereda coordenadas cuando su
# cole_cod_dane_sede coincide exactamente con DANE12_SED del catalogo 2025.
# Los nombres nunca asignan; a lo sumo proponen candidatos de revision manual.
#
# Ejecutar desde la raiz del proyecto:  Rscript R/01_reconstruir_base_geocodificada.R

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(purrr)
  library(tidyr)
  library(arrow)
  library(sf)
  library(digest)
  library(jsonlite)
})

source(file.path("R", "utils", "validation_helpers.R"))

t_inicio <- Sys.time()
options(stringsAsFactors = FALSE)

dir.create(RUTAS_FASE1$privado,   recursive = TRUE, showWarnings = FALSE)
dir.create(RUTAS_FASE1$auditoria, recursive = TRUE, showWarnings = FALSE)

COLS_OBLIGATORIAS <- c(
  "periodo", "estu_consecutivo", "punt_global",
  "cole_cod_mcpio_ubicacion", "cole_cod_dane_sede",
  "cole_cod_dane_establecimiento"
)

# Necesarias para auditar la regla de Bogota, la calidad del codigo y la
# composicion de la poblacion elegible.
COLS_DIAGNOSTICO <- c(
  "cole_cod_depto_ubicacion", "cole_depto_ubicacion", "cole_mcpio_ubicacion",
  "cole_nombre_sede", "cole_nombre_establecimiento", "cole_sede_principal",
  "cole_area_ubicacion", "estu_estudiante", "estu_grado", "estu_agregado"
)

# Covariables que main_report.Rmd 19.2 ya consume en las fases posteriores.
COLS_ANALISIS <- c(
  "punt_matematicas", "punt_lectura_critica", "punt_c_naturales",
  "punt_sociales_ciudadanas", "punt_ingles",
  "cole_naturaleza", "cole_jornada", "cole_calendario", "cole_caracter",
  "cole_genero", "cole_bilingue", "estu_genero",
  "estu_inse_individual", "estu_nse_individual", "estu_nse_establecimiento",
  "fami_estratovivienda", "fami_educacionmadre", "fami_educacionpadre",
  "fami_tieneinternet", "fami_tienecomputador"
)

COLS_DESEADAS <- c(COLS_OBLIGATORIAS, COLS_DIAGNOSTICO, COLS_ANALISIS)

# Solo para proponer candidatos de revision manual. Nunca asigna geografia.
normalizar_nombre <- function(x) {
  y <- toupper(trimws(as.character(x)))
  y <- iconv(y, to = "ASCII//TRANSLIT")
  y <- str_replace_all(y, "\\b(IED|IERD|CED|CED\\.|I\\.E\\.D|I\\.E\\.R\\.D)\\b", " ")
  y <- str_replace_all(y, "[^A-Z0-9 ]", " ")
  y <- str_squish(y)
  y[y == ""] <- NA_character_
  y
}

log_etapa <- function(...) cat(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), ..., "\n", sep = "")

# ---------------------------------------------------------------------------
# Etapa 0: manifiesto de insumos, materializacion y espacio
# ---------------------------------------------------------------------------

log_etapa("Etapa 0: manifiesto de insumos")

archivos_txt <- sort(list.files(
  RUTAS_FASE1$raw,
  pattern    = "^Examen_Saber_11_[0-9]{5}\\.txt$",
  recursive  = TRUE,
  full.names = TRUE
))

if (length(archivos_txt) != 18L) {
  stop("Se esperaban 18 TXT de Saber 11 y se encontraron ", length(archivos_txt),
       " bajo ", RUTAS_FASE1$raw, ". Revise duplicados o archivos ausentes.")
}

periodos_archivo <- str_extract(basename(archivos_txt), "[0-9]{5}")
if (anyDuplicated(periodos_archivo)) {
  stop("Hay periodos duplicados entre los archivos: ",
       paste(periodos_archivo[duplicated(periodos_archivo)], collapse = ", "))
}
if (!file.exists(RUTAS_FASE1$gpkg)) stop("No existe el catalogo: ", RUTAS_FASE1$gpkg)

insumos <- c(archivos_txt, RUTAS_FASE1$gpkg)
estado_previo <- vapply(insumos, estado_archivo_local, character(1))

# Leer un marcador de iCloud dispara una descarga completa; abortar es mas
# honesto que dejar el proceso colgado en E/S durante horas.
if (any(estado_previo == "dataless")) {
  stop(
    "Hay insumos sin materializar (marcadores de iCloud):\n  ",
    paste(basename(insumos[estado_previo == "dataless"]), collapse = "\n  "),
    "\nEjecute: brctl download \"", RUTAS_FASE1$raw, "\" y reintente."
  )
}

libre_gb <- espacio_libre_gb(".")
if (!is.na(libre_gb) && libre_gb < 2) {
  stop("Espacio libre insuficiente: ", round(libre_gb, 2), " GB. Se requieren al menos 2 GB.")
}
log_etapa("Espacio libre: ", round(libre_gb, 1), " GB")

# Decodificacion UTF-8 estricta sobre los extremos del archivo. La cobertura
# total se completa en la Etapa 1 buscando el caracter de reemplazo.
validar_utf8_muestra <- function(path, bytes = 20e6) {
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  cabeza <- readBin(con, "raw", n = bytes)
  tam <- file.size(path)
  cola <- raw()
  if (tam > 2 * bytes) {
    seek(con, where = tam - bytes, origin = "start")
    cola <- readBin(con, "raw", n = bytes)
  }
  ok <- function(r) {
    if (length(r) == 0) return(TRUE)
    tryCatch({
      txt <- rawToChar(r)
      Encoding(txt) <- "UTF-8"
      isTRUE(validUTF8(txt))
    }, error = function(e) NA)
  }
  isTRUE(ok(cabeza)) && isTRUE(ok(cola))
}

# El catalogo es un SQLite binario: delimitador, BOM y encoding no aplican y
# leerlo como texto rompe en el primer byte nulo.
describir_insumo <- function(path) {
  es_texto <- grepl("\\.txt$", path, ignore.case = TRUE)

  bom <- NA; crlf <- NA; delim <- NA_character_; n_cols <- NA_integer_
  conteos <- c(";" = NA_integer_, "," = NA_integer_, "|" = NA_integer_, "\t" = NA_integer_)

  if (es_texto) {
    con <- file(path, "rb")
    cabecera_raw <- readBin(con, "raw", n = 65536)
    close(con)
    bom <- length(cabecera_raw) >= 3 &&
      identical(as.integer(cabecera_raw[1:3]), c(239L, 187L, 191L))
    corte <- which(cabecera_raw == as.raw(10))[1]
    linea <- rawToChar(cabecera_raw[seq_len(ifelse(is.na(corte), length(cabecera_raw), corte - 1))])
    crlf <- grepl("\r$", linea)
    linea <- sub("\r$", "", linea)
    conteos <- c(";" = str_count(linea, ";"), "," = str_count(linea, ","),
                 "|" = str_count(linea, "\\|"), "\t" = str_count(linea, "\t"))
    delim <- names(conteos)[which.max(conteos)]
    n_cols <- length(strsplit(linea, ";", fixed = TRUE)[[1]])
  }

  data.frame(
    archivo          = basename(path),
    periodo          = str_extract(basename(path), "[0-9]{5}"),
    ruta_relativa    = path,
    tamano_bytes     = file.size(path),
    sha256           = sha256_archivo(path),
    filas            = NA_integer_,
    columnas         = n_cols,
    delimitador      = delim,
    delimitador_conteos = paste(sprintf("%s=%d", names(conteos), conteos), collapse = " "),
    encoding         = if (es_texto) "UTF-8" else "binario (GPKG/SQLite)",
    utf8_muestra_ok  = if (es_texto) validar_utf8_muestra(path) else NA,
    utf8_cobertura_total = NA,
    bom              = bom,
    fin_de_linea     = if (isTRUE(crlf)) "CRLF" else if (isFALSE(crlf)) "LF" else NA_character_,
    estado_archivo   = estado_archivo_local(path),
    leido_en         = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    stringsAsFactors = FALSE
  )
}

manifiesto <- map_dfr(insumos, describir_insumo)
sha_inicial <- setNames(manifiesto$sha256, manifiesto$ruta_relativa)
log_etapa("Manifiesto: ", nrow(manifiesto), " insumos con SHA-256")

# ---------------------------------------------------------------------------
# Etapa 1: pasada por periodo
# ---------------------------------------------------------------------------

log_etapa("Etapa 1: lectura por periodo")

schema_filas    <- list()
integridad      <- list()
dane_calidad    <- list()
momentos        <- list()
embudo_parcial  <- list()
bogota_partes   <- list()
utf8_cobertura  <- list()

for (i in seq_along(archivos_txt)) {
  path <- archivos_txt[i]
  per  <- periodos_archivo[i]
  log_etapa("  ", basename(path))

  encabezado <- names(read_delim(path, delim = ";", n_max = 0,
                                 locale = locale(encoding = "UTF-8"),
                                 col_types = cols(.default = col_character()),
                                 show_col_types = FALSE, progress = FALSE))

  faltan_oblig <- setdiff(COLS_OBLIGATORIAS, encabezado)
  if (length(faltan_oblig) > 0) {
    stop(basename(path), " no contiene columnas obligatorias: ",
         paste(faltan_oblig, collapse = ", "))
  }

  x <- read_delim(
    path,
    delim          = ";",
    locale         = locale(encoding = "UTF-8"),
    col_types      = cols(.default = col_character()),
    col_select     = any_of(COLS_DESEADAS),
    na             = character(),
    show_col_types = FALSE,
    progress       = FALSE
  )

  n_total <- nrow(x)
  manifiesto$filas[manifiesto$ruta_relativa == path] <- n_total

  # Normalizacion unica: recorte de espacios. Se registra como transformacion.
  x <- x %>% mutate(across(everything(), ~ trimws(.x)))

  hay_reemplazo <- any(vapply(x, function(col) any(grepl("�", col, fixed = TRUE)), logical(1)))
  utf8_cobertura[[per]] <- hay_reemplazo
  manifiesto$utf8_cobertura_total[manifiesto$ruta_relativa == path] <- !hay_reemplazo

  schema_filas[[per]] <- data.frame(
    periodo            = per,
    columna_original   = COLS_DESEADAS,
    columna_armonizada = COLS_DESEADAS,
    tipo_leido         = ifelse(COLS_DESEADAS %in% names(x), "character", NA_character_),
    n_faltantes        = vapply(COLS_DESEADAS, function(cl) {
                            if (!cl %in% names(x)) return(NA_integer_)
                            as.integer(sum(is.na(x[[cl]]) | x[[cl]] == ""))
                          }, integer(1)),
    disponible         = COLS_DESEADAS %in% names(x),
    transformacion     = ifelse(COLS_DESEADAS %in% names(x), "trimws", NA_character_),
    stringsAsFactors   = FALSE
  ) %>%
    mutate(pct_faltantes = pct(n_faltantes, n_total))

  consec <- normalizar_codigo(x$estu_consecutivo)
  periodo_interno <- normalizar_codigo(x$periodo)

  integridad[[per]] <- data.frame(
    periodo               = per,
    filas                 = n_total,
    consecutivos_faltantes = sum(is.na(consec)),
    llaves_duplicadas     = sum(duplicated(consec)),
    discrepancias_periodo = sum(is.na(periodo_interno) | periodo_interno != per),
    stringsAsFactors      = FALSE
  ) %>%
    mutate(estado = ifelse(consecutivos_faltantes == 0 & llaves_duplicadas == 0 &
                             discrepancias_periodo == 0, "PASS", "FAIL"))

  sede_orig <- x$cole_cod_dane_sede
  est_orig  <- x$cole_cod_dane_establecimiento
  sede_norm <- normalizar_codigo(sede_orig)
  est_norm  <- normalizar_codigo(est_orig)

  resumen_dane <- function(codigo, tipo) {
    valido <- es_dane_valido(codigo)
    no_num <- !is.na(codigo) & grepl("[^0-9]", codigo)
    anomalos <- unique(codigo[!is.na(codigo) & !valido])
    data.frame(
      periodo             = per,
      tipo_codigo         = tipo,
      total               = length(codigo),
      faltantes           = sum(is.na(codigo)),
      longitud_valida     = sum(valido),
      longitud_invalida   = sum(!is.na(codigo) & !valido),
      caracteres_no_numericos = sum(no_num),
      codigos_distintos   = length(unique(codigo[!is.na(codigo)])),
      ejemplos_anomalos   = paste(head(anomalos, 5), collapse = " | "),
      stringsAsFactors    = FALSE
    )
  }
  dane_calidad[[per]] <- bind_rows(resumen_dane(sede_norm, "sede"),
                                   resumen_dane(est_norm, "establecimiento"))

  # Momentos nacionales: se calculan sobre el archivo completo, antes de
  # cualquier filtro territorial.
  pg <- suppressWarnings(as.numeric(x$punt_global))
  pg_no_faltante <- !is.na(pg)
  pg_valido <- pg_no_faltante & pg >= PUNT_GLOBAL_MIN & pg <= PUNT_GLOBAL_MAX

  media_nac <- mean(pg[pg_valido])
  sd_nac    <- sd(pg[pg_valido])
  z <- rep(NA_real_, n_total)
  z[pg_valido] <- (pg[pg_valido] - media_nac) / sd_nac

  momentos[[per]] <- data.frame(
    periodo               = per,
    variable_puntaje      = "punt_global",
    obs_no_faltantes      = sum(pg_no_faltante),
    obs_validas           = sum(pg_valido),
    obs_fuera_de_rango    = sum(pg_no_faltante & !pg_valido),
    media_nacional        = media_nac,
    sd_nacional           = sd_nac,
    media_sin_rango       = mean(pg[pg_no_faltante]),
    sd_sin_rango          = sd(pg[pg_no_faltante]),
    media_z               = mean(z[pg_valido]),
    sd_z                  = sd(z[pg_valido]),
    poblacion_referencia  = "nacional_periodo_punt_global_valido",
    stringsAsFactors      = FALSE
  ) %>%
    mutate(estado = ifelse(abs(media_z) < 1e-8 & abs(sd_z - 1) < 1e-8, "PASS", "FAIL"))

  # Regla de Bogota y sus alternativas, medidas sobre la misma poblacion.
  mcpio <- normalizar_codigo(x$cole_cod_mcpio_ubicacion)
  bog_mcpio <- !is.na(mcpio) & mcpio == "11001"

  depto <- if ("cole_cod_depto_ubicacion" %in% names(x)) normalizar_codigo(x$cole_cod_depto_ubicacion) else rep(NA_character_, n_total)
  bog_depto <- !is.na(depto) & depto == "11"

  txt_mcpio <- if ("cole_mcpio_ubicacion" %in% names(x)) toupper(coalesce(x$cole_mcpio_ubicacion, "")) else rep("", n_total)
  bog_texto <- grepl("BOGOT", txt_mcpio, fixed = TRUE)

  embudo_parcial[[per]] <- data.frame(
    periodo                    = per,
    total_nacional             = n_total,
    punt_global_no_faltante    = sum(pg_no_faltante),
    punt_global_valido         = sum(pg_valido),
    bogota_regla_municipio     = sum(bog_mcpio),
    bogota_regla_departamento  = sum(bog_depto),
    bogota_regla_texto         = sum(bog_texto),
    discrepancia_mcpio_depto   = sum(bog_mcpio != bog_depto),
    discrepancia_mcpio_texto   = sum(bog_mcpio != bog_texto),
    bogota_punt_valido         = sum(bog_mcpio & pg_valido),
    stringsAsFactors           = FALSE
  )

  sel <- which(bog_mcpio)
  parte <- x[sel, , drop = FALSE]
  parte$archivo_fuente        <- basename(path)
  parte$periodo_fuente        <- per
  parte$periodo               <- periodo_interno[sel]
  parte$punt_global_orig      <- x$punt_global[sel]
  parte$punt_global_num       <- pg[sel]
  parte$punt_global_valido    <- pg_valido[sel]
  parte$z_punt_global_nacional <- z[sel]
  parte$cole_cod_dane_sede_orig <- sede_orig[sel]
  parte$cole_cod_dane_sede_norm <- sede_norm[sel]
  parte$cole_cod_dane_establecimiento_orig <- est_orig[sel]
  parte$cole_cod_dane_establecimiento_norm <- est_norm[sel]
  parte$media_nacional_periodo <- media_nac
  parte$sd_nacional_periodo    <- sd_nac

  bogota_partes[[per]] <- parte

  rm(x, parte, pg, z, sede_orig, est_orig, sede_norm, est_norm,
     mcpio, depto, txt_mcpio, bog_mcpio, bog_depto, bog_texto, consec, periodo_interno)
  gc(verbose = FALSE)
}

bogota <- bind_rows(bogota_partes)
rm(bogota_partes); gc(verbose = FALSE)
log_etapa("Bogota acumulado: ", format(nrow(bogota), big.mark = ","), " filas")

escribir_csv(manifiesto, "00_input_manifest.csv")
escribir_csv(bind_rows(schema_filas), "01_schema_periodos.csv")
escribir_csv(bind_rows(integridad), "02_integridad_llave_periodo.csv")
escribir_csv(bind_rows(momentos), "03_momentos_nacionales_periodo.csv")
escribir_csv(bind_rows(dane_calidad), "04_calidad_dane_periodo.csv")

# ---------------------------------------------------------------------------
# Etapa 2: catalogo de sedes 2025
# ---------------------------------------------------------------------------

log_etapa("Etapa 2: catalogo de sedes 2025")

colegios <- st_read(RUTAS_FASE1$gpkg, quiet = TRUE)
crs_declarado  <- st_crs(colegios)$input
epsg_declarado <- st_crs(colegios)$epsg
coords_cat <- st_coordinates(colegios)

# El GPKG declara EPSG:3857 pero almacena grados: los valores caen en el rango
# de lon/lat de Bogota, no en metros de Pseudo-Mercator. Se corrige la etiqueta
# con st_set_crs; transformar desde el CRS declarado desplazaria los puntos.
finitos <- is.finite(coords_cat[, 1]) & is.finite(coords_cat[, 2]) &
  abs(coords_cat[, 1]) < 1e300 & abs(coords_cat[, 2]) < 1e300
evidencia_crs <- sprintf(
  "lon [%.4f, %.4f] lat [%.4f, %.4f] sobre %d de %d filas con coordenada finita",
  min(coords_cat[finitos, 1]), max(coords_cat[finitos, 1]),
  min(coords_cat[finitos, 2]), max(coords_cat[finitos, 2]),
  sum(finitos), nrow(coords_cat)
)
colegios <- st_set_crs(colegios, 4326)

catalogo <- st_drop_geometry(colegios) %>%
  mutate(
    dane12_sed_norm = normalizar_codigo(DANE12_SED),
    dane12_est_norm = normalizar_codigo(DANE12_EST),
    lon = coords_cat[, 1],
    lat = coords_cat[, 2],
    coord_status = case_when(
      !finitos ~ "centinela_dbl_max",
      lon >= BBOX_BOGOTA$lon_min & lon <= BBOX_BOGOTA$lon_max &
        lat >= BBOX_BOGOTA$lat_min & lat <= BBOX_BOGOTA$lat_max ~ "plausible",
      TRUE ~ "fuera_de_bbox"
    )
  )

codigos_ambiguos <- catalogo %>% count(dane12_sed_norm) %>% filter(n > 1) %>% pull(dane12_sed_norm)

log_etapa("  filas: ", nrow(catalogo),
          " | sedes: ", n_distinct(catalogo$dane12_sed_norm),
          " | establecimientos: ", n_distinct(catalogo$dane12_est_norm),
          " | plausibles: ", sum(catalogo$coord_status == "plausible"),
          " | ambiguos: ", length(codigos_ambiguos))

crosswalk <- catalogo %>%
  transmute(
    codigo_sede             = dane12_sed_norm,
    codigo_establecimiento  = dane12_est_norm,
    nombre_establecimiento  = NOMBRE_EST,
    nombre_sede             = NOMBRE_SED,
    lon, lat,
    crs_origen_declarado    = crs_declarado,
    crs_aplicado            = "EPSG:4326 (st_set_crs, sin transformar)",
    evidencia_crs           = evidencia_crs,
    coord_status,
    fuente                  = basename(RUTAS_FASE1$gpkg),
    catalog_vintage         = CATALOG_VINTAGE
  )
escribir_csv(crosswalk, "07_crosswalk_sede_catalogo_2025.csv")

# ---------------------------------------------------------------------------
# Etapa 3: union sede contra sede
# ---------------------------------------------------------------------------

log_etapa("Etapa 3: union con el catalogo")

card_antes <- tabla_cardinalidad(bogota, c("periodo", "estu_consecutivo"), "antes_union")

catalogo_join <- catalogo %>%
  transmute(
    cole_cod_dane_sede_norm = dane12_sed_norm,
    dane12_sed_catalogo     = dane12_sed_norm,
    dane12_est_catalogo     = dane12_est_norm,
    nombre_est_catalogo     = NOMBRE_EST,
    nombre_sede_catalogo    = NOMBRE_SED,
    cod_upz_catalogo        = COD_UPZ,
    nombre_upz_catalogo     = NOMBRE_UPZ,
    cod_upl_catalogo        = COD_UPL,
    nombre_upl_catalogo     = NOM_UPL,
    zona_catalogo           = ZONA,
    estrato_catalogo        = ESTRATO,
    lon, lat,
    coord_status_catalogo   = coord_status
  )

base <- bogota %>%
  left_join(catalogo_join, by = "cole_cod_dane_sede_norm", relationship = "many-to-one")

card_despues <- tabla_cardinalidad(base, c("periodo", "estu_consecutivo"), "despues_union")

if (card_despues$filas != card_antes$filas) {
  stop("La union con el catalogo multiplico observaciones: ",
       card_antes$filas, " -> ", card_despues$filas,
       ". Revise la unicidad de DANE12_SED antes de continuar.")
}

cardinalidad <- bind_rows(card_antes, card_despues) %>%
  mutate(
    sin_coincidencia = c(NA_integer_, sum(is.na(base$dane12_sed_catalogo))),
    multiplicados    = c(NA_integer_, card_despues$filas - card_antes$filas)
  )

# ---------------------------------------------------------------------------
# Etapa 4: candidatos por nombre y estados del cruce
# ---------------------------------------------------------------------------

log_etapa("Etapa 4: estados del cruce")

dane_sede_valido <- es_dane_valido(base$cole_cod_dane_sede_norm)
en_catalogo      <- !is.na(base$dane12_sed_catalogo)

# Candidatos de revision manual: igualdad exacta de nombre normalizado entre la
# sede ICFES y la sede del catalogo, solo para codigos sin match. No asignan
# coordenadas ni cambian match_method.
sin_match_sedes <- base %>%
  filter(dane_sede_valido, !en_catalogo) %>%
  distinct(cole_cod_dane_sede_norm,
           cole_cod_dane_establecimiento_norm,
           cole_nombre_sede, cole_nombre_establecimiento) %>%
  mutate(nombre_sede_norm = normalizar_nombre(cole_nombre_sede))

catalogo_nombres <- catalogo %>%
  transmute(codigo_sede_candidato = dane12_sed_norm,
            nombre_sede_candidato = NOMBRE_SED,
            nombre_sede_norm      = normalizar_nombre(NOMBRE_SED)) %>%
  filter(!is.na(nombre_sede_norm))

candidatos <- sin_match_sedes %>%
  filter(!is.na(nombre_sede_norm)) %>%
  inner_join(catalogo_nombres, by = "nombre_sede_norm", relationship = "many-to-many")

codigos_con_candidato <- unique(candidatos$cole_cod_dane_sede_norm)
log_etapa("  sedes sin match: ", nrow(sin_match_sedes),
          " | con candidato por nombre: ", length(codigos_con_candidato))

coord_plausible <- !is.na(base$coord_status_catalogo) & base$coord_status_catalogo == "plausible"

base <- base %>%
  mutate(
    dane_sede_valido = dane_sede_valido,
    match_status = case_when(
      cole_cod_dane_sede_norm %in% codigos_ambiguos ~ "catalog_conflict",
      !dane_sede_valido                             ~ "missing_or_invalid_seat_code",
      en_catalogo &  coord_plausible                ~ "exact_match_valid_coordinates",
      en_catalogo & !coord_plausible                ~ "exact_match_invalid_coordinates",
      cole_cod_dane_sede_norm %in% codigos_con_candidato ~ "pending_manual_review",
      TRUE                                          ~ "valid_code_not_in_catalog"
    ),
    match_method = if_else(
      match_status %in% c("exact_match_valid_coordinates", "exact_match_invalid_coordinates"),
      "dane_sede_exacto", "ninguno"
    ),
    coord_status = coalesce(coord_status_catalogo, "sin_coordenada"),
    conflicto_est_status = case_when(
      !en_catalogo ~ "no_aplica",
      is.na(cole_cod_dane_establecimiento_norm) | is.na(dane12_est_catalogo) ~ "no_aplica",
      cole_cod_dane_establecimiento_norm != dane12_est_catalogo ~ "conflicto_establecimiento",
      TRUE ~ "sin_conflicto"
    ),
    catalog_vintage = CATALOG_VINTAGE,
    score_reference_population = "nacional_periodo_punt_global_valido",
    is_main_sample = match_status == "exact_match_valid_coordinates" & punt_global_valido,
    exclusion_reason = case_when(
      is_main_sample       ~ NA_character_,
      !punt_global_valido  ~ "punt_global_invalido",
      TRUE                 ~ match_status
    )
  )

match_periodo <- base %>%
  count(periodo_fuente, match_status, name = "n_registros") %>%
  group_by(periodo_fuente) %>%
  mutate(pct_periodo = pct(n_registros, sum(n_registros))) %>%
  ungroup() %>%
  mutate(pct_total_bogota = pct(n_registros, nrow(base))) %>%
  rename(periodo = periodo_fuente)
escribir_csv(match_periodo, "06_match_sede_periodo.csv")

# ---------------------------------------------------------------------------
# Etapa 5: conflictos establecimiento y casos sin match
# ---------------------------------------------------------------------------

log_etapa("Etapa 5: conflictos y casos sin match")

conflictos <- base %>%
  filter(conflicto_est_status == "conflicto_establecimiento") %>%
  count(periodo_fuente, cole_cod_dane_sede_norm,
        cole_cod_dane_establecimiento_norm, dane12_est_catalogo,
        cole_nombre_establecimiento, nombre_est_catalogo, nombre_sede_catalogo,
        name = "n_estudiantes") %>%
  rename(periodo = periodo_fuente,
         codigo_sede = cole_cod_dane_sede_norm,
         establecimiento_icfes = cole_cod_dane_establecimiento_norm,
         establecimiento_catalogo = dane12_est_catalogo) %>%
  mutate(tipo_conflicto = "establecimiento_icfes_difiere_de_catalogo_2025") %>%
  arrange(desc(n_estudiantes))
escribir_csv(conflictos, "08_conflictos_sede_establecimiento.csv")

n_candidatos_por_codigo <- candidatos %>%
  count(cole_cod_dane_sede_norm, name = "n_candidatos")

sin_match_agregado <- base %>%
  filter(match_status %in% c("valid_code_not_in_catalog", "pending_manual_review",
                             "missing_or_invalid_seat_code", "catalog_conflict")) %>%
  count(periodo_fuente, cole_cod_dane_sede_norm, cole_cod_dane_establecimiento_norm,
        cole_nombre_sede, cole_nombre_establecimiento, match_status,
        name = "n_estudiantes") %>%
  rename(periodo = periodo_fuente,
         codigo_sede = cole_cod_dane_sede_norm,
         codigo_establecimiento = cole_cod_dane_establecimiento_norm,
         motivo = match_status) %>%
  left_join(n_candidatos_por_codigo,
            by = c("codigo_sede" = "cole_cod_dane_sede_norm")) %>%
  mutate(
    n_candidatos = coalesce(n_candidatos, 0L),
    posible_fuente_revision = case_when(
      n_candidatos == 1 ~ "candidato unico por nombre normalizado de sede",
      n_candidatos > 1  ~ paste0(n_candidatos, " candidatos por nombre normalizado (ambiguo)"),
      TRUE              ~ "sin candidato; requiere fuente externa"
    ),
    estado_revision_manual = "PENDIENTE"
  ) %>%
  arrange(desc(n_estudiantes))
escribir_csv(sin_match_agregado, "09_sin_match_agregado.csv")

# ---------------------------------------------------------------------------
# Etapa 6: embudo por periodo
# ---------------------------------------------------------------------------

resumen_estados <- base %>%
  group_by(periodo = periodo_fuente) %>%
  summarise(
    bogota_total              = n(),
    dane_sede_valido          = sum(dane_sede_valido),
    match_exacto_catalogo     = sum(match_status %in% c("exact_match_valid_coordinates",
                                                        "exact_match_invalid_coordinates")),
    coordenada_valida         = sum(match_status == "exact_match_valid_coordinates"),
    muestra_principal         = sum(is_main_sample),
    excluidos                 = sum(!is_main_sample),
    motivos_exclusion         = paste(sprintf("%s=%d",
                                   names(table(exclusion_reason[!is_main_sample])),
                                   as.integer(table(exclusion_reason[!is_main_sample]))),
                                 collapse = "; "),
    .groups = "drop"
  )

embudo <- bind_rows(embudo_parcial) %>%
  left_join(resumen_estados, by = "periodo") %>%
  relocate(motivos_exclusion, .after = last_col())
escribir_csv(embudo, "05_embudo_bogota_periodo.csv")

# ---------------------------------------------------------------------------
# Etapa 7: comparacion agregada con la base legacy
# ---------------------------------------------------------------------------

log_etapa("Etapa 7: comparacion agregada con legacy")

legacy_nota <- NA_character_
legacy_resumen <- NULL

if (file.exists(RUTAS_FASE1$legacy_csv)) {
  legacy <- tryCatch(
    read_csv(RUTAS_FASE1$legacy_csv,
             col_select = any_of(c("periodo", "cole_cod_dane_sede")),
             col_types = cols(.default = col_character()),
             progress = FALSE),
    error = function(e) NULL
  )

  if (is.null(legacy) || !all(c("periodo", "cole_cod_dane_sede") %in% names(legacy))) {
    legacy_nota <- "El CSV legacy existe pero no expone periodo y cole_cod_dane_sede; no fue posible la comparacion agregada."
  } else {
    conteo_legacy <- legacy %>%
      transmute(periodo = normalizar_codigo(periodo),
                codigo_sede = normalizar_codigo(cole_cod_dane_sede)) %>%
      count(periodo, codigo_sede, name = "conteo_legacy")

    conteo_corregido <- base %>%
      count(periodo = periodo_fuente, codigo_sede = cole_cod_dane_sede_norm,
            name = "conteo_corregido")

    legacy_resumen <- full_join(conteo_legacy, conteo_corregido,
                                by = c("periodo", "codigo_sede")) %>%
      mutate(
        conteo_legacy    = coalesce(conteo_legacy, 0L),
        conteo_corregido = coalesce(conteo_corregido, 0L),
        diferencia_agregada = conteo_corregido - conteo_legacy,
        presencia_legacy    = conteo_legacy > 0,
        presencia_corregida = conteo_corregido > 0
      ) %>%
      group_by(periodo) %>%
      mutate(
        cobertura_legacy    = pct(conteo_legacy, sum(conteo_legacy)),
        cobertura_corregida = pct(conteo_corregido, sum(conteo_corregido))
      ) %>%
      ungroup() %>%
      mutate(limitacion_comparabilidad =
               "El CSV legacy no contiene estu_consecutivo: la comparacion es agregada por periodo x codigo de sede y no identifica registros individuales.") %>%
      arrange(periodo, desc(abs(diferencia_agregada)))

    escribir_csv(legacy_resumen, "10_legacy_vs_corregido_resumen.csv")
    legacy_nota <- sprintf("Comparacion agregada sobre %d combinaciones periodo x sede.",
                           nrow(legacy_resumen))
    rm(legacy, conteo_legacy, conteo_corregido); gc(verbose = FALSE)
  }
} else {
  legacy_nota <- "No existe el CSV legacy; no fue posible ninguna reconciliacion."
}
log_etapa("  ", legacy_nota)

# ---------------------------------------------------------------------------
# Etapa 8: escritura de la base privada y del diccionario
# ---------------------------------------------------------------------------

log_etapa("Etapa 8: escritura de resultados")

cols_auditoria <- c(
  "archivo_fuente", "periodo_fuente", "periodo", "estu_consecutivo",
  "cole_cod_mcpio_ubicacion",
  "punt_global_orig", "punt_global_num", "punt_global_valido",
  "z_punt_global_nacional", "media_nacional_periodo", "sd_nacional_periodo",
  "score_reference_population",
  "cole_cod_dane_sede_orig", "cole_cod_dane_sede_norm", "dane_sede_valido",
  "cole_cod_dane_establecimiento_orig", "cole_cod_dane_establecimiento_norm",
  "dane12_sed_catalogo", "dane12_est_catalogo",
  "nombre_est_catalogo", "nombre_sede_catalogo",
  "cod_upz_catalogo", "nombre_upz_catalogo",
  "cod_upl_catalogo", "nombre_upl_catalogo",
  "zona_catalogo", "estrato_catalogo",
  "lon", "lat", "coord_status",
  "match_method", "match_status", "conflicto_est_status",
  "catalog_vintage", "is_main_sample", "exclusion_reason"
)

cols_icfes <- setdiff(intersect(c(COLS_DIAGNOSTICO, COLS_ANALISIS), names(base)),
                      c("punt_global"))

base_final <- base %>% select(all_of(cols_auditoria), all_of(cols_icfes))

stopifnot(nrow(base_final) == nrow(bogota))

write_parquet(base_final, file.path(RUTAS_FASE1$privado, "saber11_bogota_sede_auditada.parquet"))
log_etapa("  base privada: ", format(nrow(base_final), big.mark = ","), " filas x ",
          ncol(base_final), " columnas")

if (nrow(candidatos) > 0) {
  write_parquet(
    candidatos %>%
      select(codigo_sede_icfes = cole_cod_dane_sede_norm,
             codigo_establecimiento_icfes = cole_cod_dane_establecimiento_norm,
             nombre_sede_icfes = cole_nombre_sede,
             nombre_establecimiento_icfes = cole_nombre_establecimiento,
             nombre_normalizado = nombre_sede_norm,
             codigo_sede_candidato, nombre_sede_candidato) %>%
      mutate(metodo_candidato = "igualdad exacta de nombre de sede normalizado",
             uso_permitido = "revision manual; no asigna geografia ni muestra principal"),
    file.path(RUTAS_FASE1$privado, "fase1_unmatched_review.parquet")
  )
}

definiciones <- c(
  archivo_fuente = "Nombre del TXT original del que proviene la fila",
  periodo_fuente = "Periodo derivado del nombre del archivo",
  periodo = "Periodo declarado en la columna periodo del TXT",
  estu_consecutivo = "Identificador de la presentacion del examen; no es una persona longitudinal",
  punt_global_orig = "punt_global tal como aparece en el TXT, sin convertir",
  punt_global_num = "punt_global convertido a numerico",
  punt_global_valido = "TRUE si punt_global es numerico y cae en [0,500]",
  z_punt_global_nacional = "(punt_global - media nacional del periodo) / sd nacional del periodo",
  media_nacional_periodo = "Media nacional de punt_global del periodo, calculada antes de filtrar Bogota",
  sd_nacional_periodo = "Desviacion estandar nacional del periodo, muestral (n-1)",
  score_reference_population = "Poblacion de referencia del z-score",
  cole_cod_dane_sede_orig = "Codigo DANE de sede tal como viene en el TXT",
  cole_cod_dane_sede_norm = "Codigo DANE de sede con espacios recortados; sin relleno de ceros",
  dane_sede_valido = "TRUE si el codigo de sede tiene exactamente 12 digitos",
  cole_cod_dane_establecimiento_orig = "Codigo DANE de establecimiento tal como viene en el TXT",
  cole_cod_dane_establecimiento_norm = "Codigo DANE de establecimiento con espacios recortados",
  dane12_sed_catalogo = "DANE12_SED de la sede vinculada en el catalogo 2025",
  dane12_est_catalogo = "DANE12_EST del establecimiento asociado a esa sede en el catalogo 2025",
  nombre_est_catalogo = "NOMBRE_EST del catalogo 2025",
  nombre_sede_catalogo = "NOMBRE_SED del catalogo 2025",
  cod_upz_catalogo = "COD_UPZ del catalogo 2025; atributo heredado, sin cruce espacial",
  nombre_upz_catalogo = "NOMBRE_UPZ del catalogo 2025",
  cod_upl_catalogo = "COD_UPL del catalogo 2025",
  nombre_upl_catalogo = "NOM_UPL del catalogo 2025",
  zona_catalogo = "ZONA urbana o rural segun el catalogo 2025",
  estrato_catalogo = "ESTRATO de la sede segun el catalogo 2025",
  lon = "Longitud de la sede en EPSG:4326",
  lat = "Latitud de la sede en EPSG:4326",
  coord_status = "plausible, centinela_dbl_max, fuera_de_bbox o sin_coordenada",
  match_method = "dane_sede_exacto o ninguno",
  match_status = "Estado del cruce, exhaustivo y mutuamente excluyente",
  conflicto_est_status = "Desacuerdo entre el establecimiento ICFES y el del catalogo 2025",
  catalog_vintage = "Fecha de referencia del catalogo de sedes",
  is_main_sample = "TRUE solo si hay match exacto, coordenada plausible y puntaje valido",
  exclusion_reason = "Motivo de exclusion de la muestra principal; prioridad: puntaje invalido, luego match_status"
)

usos <- c(
  punt_matematicas = "Fase 2: puntajes por area",
  punt_lectura_critica = "Fase 2: puntajes por area",
  punt_c_naturales = "Fase 2: puntajes por area",
  punt_sociales_ciudadanas = "Fase 2: puntajes por area",
  punt_ingles = "Fase 2: puntajes por area",
  cole_naturaleza = "Fase 2: covariable es_oficial (main_report.Rmd 19.2)",
  cole_jornada = "Fase 2: covariable es_jornada_compl (main_report.Rmd 19.2)",
  cole_calendario = "Fase 2: control de calendario A/B",
  cole_bilingue = "Fase 2: sensibilidad sin bilingues",
  fami_estratovivienda = "Fase 2: covariable estrato_familia (main_report.Rmd 19.2)",
  fami_educacionmadre = "Fase 2: sensibilidad madre vs estrato",
  estu_inse_individual = "Fase 2: indice socioeconomico individual",
  fami_tieneinternet = "Fase 2: covariable de lista B",
  estu_estudiante = "Diagnostico de composicion de la poblacion elegible",
  estu_grado = "Diagnostico de composicion de la poblacion elegible",
  estu_agregado = "Diagnostico de composicion de la poblacion elegible"
)

diccionario <- data.frame(
  variable = names(base_final),
  tipo     = vapply(base_final, function(v) class(v)[1], character(1)),
  stringsAsFactors = FALSE
) %>%
  mutate(
    fuente = case_when(
      variable %in% c("archivo_fuente", "periodo_fuente") ~ "derivada del nombre del archivo",
      grepl("_catalogo$", variable) | variable %in% c("lon", "lat", "catalog_vintage") ~ "colegios06_2025.gpkg",
      variable %in% c("z_punt_global_nacional", "media_nacional_periodo", "sd_nacional_periodo",
                      "punt_global_num", "punt_global_valido", "dane_sede_valido",
                      "match_method", "match_status", "coord_status", "conflicto_est_status",
                      "is_main_sample", "exclusion_reason", "score_reference_population") ~ "derivada en esta fase",
      TRUE ~ "TXT Saber 11"
    ),
    definicion = coalesce(unname(definiciones[variable]),
                          "Variable original del TXT Saber 11, conservada sin transformar"),
    transformacion = case_when(
      grepl("_norm$", variable) ~ "trimws; vacio a NA",
      variable == "punt_global_num" ~ "as.numeric",
      variable == "z_punt_global_nacional" ~ "estandarizacion nacional por periodo",
      TRUE ~ "trimws"
    ),
    unidad = case_when(
      variable %in% c("lon", "lat") ~ "grados decimales",
      grepl("^punt_", variable) ~ "puntos Saber 11",
      variable == "z_punt_global_nacional" ~ "desviaciones estandar",
      TRUE ~ "categorica o identificador"
    ),
    valores_permitidos = case_when(
      variable == "match_status" ~ "exact_match_valid_coordinates | exact_match_invalid_coordinates | valid_code_not_in_catalog | missing_or_invalid_seat_code | catalog_conflict | pending_manual_review",
      variable == "match_method" ~ "dane_sede_exacto | ninguno",
      variable == "coord_status" ~ "plausible | centinela_dbl_max | fuera_de_bbox | sin_coordenada",
      variable == "conflicto_est_status" ~ "sin_conflicto | conflicto_establecimiento | no_aplica",
      variable == "punt_global_num" ~ "[0,500] para registros validos",
      TRUE ~ ""
    ),
    uso_posterior = coalesce(unname(usos[variable]), "Auditoria y trazabilidad de la Fase 1"),
    clasificacion = if_else(
      variable %in% c("estu_consecutivo") | grepl("^estu_|^fami_", variable),
      "privada", "privada"
    )
  )
escribir_csv(diccionario, "11_diccionario_base.csv")

# ---------------------------------------------------------------------------
# Etapa 9: controles esperados contra observados
# ---------------------------------------------------------------------------

momentos_df   <- bind_rows(momentos)
integridad_df <- bind_rows(integridad)

observados <- c(
  archivos_periodos          = length(archivos_txt),
  registros_nacionales       = sum(momentos_df$obs_no_faltantes),
  registros_bogota           = sum(embudo$bogota_punt_valido),
  match_exacto_sede          = sum(base$match_status %in%
                                     c("exact_match_valid_coordinates",
                                       "exact_match_invalid_coordinates") &
                                     base$punt_global_valido),
  filas_gpkg                 = nrow(catalogo),
  establecimientos_gpkg      = n_distinct(catalogo$dane12_est_norm),
  establecimientos_multisede = sum(table(catalogo$dane12_est_norm) > 1),
  coordenadas_plausibles     = sum(catalogo$coord_status == "plausible"),
  coordenadas_anomalas       = sum(catalogo$coord_status != "plausible"),
  llaves_faltantes           = sum(integridad_df$consecutivos_faltantes),
  llaves_duplicadas          = sum(integridad_df$llaves_duplicadas),
  discrepancias_periodo      = sum(integridad_df$discrepancias_periodo)
)

expected_vs_observed <- CONTROLES_ESPERADOS %>%
  mutate(
    observado  = unname(observados[control]),
    diferencia = observado - esperado,
    estado     = if_else(diferencia == 0, "PASS", "REVIEW"),
    explicacion = case_when(
      diferencia == 0 ~ "Coincide con el control diagnostico.",
      control == "registros_nacionales" ~ "El control cuenta filas nacionales con punt_global no faltante. La poblacion elegible de esta fase exige ademas rango [0,500]; ambos denominadores estan en 03_momentos_nacionales_periodo.csv.",
      control == "registros_bogota" ~ "Regla estricta cole_cod_mcpio_ubicacion == 11001 sobre registros con puntaje valido. Las reglas alternativas por departamento y por texto estan en 05_embudo_bogota_periodo.csv.",
      control == "match_exacto_sede" ~ "Coincidencias exactas sede a sede sobre Bogota con puntaje valido. El desglose por estado esta en 06_match_sede_periodo.csv.",
      TRUE ~ "Diferencia no explicada; revisar la etapa correspondiente antes de usar la cifra."
    )
  )
escribir_csv(expected_vs_observed, "12_expected_vs_observed.csv")

# ---------------------------------------------------------------------------
# Etapa 10: metadatos, inmutabilidad de insumos y cierre
# ---------------------------------------------------------------------------

sha_final <- vapply(names(sha_inicial), sha256_archivo, character(1))
insumos_intactos <- identical(unname(sha_inicial), unname(sha_final))
if (!insumos_intactos) {
  warning("Al menos un insumo cambio de SHA-256 durante la ejecucion.")
}

digest_agregados <- digest::digest(list(
  momentos_df, integridad_df, embudo, match_periodo, expected_vs_observed
), algo = "sha256")

ruta_meta <- file.path(RUTAS_FASE1$auditoria, "run_metadata.json")
digest_anterior <- if (file.exists(ruta_meta)) {
  tryCatch(jsonlite::fromJSON(ruta_meta)$digest_agregados, error = function(e) NA_character_)
} else NA_character_

jsonlite::write_json(
  list(
    fase = "1",
    inicio = format(t_inicio, "%Y-%m-%d %H:%M:%S"),
    fin = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    duracion_min = round(as.numeric(difftime(Sys.time(), t_inicio, units = "mins")), 2),
    r_version = R.version.string,
    paquetes = vapply(c("readr", "dplyr", "arrow", "sf", "digest"),
                      function(p) as.character(packageVersion(p)), character(1)),
    n_archivos = length(archivos_txt),
    filas_nacionales_no_faltantes = unname(observados["registros_nacionales"]),
    filas_bogota_total = nrow(base),
    filas_bogota_punt_valido = unname(observados["registros_bogota"]),
    filas_muestra_principal = sum(base$is_main_sample),
    crs_declarado_gpkg = crs_declarado,
    crs_aplicado = "EPSG:4326 via st_set_crs",
    evidencia_crs = evidencia_crs,
    insumos_intactos = insumos_intactos,
    legacy_nota = legacy_nota,
    digest_agregados = digest_agregados,
    digest_corrida_anterior = digest_anterior,
    cardinalidad = cardinalidad
  ),
  ruta_meta, auto_unbox = TRUE, pretty = TRUE
)

writeLines(capture.output(sessionInfo()), file.path(RUTAS_FASE1$auditoria, "sessionInfo.txt"))

log_etapa("Fin. Bogota total: ", format(nrow(base), big.mark = ","),
          " | muestra principal: ", format(sum(base$is_main_sample), big.mark = ","),
          " | insumos intactos: ", insumos_intactos)
