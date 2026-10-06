#!/usr/bin/env Rscript

# Validacion directa de la base privada contra sus insumos y contra la evidencia
# publicada. A diferencia de 02, que audita las tablas de la Fase 1, este script
# recalcula desde el parquet y desde los originales.
#
# Un fallo critico termina con codigo de salida 1 y bloquea cualquier
# afirmacion de validacion positiva.
#
# Ejecutar desde la raiz del proyecto:  Rscript R/03_validar_parquet.R

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(arrow)
  library(sf)
  library(jsonlite)
})

source(file.path("R", "utils", "validation_helpers.R"))

# El estado queda EN_CURSO desde aqui: una excepcion no deja utilizable una
# aprobacion anterior.
marcar_validacion_en_curso("03_validar_parquet")

AUD       <- RUTAS_FASE1$auditoria
ruta_base <- file.path(RUTAS_FASE1$privado, "saber11_bogota_sede_auditada.parquet")
if (!file.exists(ruta_base)) stop("No existe ", ruta_base)

base <- read_parquet(ruta_base)
num  <- function(x) suppressWarnings(as.numeric(x))

pruebas <- list()
registrar <- function(id, descripcion, observado, regla, ok, critica = TRUE) {
  pruebas[[length(pruebas) + 1]] <<- data.frame(
    id_prueba = id, descripcion = descripcion,
    valor_observado = as.character(observado), regla_aceptacion = regla,
    estado = if (ok) "PASS" else if (critica) "FAIL" else "REVIEW",
    critica = critica, stringsAsFactors = FALSE
  )
}

cat("Validacion directa del parquet\n")

# ---------------------------------------------------------------------------
# A. Formula de estandarizacion
# ---------------------------------------------------------------------------

val <- base$punt_global_valido
z_rec <- (base$punt_global_num - base$media_nacional_periodo) / base$sd_nacional_periodo
dif_z <- max(abs(z_rec[val] - base$z_punt_global_nacional[val]))
registrar("V01", "z almacenado reproduce (punt_global - media) / sd fila a fila",
          sprintf("desviacion maxima %.3e", dif_z), "desviacion < 1e-12", dif_z < 1e-12)

z_fuera <- sum(!is.na(base$z_punt_global_nacional) & !val)
registrar("V02", "No hay z calculado sobre puntajes invalidos",
          sprintf("%d filas", z_fuera), "0 filas", z_fuera == 0)

momentos_unicos <- base %>%
  group_by(periodo_fuente) %>%
  summarise(n_media = n_distinct(media_nacional_periodo),
            n_sd = n_distinct(sd_nacional_periodo), .groups = "drop")
mom_ok <- all(momentos_unicos$n_media == 1 & momentos_unicos$n_sd == 1)
registrar("V03", "Media y desviacion nacionales son constantes dentro de cada periodo",
          sprintf("%d/%d periodos con un unico par", sum(momentos_unicos$n_media == 1 &
                  momentos_unicos$n_sd == 1), nrow(momentos_unicos)),
          "un unico par por periodo", mom_ok)

# Recalculo independiente de los momentos nacionales desde los TXT originales,
# leyendo solo periodo y punt_global.
archivos_txt <- sort(list.files(RUTAS_FASE1$raw,
                                pattern = "^Examen_Saber_11_[0-9]{5}\\.txt$",
                                recursive = TRUE, full.names = TRUE))
momentos_indep <- lapply(archivos_txt, function(path) {
  per <- str_extract(basename(path), "[0-9]{5}")
  x <- read_delim(path, delim = ";", locale = locale(encoding = "UTF-8"),
                  col_types = cols(.default = col_character()),
                  col_select = all_of(c("periodo", "punt_global")),
                  na = character(), show_col_types = FALSE, progress = FALSE)
  pg <- suppressWarnings(as.numeric(trimws(x$punt_global)))
  ok <- !is.na(pg) & pg >= PUNT_GLOBAL_MIN & pg <= PUNT_GLOBAL_MAX
  data.frame(periodo_fuente = per, n_indep = sum(ok),
             media_indep = mean(pg[ok]), sd_indep = sd(pg[ok]),
             stringsAsFactors = FALSE)
}) %>% bind_rows()

momentos_base <- base %>%
  group_by(periodo_fuente) %>%
  summarise(media_base = first(media_nacional_periodo),
            sd_base = first(sd_nacional_periodo), .groups = "drop")

cmp_mom <- left_join(momentos_indep, momentos_base, by = "periodo_fuente") %>%
  mutate(dif_media = abs(media_indep - media_base), dif_sd = abs(sd_indep - sd_base))
registrar("V04", "Los momentos nacionales se reproducen leyendo de nuevo los TXT originales",
          sprintf("dif. maxima media %.2e, sd %.2e en %d periodos",
                  max(cmp_mom$dif_media), max(cmp_mom$dif_sd), nrow(cmp_mom)),
          "diferencias < 1e-9",
          max(cmp_mom$dif_media) < 1e-9 && max(cmp_mom$dif_sd) < 1e-9)

# La poblacion que define los momentos debe exceder a Bogota en cada periodo.
cmp_pob <- left_join(momentos_indep,
                     base %>% count(periodo_fuente, name = "n_bogota"),
                     by = "periodo_fuente")
registrar("V05", "La poblacion de los momentos es nacional, no bogotana",
          sprintf("razon minima nacional/Bogota %.1f", min(cmp_pob$n_indep / cmp_pob$n_bogota)),
          "la poblacion nacional excede a Bogota en los 18 periodos",
          all(cmp_pob$n_indep > cmp_pob$n_bogota))

# ---------------------------------------------------------------------------
# B. Correspondencia de codigos de sede
# ---------------------------------------------------------------------------

colegios <- st_read(RUTAS_FASE1$gpkg, quiet = TRUE)
co <- st_coordinates(colegios)
cat_sed <- normalizar_codigo(st_drop_geometry(colegios)$DANE12_SED)
cat_lon <- co[, 1]; cat_lat <- co[, 2]

es_exacto <- base$match_status %in% c("exact_match_valid_coordinates",
                                      "exact_match_invalid_coordinates")

mal_codigo <- sum(es_exacto & base$dane12_sed_catalogo != base$cole_cod_dane_sede_norm)
registrar("V06", "En todo match exacto el codigo del catalogo es identico al codigo ICFES de sede",
          sprintf("%d discrepancias", mal_codigo), "0 discrepancias", mal_codigo == 0)

fuera_catalogo <- sum(es_exacto & !(base$dane12_sed_catalogo %in% cat_sed))
registrar("V07", "Todo codigo vinculado existe en el catalogo 2025 releido del GPKG",
          sprintf("%d codigos ausentes", fuera_catalogo), "0 ausentes", fuera_catalogo == 0)

sin_metodo <- sum(!es_exacto & base$match_method != "ninguno")
con_geo_sin_match <- sum(!es_exacto & (!is.na(base$lon) | !is.na(base$lat)))
registrar("V08", "Ningun registro sin match exacto recibe coordenadas ni metodo de vinculacion",
          sprintf("%d con metodo, %d con coordenada", sin_metodo, con_geo_sin_match),
          "0 y 0", sin_metodo == 0 && con_geo_sin_match == 0)

# El codigo de establecimiento no sustituye al de sede en ningun caso.
usa_est <- sum(es_exacto &
                 base$dane12_sed_catalogo == base$cole_cod_dane_establecimiento_norm &
                 base$cole_cod_dane_sede_norm != base$cole_cod_dane_establecimiento_norm,
               na.rm = TRUE)
registrar("V09", "El codigo de establecimiento nunca se uso como llave de sede",
          sprintf("%d casos", usa_est), "0 casos", usa_est == 0)

# ---------------------------------------------------------------------------
# C. Coordenadas
# ---------------------------------------------------------------------------

mapa_coord <- data.frame(sed = cat_sed, lon_cat = cat_lon, lat_cat = cat_lat,
                         stringsAsFactors = FALSE)
chk <- base %>%
  filter(es_exacto) %>%
  select(sed = dane12_sed_catalogo, lon, lat) %>%
  distinct() %>%
  left_join(mapa_coord, by = "sed")
dif_coord <- max(c(abs(chk$lon - chk$lon_cat), abs(chk$lat - chk$lat_cat)), na.rm = TRUE)
registrar("V10", "Las coordenadas de la base coinciden con las del GPKG para la misma sede",
          sprintf("desviacion maxima %.3e grados", dif_coord), "desviacion < 1e-9",
          dif_coord < 1e-9)

mp <- base$is_main_sample
fuera_bbox <- sum(mp & !(base$lon >= BBOX_BOGOTA$lon_min & base$lon <= BBOX_BOGOTA$lon_max &
                           base$lat >= BBOX_BOGOTA$lat_min & base$lat <= BBOX_BOGOTA$lat_max))
registrar("V11", "Toda la muestra principal cae dentro del bbox aprobado de Bogota D.C.",
          sprintf("%d filas fuera", fuera_bbox), "0 filas", fuera_bbox == 0)

centinela <- sum(mp & (abs(base$lon) > 1e300 | abs(base$lat) > 1e300 |
                         !is.finite(base$lon) | !is.finite(base$lat)))
registrar("V12", "No hay geometrias centinela en la muestra principal",
          sprintf("%d filas", centinela), "0 filas", centinela == 0)

# ---------------------------------------------------------------------------
# D. Seleccion de la muestra
# ---------------------------------------------------------------------------

mp_esperada <- base$match_status == "exact_match_valid_coordinates" & base$punt_global_valido
registrar("V13", "is_main_sample equivale a match exacto con coordenada valida y puntaje valido",
          sprintf("%d desacuerdos", sum(mp != mp_esperada)), "0 desacuerdos",
          all(mp == mp_esperada))

ESTADOS <- c("exact_match_valid_coordinates", "exact_match_invalid_coordinates",
             "valid_code_not_in_catalog", "missing_or_invalid_seat_code",
             "catalog_conflict", "pending_manual_review")
estados_ok <- all(base$match_status %in% ESTADOS) && !any(is.na(base$match_status))
registrar("V14", "Todo registro tiene exactamente un estado valido",
          sprintf("%d estados observados, %d filas sin estado",
                  n_distinct(base$match_status), sum(is.na(base$match_status))),
          "estados dentro del catalogo cerrado y sin faltantes", estados_ok)

excl_ok <- all(is.na(base$exclusion_reason[mp])) && all(!is.na(base$exclusion_reason[!mp]))
registrar("V15", "exclusion_reason esta vacio si y solo si el registro entra a la muestra principal",
          sprintf("%d con motivo dentro de la muestra, %d sin motivo fuera",
                  sum(!is.na(base$exclusion_reason[mp])), sum(is.na(base$exclusion_reason[!mp]))),
          "0 y 0", excl_ok)

bog_ok <- all(normalizar_codigo(base$cole_cod_mcpio_ubicacion) == "11001")
registrar("V16", "Todo registro de la base cumple la regla de Bogota por codigo municipal",
          sprintf("%d filas con municipio distinto de 11001",
                  sum(normalizar_codigo(base$cole_cod_mcpio_ubicacion) != "11001")),
          "0 filas", bog_ok)

dane_texto <- vapply(c("cole_cod_dane_sede_orig", "cole_cod_dane_sede_norm",
                       "cole_cod_dane_establecimiento_orig",
                       "cole_cod_dane_establecimiento_norm",
                       "dane12_sed_catalogo", "dane12_est_catalogo"),
                     function(v) class(base[[v]])[1], character(1))
registrar("V17", "Los codigos DANE siguen siendo texto en el parquet",
          paste(unique(dane_texto), collapse = ", "), "todos character",
          all(dane_texto == "character"))

# ---------------------------------------------------------------------------
# E. La evidencia publicada corresponde a los archivos actuales
# ---------------------------------------------------------------------------

leer_aud <- function(nombre) {
  p <- file.path(AUD, nombre)
  if (!file.exists(p)) return(NULL)
  read_csv(p, col_types = cols(.default = col_character()), progress = FALSE)
}

match_csv <- leer_aud("06_match_sede_periodo.csv")
match_rec <- base %>%
  count(periodo = periodo_fuente, match_status, name = "n_rec") %>%
  mutate(periodo = as.character(periodo))
cmp_match <- match_csv %>%
  transmute(periodo, match_status, n_csv = num(n_registros),
            pct_periodo_csv = num(pct_periodo),
            pct_total_csv = num(pct_total_bogota)) %>%
  full_join(match_rec, by = c("periodo", "match_status")) %>%
  group_by(periodo) %>%
  mutate(pct_periodo_rec = pct(n_rec, sum(n_rec))) %>%
  ungroup() %>%
  mutate(pct_total_rec = pct(n_rec, nrow(base)))

dif_n <- sum(cmp_match$n_csv != cmp_match$n_rec, na.rm = TRUE) +
  sum(is.na(cmp_match$n_csv)) + sum(is.na(cmp_match$n_rec))
registrar("V18", "Los conteos de 06_match_sede_periodo.csv se reproducen desde el parquet actual",
          sprintf("%d celdas discrepantes sobre %d", dif_n, nrow(cmp_match)),
          "0 discrepancias", dif_n == 0)

# Cierre del parche 1.1: los porcentajes deben variar fila a fila y coincidir
# con el recalculo. La version defectuosa de pct() producia un valor constante.
dif_pct <- max(c(abs(cmp_match$pct_periodo_csv - cmp_match$pct_periodo_rec),
                 abs(cmp_match$pct_total_csv - cmp_match$pct_total_rec)), na.rm = TRUE)
n_pct_distintos <- n_distinct(cmp_match$pct_total_csv)
registrar("V19", "Los porcentajes publicados se recalculan correctamente (parche 1.1)",
          sprintf("desviacion maxima %.4f; %d valores distintos de pct_total_bogota sobre %d filas",
                  dif_pct, n_pct_distintos, nrow(cmp_match)),
          "desviacion < 1e-4 y mas de un valor distinto",
          dif_pct < 1e-4 && n_pct_distintos > 1)

embudo_csv <- leer_aud("05_embudo_bogota_periodo.csv")
embudo_rec <- base %>%
  group_by(periodo = periodo_fuente) %>%
  summarise(bogota_rec = n(), principal_rec = sum(is_main_sample),
            excluidos_rec = sum(!is_main_sample), .groups = "drop")
cmp_emb <- embudo_csv %>%
  transmute(periodo, bogota_csv = num(bogota_total),
            principal_csv = num(muestra_principal), excl_csv = num(excluidos)) %>%
  left_join(embudo_rec, by = "periodo")
dif_emb <- sum(cmp_emb$bogota_csv != cmp_emb$bogota_rec) +
  sum(cmp_emb$principal_csv != cmp_emb$principal_rec) +
  sum(cmp_emb$excl_csv != cmp_emb$excluidos_rec)
registrar("V20", "El embudo publicado reconcilia con el parquet actual",
          sprintf("%d discrepancias en %d periodos", dif_emb, nrow(cmp_emb)),
          "0 discrepancias", dif_emb == 0)

esperados_csv <- leer_aud("12_expected_vs_observed.csv")
obs_rec <- c(
  registros_bogota  = sum(base$punt_global_valido),
  match_exacto_sede = sum(es_exacto & base$punt_global_valido)
)
cmp_esp <- esperados_csv %>%
  filter(control %in% names(obs_rec)) %>%
  mutate(observado = num(observado), recalculado = unname(obs_rec[control]))
dif_esp <- sum(cmp_esp$observado != cmp_esp$recalculado)
registrar("V21", "Los controles publicados se reproducen desde el parquet actual",
          sprintf("%d de %d controles verificables coinciden",
                  sum(cmp_esp$observado == cmp_esp$recalculado), nrow(cmp_esp)),
          "todos coinciden", dif_esp == 0)

# Los insumos originales no deben haber cambiado desde el manifiesto.
manifiesto <- leer_aud("00_input_manifest.csv")
sha_ahora <- vapply(manifiesto$ruta_relativa, sha256_archivo, character(1))
iguales <- sum(unname(sha_ahora) == manifiesto$sha256, na.rm = TRUE)
registrar("V22", "Los insumos originales conservan su SHA-256",
          sprintf("%d/%d identicos", iguales, nrow(manifiesto)),
          "todos identicos", iguales == nrow(manifiesto))

# Ninguna tabla publica puede contener identificadores de estudiante.
csvs <- list.files(AUD, pattern = "\\.csv$", full.names = TRUE)
con_id <- csvs[vapply(csvs, function(p) {
  any(grepl("SB11[0-9]{10,}", readLines(p, warn = FALSE)))
}, logical(1))]
registrar("V23", "Ninguna tabla publica contiene identificadores individuales",
          if (length(con_id) == 0) "ninguna" else paste(basename(con_id), collapse = ", "),
          "0 archivos con patron SB11...", length(con_id) == 0)

# ---------------------------------------------------------------------------
# Cierre
# ---------------------------------------------------------------------------

resultado <- bind_rows(pruebas)
escribir_csv(resultado, "13_validacion_parquet.csv")

n_fail <- sum(resultado$estado == "FAIL")
n_rev  <- sum(resultado$estado == "REVIEW")
n_pass <- sum(resultado$estado == "PASS")

cat(sprintf("\n%d PASS, %d FAIL, %d REVIEW sobre %d pruebas\n",
            n_pass, n_fail, n_rev, nrow(resultado)))
for (i in seq_len(nrow(resultado))) {
  if (resultado$estado[i] != "PASS") {
    cat(sprintf("  %s [%s] %s -> %s\n", resultado$id_prueba[i], resultado$estado[i],
                resultado$descripcion[i], resultado$valor_observado[i]))
  }
}

if (n_fail > 0) {
  fallidas <- resultado$id_prueba[resultado$estado == "FAIL"]
  invalidar_entrega("03_validar_parquet", fallidas)
  cat(sprintf("VALIDACION DEL PARQUET FALLIDA: %s.\n", paste(fallidas, collapse = ", ")))
  cat("Entrega invalidada: las afirmaciones vigentes quedan retenidas y el analisis no debe ejecutarse.\n")
  quit(status = 1L)
}

# La huella queda registrada para que 04 compruebe que consume exactamente el
# parquet que se valido.
registrar_estado_validacion("03_validar_parquet", "VALIDA",
                            list(pruebas_pass = n_pass,
                                 huella_parquet = huella_parquet()))
cat("Validacion directa del parquet superada. Huella registrada:",
    substr(huella_parquet(), 1, 16), "\n")
