#!/usr/bin/env Rscript

# Fase 1: validacion independiente de la base reconstruida.
# No recalcula el pipeline; lee sus productos y emite un veredicto.
#
# Ejecutar desde la raiz del proyecto:  Rscript R/02_validar_fase1.R

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(arrow)
  library(jsonlite)
  library(digest)
})

source(file.path("R", "utils", "validation_helpers.R"))

# El estado queda EN_CURSO desde aqui: una excepcion no deja utilizable una
# aprobacion anterior.
marcar_validacion_en_curso("02_validar_fase1")

AUD <- RUTAS_FASE1$auditoria
ruta_base <- file.path(RUTAS_FASE1$privado, "saber11_bogota_sede_auditada.parquet")

if (!file.exists(ruta_base)) {
  stop("No existe ", ruta_base, ". Ejecute antes R/01_reconstruir_base_geocodificada.R")
}

leer_aud <- function(nombre) {
  p <- file.path(AUD, nombre)
  if (!file.exists(p)) return(NULL)
  read_csv(p, col_types = cols(.default = col_character()), progress = FALSE)
}

base       <- read_parquet(ruta_base)
manifiesto <- leer_aud("00_input_manifest.csv")
integridad <- leer_aud("02_integridad_llave_periodo.csv")
momentos   <- leer_aud("03_momentos_nacionales_periodo.csv")
embudo     <- leer_aud("05_embudo_bogota_periodo.csv")
esperados  <- leer_aud("12_expected_vs_observed.csv")
meta       <- fromJSON(file.path(AUD, "run_metadata.json"))

num <- function(x) suppressWarnings(as.numeric(x))

ESTADOS_VALIDOS <- c("exact_match_valid_coordinates", "exact_match_invalid_coordinates",
                     "valid_code_not_in_catalog", "missing_or_invalid_seat_code",
                     "catalog_conflict", "pending_manual_review")

resultados <- list()
registrar <- function(id, descripcion, observado, regla, estado, evidencia) {
  resultados[[length(resultados) + 1]] <<- data.frame(
    id_prueba = id, descripcion = descripcion,
    valor_observado = as.character(observado), regla_aceptacion = regla,
    estado = estado, archivo_evidencia = evidencia, stringsAsFactors = FALSE
  )
}

# 1
n_per <- n_distinct(base$periodo_fuente)
registrar("T01", "Hay exactamente 18 periodos unicos", n_per,
          "n_distinct(periodo_fuente) == 18",
          if (n_per == 18L) "PASS" else "FAIL", "00_input_manifest.csv")

# 2
sha_ahora <- vapply(manifiesto$ruta_relativa, sha256_archivo, character(1))
iguales <- sum(unname(sha_ahora) == manifiesto$sha256, na.rm = TRUE)
registrar("T02", "Ningun insumo cambio durante y despues de la ejecucion",
          sprintf("%d/%d SHA-256 identicos", iguales, nrow(manifiesto)),
          "todos los SHA-256 coinciden con el manifiesto",
          if (iguales == nrow(manifiesto) && isTRUE(meta$insumos_intactos)) "PASS" else "FAIL",
          "00_input_manifest.csv")

# 3
cols_dane <- c("cole_cod_dane_sede_orig", "cole_cod_dane_sede_norm",
               "cole_cod_dane_establecimiento_orig", "cole_cod_dane_establecimiento_norm",
               "dane12_sed_catalogo", "dane12_est_catalogo")
tipos_dane <- vapply(cols_dane, function(v) class(base[[v]])[1], character(1))
registrar("T03", "Los codigos DANE permanecieron como texto",
          paste(sprintf("%s=%s", names(tipos_dane), tipos_dane), collapse = "; "),
          "todas las columnas DANE son character",
          if (all(tipos_dane == "character")) "PASS" else "FAIL",
          "data/processed/private/saber11_bogota_sede_auditada.parquet")

# 4
llave_ok <- all(c("periodo", "estu_consecutivo") %in% names(base))
registrar("T04", "La llave utilizada es periodo + estu_consecutivo",
          paste(intersect(c("periodo", "estu_consecutivo"), names(base)), collapse = " + "),
          "ambas columnas presentes en la base",
          if (llave_ok) "PASS" else "FAIL",
          "11_diccionario_base.csv")

# 5
falt_llave <- sum(is.na(base$estu_consecutivo) | base$estu_consecutivo == "")
dup_llave  <- sum(duplicated(paste(base$periodo_fuente, base$estu_consecutivo, sep = "\r")))
falt_arch  <- sum(num(integridad$consecutivos_faltantes))
dup_arch   <- sum(num(integridad$llaves_duplicadas))
registrar("T05", "La llave no tiene faltantes ni duplicados dentro del periodo",
          sprintf("base: %d faltantes, %d duplicados | archivos: %d faltantes, %d duplicados",
                  falt_llave, dup_llave, falt_arch, dup_arch),
          "los cuatro conteos son 0",
          if (falt_llave == 0 && dup_llave == 0 && falt_arch == 0 && dup_arch == 0) "PASS" else "FAIL",
          "02_integridad_llave_periodo.csv")

# 6
disc_arch <- sum(num(integridad$discrepancias_periodo))
disc_base <- sum(base$periodo != base$periodo_fuente, na.rm = TRUE) + sum(is.na(base$periodo))
registrar("T06", "El periodo interno coincide con el periodo del archivo",
          sprintf("archivos: %d | base: %d", disc_arch, disc_base),
          "ambos conteos son 0",
          if (disc_arch == 0 && disc_base == 0) "PASS" else "FAIL",
          "02_integridad_llave_periodo.csv")

# 7
cmp <- momentos %>%
  select(periodo, obs_no_faltantes) %>%
  mutate(obs_no_faltantes = num(obs_no_faltantes)) %>%
  left_join(embudo %>% select(periodo, bogota_regla_municipio) %>%
              mutate(bogota_regla_municipio = num(bogota_regla_municipio)), by = "periodo")
antes_ok <- all(cmp$obs_no_faltantes > cmp$bogota_regla_municipio)
registrar("T07", "Los momentos nacionales se calcularon antes de filtrar Bogota",
          sprintf("en %d/%d periodos la poblacion de momentos supera a Bogota",
                  sum(cmp$obs_no_faltantes > cmp$bogota_regla_municipio), nrow(cmp)),
          "la poblacion de momentos excede a Bogota en los 18 periodos",
          if (antes_ok) "PASS" else "FAIL", "03_momentos_nacionales_periodo.csv")

# 8 y 9
max_media_z <- max(abs(num(momentos$media_z)))
max_sd_z    <- max(abs(num(momentos$sd_z) - 1))
registrar("T08", "La media del z-score nacional es aproximadamente 0 por periodo",
          sprintf("max |media| = %.3e", max_media_z), "max |media| < 1e-8",
          if (max_media_z < 1e-8) "PASS" else "FAIL", "03_momentos_nacionales_periodo.csv")
registrar("T09", "La desviacion del z-score nacional es aproximadamente 1 por periodo",
          sprintf("max |sd - 1| = %.3e", max_sd_z), "max |sd - 1| < 1e-8",
          if (max_sd_z < 1e-8) "PASS" else "FAIL", "03_momentos_nacionales_periodo.csv")

# 10
card <- meta$cardinalidad
filas_antes   <- card$filas[card$etapa == "antes_union"]
filas_despues <- card$filas[card$etapa == "despues_union"]
registrar("T10", "La union con el catalogo no multiplica estudiantes",
          sprintf("%s -> %s filas", format(filas_antes, big.mark = ","),
                  format(filas_despues, big.mark = ",")),
          "filas despues == filas antes",
          if (identical(filas_antes, filas_despues)) "PASS" else "FAIL", "run_metadata.json")

# 11
# Se inspecciona el arbol sintactico, no el texto: buscar por grep encontraria
# las cadenas de patron de este mismo archivo y daria un falso positivo.
tokens_de <- function(paths) {
  do.call(rbind, lapply(paths, function(p) {
    pd <- utils::getParseData(parse(p, keep.source = TRUE))
    pd[, c("token", "text")]
  }))
}

SCRIPTS_MUESTRA <- c("R/01_reconstruir_base_geocodificada.R",
                     "R/utils/validation_helpers.R")

metodos <- sort(unique(base$match_method))
llamadas <- local({
  tk <- tokens_de(SCRIPTS_MUESTRA)
  tk$text[tk$token == "SYMBOL_FUNCTION_CALL"]
})
prohibidos <- c("adist", "agrep", "stringdist", "stringdistmatrix",
                "st_nearest_feature", "st_nearest_points", "st_join",
                "st_within", "st_buffer", "st_distance", "st_intersects")
hallados <- intersect(prohibidos, llamadas)
metodo_ok <- all(metodos %in% c("dane_sede_exacto", "ninguno")) && length(hallados) == 0
registrar("T11", "No se uso nombre, fuzzy, proximidad ni primera sede para la muestra principal",
          sprintf("match_method: %s | funciones prohibidas en los scripts que construyen la muestra: %s",
                  paste(metodos, collapse = ", "),
                  if (length(hallados) == 0) "ninguna" else paste(hallados, collapse = ", ")),
          "match_method solo dane_sede_exacto o ninguno, y sin funciones de emparejamiento aproximado o espacial",
          if (metodo_ok) "PASS" else "FAIL", "06_match_sede_periodo.csv")

# 12
tab_estados <- table(base$match_status, useNA = "ifany")
estados_ok <- all(names(tab_estados) %in% ESTADOS_VALIDOS) &&
  !any(is.na(names(tab_estados))) && sum(tab_estados) == nrow(base)
registrar("T12", "Los estados del cruce son exhaustivos y mutuamente excluyentes",
          sprintf("%d estados suman %s de %s filas", length(tab_estados),
                  format(sum(tab_estados), big.mark = ","), format(nrow(base), big.mark = ",")),
          "cada fila tiene exactamente un estado valido",
          if (estados_ok) "PASS" else "FAIL", "06_match_sede_periodo.csv")

# 13
rec <- embudo %>%
  mutate(across(c(bogota_total, muestra_principal, excluidos), num)) %>%
  mutate(desfase = bogota_total - (muestra_principal + excluidos))
suma_ok <- all(rec$desfase == 0) && sum(rec$bogota_total) == nrow(base)
registrar("T13", "La suma del embudo reconcilia con el total de Bogota",
          sprintf("desfase maximo por periodo: %d | total embudo %s vs base %s",
                  max(abs(rec$desfase)), format(sum(rec$bogota_total), big.mark = ","),
                  format(nrow(base), big.mark = ",")),
          "muestra principal + excluidos == total de Bogota en cada periodo",
          if (suma_ok) "PASS" else "FAIL", "05_embudo_bogota_periodo.csv")

# 14
tk_nuevos <- tokens_de(c(SCRIPTS_MUESTRA, "R/02_validar_fase1.R"))
n_setwd <- sum(tk_nuevos$token == "SYMBOL_FUNCTION_CALL" & tk_nuevos$text == "setwd")
cadenas <- tk_nuevos$text[tk_nuevos$token == "STR_CONST"]
rutas_abs <- grep('^"(/Users/|/home/|/Volumes/|[A-Za-z]:[\\\\/])', cadenas, value = TRUE)
abs_hits <- c(rep("setwd", n_setwd), rutas_abs)
registrar("T14", "No existen rutas absolutas ni setwd() en los scripts nuevos",
          sprintf("%d llamadas a setwd, %d cadenas con ruta absoluta", n_setwd, length(rutas_abs)),
          "cero coincidencias de setwd() o rutas absolutas",
          if (length(abs_hits) == 0) "PASS" else "FAIL", "R/")

# 15
# Una regla en .gitignore no desversiona un archivo ya rastreado. Si hay
# repositorio se inspecciona el indice; si no lo hay, se registra N/A con su
# alcance y no se promete un PASS futuro.
gi <- if (file.exists(".gitignore")) readLines(".gitignore", warn = FALSE) else character()
# data/*.zip: un .gitignore que excluye el directorio data/raw/ no excluye
# data/raw.zip, que contiene los mismos microdatos comprimidos.
reglas <- c("data/raw/", "data/processed/private/", "outputs/portafolio/modelos/",
            "data/*.zip", ".Rhistory", ".RData", "CLAUDE.local.md")
faltan_reglas <- reglas[!vapply(reglas, function(r) any(trimws(gi) == r), logical(1))]
reglas_ok <- sprintf("reglas .gitignore %d/%d", length(reglas) - length(faltan_reglas), length(reglas))

raiz_repo <- tryCatch(
  suppressWarnings(system2("git", c("rev-parse", "--show-toplevel"),
                           stdout = TRUE, stderr = FALSE)),
  error = function(e) character())
hay_repo <- length(raiz_repo) == 1 && nzchar(raiz_repo) &&
  identical(normalizePath(raiz_repo, mustWork = FALSE), normalizePath(".", mustWork = FALSE))

# Las extensiones se escriben como clase de caracteres [.] en lugar de escapes
# anidados: "\\\\.zip$" en una cadena de R produce la regex \\.zip$, que busca una
# barra invertida literal y no casa con data/raw.zip.
PATRON_SENSIBLE <- paste0("^data/raw/|^data/processed/private/|^data/cleaned/|^data/analysis/",
                          "|^outputs/portafolio/modelos/|^data/.*[.]zip$",
                          "|[.]parquet$|Examen_Saber_11_")

if (hay_repo) {
  rastreados <- tryCatch(suppressWarnings(system2("git", c("ls-files"), stdout = TRUE, stderr = FALSE)),
                         error = function(e) character())
  preparados <- tryCatch(suppressWarnings(system2("git", c("diff", "--cached", "--name-only"),
                                                 stdout = TRUE, stderr = FALSE)),
                         error = function(e) character())
  sensibles <- unique(c(grep(PATRON_SENSIBLE, rastreados, value = TRUE),
                        grep(PATRON_SENSIBLE, preparados, value = TRUE)))
  git_ok <- length(sensibles) == 0 && length(faltan_reglas) == 0
  registrar("T15", "Raw, microdatos y bases privadas estan excluidos de Git",
            sprintf("repositorio presente; %d archivo(s) sensible(s) versionado(s) o preparado(s); %s%s",
                    length(sensibles), reglas_ok,
                    if (length(sensibles)) paste0(" | ", paste(head(sensibles, 5), collapse = ", ")) else ""),
            "cero archivos sensibles en el indice y todas las reglas presentes",
            if (git_ok) "PASS" else "FAIL", ".gitignore")
} else {
  registrar("T15", "Raw, microdatos y bases privadas estan excluidos de Git",
            sprintf("no hay repositorio git en la raiz del proyecto; %s verificadas por inspeccion", reglas_ok),
            "sin repositorio no se puede inspeccionar el indice: alcance limitado a las reglas",
            "N/A - sin repositorio", ".gitignore")
}

# 16
digest_actual   <- meta$digest_agregados
digest_anterior <- meta$digest_corrida_anterior
estado_16 <- if (is.null(digest_anterior) || is.na(digest_anterior)) {
  "PENDIENTE"
} else if (identical(digest_actual, digest_anterior)) "PASS" else "FAIL"
registrar("T16", "Dos ejecuciones de 01 repiten los cinco agregados incluidos en el digest (momentos, integridad, embudo, match y controles)",
          if (estado_16 == "PENDIENTE") "sin corrida previa registrada"
          else sprintf("actual %s vs anterior %s", substr(digest_actual, 1, 12),
                       substr(digest_anterior, 1, 12)),
          "digest identico de esas cinco tablas entre corridas; no cubre el parquet completo ni el analisis",
          estado_16, "run_metadata.json")

validacion <- bind_rows(resultados)
escribir_csv(validacion, "validation_results.csv")

n_pass <- sum(validacion$estado == "PASS")
n_fail <- sum(validacion$estado == "FAIL")
n_otro <- nrow(validacion) - n_pass - n_fail

veredicto <- if (n_fail > 0) "FAIL" else if (n_otro > 0) "CONDITIONAL PASS" else "PASS"
cat(sprintf("Pruebas: %d PASS, %d FAIL, %d otros -> %s\n", n_pass, n_fail, n_otro, veredicto))

# ---------------------------------------------------------------------------
# Reportes
# ---------------------------------------------------------------------------

md_tabla <- function(df) {
  df <- as.data.frame(lapply(df, as.character), stringsAsFactors = FALSE)
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}

fmt <- function(x) format(as.numeric(x), big.mark = ",", scientific = FALSE, trim = TRUE)

reg <- function(n) sprintf("%s %s", fmt(n), if (n == 1) "registro" else "registros")

estados_tab <- base %>%
  count(match_status, name = "registros") %>%
  arrange(desc(registros)) %>%
  mutate(pct_bogota = sprintf("%.2f%%", 100 * registros / nrow(base)),
         registros = fmt(registros))

n_bogota      <- nrow(base)
n_principal   <- sum(base$is_main_sample)
n_valido      <- sum(base$punt_global_valido)
n_en_catalogo <- sum(base$match_status %in% c("exact_match_valid_coordinates",
                                              "exact_match_invalid_coordinates"))
n_conflicto   <- sum(base$conflicto_est_status == "conflicto_establecimiento")
n_pendiente   <- sum(base$match_status == "pending_manual_review")
n_sin_cat     <- sum(base$match_status == "valid_code_not_in_catalog")
n_sin_codigo  <- sum(base$match_status == "missing_or_invalid_seat_code")
sedes_conflicto <- n_distinct(base$cole_cod_dane_sede_norm[
  base$conflicto_est_status == "conflicto_establecimiento"])

reporte <- c(
  "# Fase 1 — Reporte de validacion",
  "",
  sprintf("Corrida: %s. Duracion: %s minutos.", meta$fin, meta$duracion_min),
  "",
  "## Objetivo",
  "",
  "Reconstruir desde los TXT originales del ICFES una base de resultados Saber 11 para",
  "colegios ubicados en Bogota cuya procedencia, poblacion, llave, estandarizacion del",
  "puntaje y vinculacion con sedes puedan auditarse y reproducirse.",
  "",
  "## Contrato de datos",
  "",
  sprintf("- Insumos: %d archivos, con SHA-256 registrado antes y despues de la corrida (`00_input_manifest.csv`).",
          nrow(manifiesto)),
  sprintf("- Insumos intactos al cerrar: %s.", meta$insumos_intactos),
  "- Codigos DANE leidos y conservados como texto. Sin `as.integer`, sin relleno de ceros.",
  "- Se conserva version original y normalizada de cada codigo.",
  "",
  "## Unidad de observacion",
  "",
  "Una presentacion del examen: `periodo + estu_consecutivo`. `estu_consecutivo` identifica",
  "una presentacion, no una persona seguida en el tiempo.",
  "",
  "## Definicion de la muestra",
  "",
  sprintf("- Universo Bogota: %s registros de colegios con `cole_cod_mcpio_ubicacion == \"11001\"`.", fmt(n_bogota)),
  sprintf("- Con puntaje global valido en [0,500]: %s.", fmt(n_valido)),
  sprintf("- Con coincidencia exacta de sede en el catalogo 2025: %s.", fmt(n_en_catalogo)),
  sprintf("- Muestra principal (`is_main_sample`): %s (%.2f%% de Bogota).",
          fmt(n_principal), 100 * n_principal / n_bogota),
  "",
  "## Regla de Bogota",
  "",
  "`cole_cod_mcpio_ubicacion == \"11001\"`, sobre la ubicacion del colegio, no sobre la",
  "residencia ni el municipio de presentacion del estudiante. Las reglas alternativas por",
  "codigo de departamento y por texto se calcularon en paralelo y sus discrepancias estan",
  "en `05_embudo_bogota_periodo.csv`.",
  "",
  "## Formula del z-score",
  "",
  "```",
  "z_punt_global_nacional = (punt_global - media_nacional_periodo) / sd_nacional_periodo",
  "```",
  "",
  "Media y desviacion se calculan por periodo sobre la poblacion nacional elegible",
  "(`punt_global` numerico y dentro de [0,500]), antes de cualquier filtro territorial.",
  "La desviacion es muestral (n-1).",
  "",
  "## Estrategia de vinculacion",
  "",
  "`cole_cod_dane_sede` contra `DANE12_SED` del catalogo 2025, texto contra texto, igualdad",
  "exacta. La union es many-to-one y esta garantizada por la unicidad de `DANE12_SED`.",
  "Los nombres solo generan candidatos de revision manual; no asignan coordenadas ni",
  "modifican `match_method`.",
  "",
  sprintf("El catalogo declara `%s` pero almacena grados (%s). Se corrige la etiqueta con",
          meta$crs_declarado_gpkg, meta$evidencia_crs),
  "`st_set_crs(4326)`; no se reproyecta y no se modifica el archivo en disco.",
  "",
  "## Resultados de las pruebas",
  "",
  md_tabla(validacion %>% select(id_prueba, descripcion, valor_observado, estado)),
  "",
  "## Estados del cruce",
  "",
  md_tabla(estados_tab),
  "",
  "## Embudo final",
  "",
  md_tabla(embudo %>% select(periodo, total_nacional, punt_global_valido,
                             bogota_regla_municipio, dane_sede_valido,
                             match_exacto_catalogo, coordenada_valida,
                             muestra_principal, excluidos)),
  "",
  "## Comparacion esperado contra observado",
  "",
  md_tabla(esperados %>% select(control, esperado, observado, diferencia, estado)),
  "",
  "## Limitaciones",
  "",
  "- La geografia es armonizada a una referencia contemporanea: el catalogo de sedes es de",
  sprintf("  %s y se aplica a resultados 2016-2024. No es geocodificacion historica certificada.", CATALOG_VINTAGE),
  "- Un cambio de establecimiento asociado a una misma sede no se corrige; se registra.",
  "- La comparacion con la base legacy es agregada por periodo y sede: el CSV legacy no",
  "  contiene `estu_consecutivo` y no permite reconciliacion fila a fila.",
  "- No hay repositorio Git en la raiz; la exclusion de microdatos se verifica por",
  "  inspeccion de `.gitignore`, no por el indice de Git.",
  "",
  "## Casos pendientes",
  "",
  sprintf("- %s en `pending_manual_review`: codigo de sede valido, sin match, con candidato por nombre.", reg(n_pendiente)),
  sprintf("- %s en `valid_code_not_in_catalog`: codigo valido, sin match y sin candidato.", reg(n_sin_cat)),
  sprintf("- %s sin codigo de sede utilizable.", reg(n_sin_codigo)),
  sprintf("- %s con desacuerdo de establecimiento entre ICFES y catalogo, en %d sedes.",
          reg(n_conflicto), sedes_conflicto),
  "",
  "## Conclusion",
  "",
  sprintf("**%s** — %d pruebas PASS, %d FAIL, %d en otro estado.", veredicto, n_pass, n_fail, n_otro),
  ""
)
writeLines(reporte, file.path(AUD, "FASE1_VALIDATION_REPORT.md"))

# --- Decisiones que requieren a David ---------------------------------------

bloque_decision <- function(decision, evidencia, opciones, consecuencias, recomendacion) {
  c(sprintf("Decision: %s", decision),
    sprintf("Evidencia disponible: %s", evidencia),
    sprintf("Opciones: %s", opciones),
    sprintf("Consecuencia de cada opcion: %s", consecuencias),
    sprintf("Recomendacion tecnica: %s", recomendacion),
    "Estado: REQUIERE DECISION DE DAVID", "")
}

decisiones <- c("# Decisiones pendientes — Fase 1", "")

decisiones <- c(decisiones, bloque_decision(
  "Que hacer con los registros de Bogota sin coincidencia exacta de sede en el catalogo 2025.",
  sprintf("%s en pending_manual_review y %s en valid_code_not_in_catalog; el detalle por sede esta en 09_sin_match_agregado.csv.",
          reg(n_pendiente), reg(n_sin_cat)),
  "(a) dejarlos excluidos y documentar la perdida; (b) resolverlos manualmente sede por sede a partir de los candidatos por nombre; (c) incorporar un catalogo historico de sedes como fuente independiente.",
  "(a) conserva la trazabilidad y reduce cobertura; (b) recupera cobertura pero introduce criterio humano que debe quedar registrado; (c) es la unica via que permitiria hablar de geografia historica.",
  "(a) para cerrar la Fase 1, y abrir (c) como tarea propia antes de cualquier afirmacion historica."))

decisiones <- c(decisiones, bloque_decision(
  "Como tratar los desacuerdos entre el establecimiento reportado por ICFES y el asociado a la sede en el catalogo 2025.",
  sprintf("%s registros en %d sedes, listados en 08_conflictos_sede_establecimiento.csv. No se corrigieron automaticamente.",
          fmt(n_conflicto), sedes_conflicto),
  "(a) conservarlos en la muestra principal marcados; (b) excluirlos de la muestra principal; (c) resolverlos caso por caso.",
  "(a) mantiene la cobertura y traslada el juicio a la Fase 2; (b) reduce la muestra por un desacuerdo administrativo que no afecta la ubicacion de la sede; (c) es costoso y requiere fuente externa.",
  "(a): el cruce es sede contra sede y la coordenada proviene de la sede, no del establecimiento. El conflicto es informativo, no invalidante."))

decisiones <- c(decisiones, bloque_decision(
  "Si la Fase 2 debe recalcular UPZ y UPL desde la geometria de la sede en lugar de heredar los atributos del catalogo.",
  "La base conserva cod_upz_catalogo y cod_upl_catalogo como atributos del GPKG, sin cruce espacial. La auditoria preliminar reporto discrepancias entre atributo y cruce espacial en UPZ y ZAT.",
  "(a) heredar los atributos del catalogo; (b) recalcular por cruce espacial contra los poligonos vigentes; (c) calcular ambos y reportar la discrepancia.",
  "(a) es barato pero arrastra la vigencia del catalogo; (b) es coherente con la unidad espacial declarada; (c) documenta el desacuerdo sin ocultarlo.",
  "(c), y fijar la convencion temporal de las geografias antes de estimar."))

if (any(esperados$estado != "PASS")) {
  dif <- esperados %>% filter(estado != "PASS")
  decisiones <- c(decisiones, bloque_decision(
    "Cual denominador nacional y cual universo de Bogota se adoptan como cifras oficiales del proyecto.",
    sprintf("Controles con diferencia: %s. El detalle esta en 12_expected_vs_observed.csv y 03_momentos_nacionales_periodo.csv.",
            paste(sprintf("%s (esperado %s, observado %s)", dif$control, dif$esperado, dif$observado),
                  collapse = "; ")),
    "(a) adoptar las cifras de esta reconstruccion y explicar la diferencia; (b) adoptar la definicion que reproduce el control heredado; (c) publicar ambas.",
    "(a) es consistente con la regla de elegibilidad aprobada; (b) subordina la definicion al numero previo; (c) obliga a explicar dos denominadores en cada tabla.",
    "(a): la regla de elegibilidad se fijo antes de observar los conteos y no debe moverse para reproducirlos."))
}

# Este archivo se regenera en cada corrida. Las decisiones que David ya tomo
# viven en docs/DECISIONES_HUMANAS.md, que ningun script sobrescribe.
decisiones <- c(decisiones,
  "---", "",
  "Archivo generado por `R/02_validar_fase1.R` en cada corrida.",
  "Las decisiones ya tomadas estan en `docs/DECISIONES_HUMANAS.md`, que ningun script sobrescribe.",
  "")
writeLines(decisiones, file.path(AUD, "DECISIONES_PENDIENTES.md"))

# --- Afirmaciones verificadas ------------------------------------------------

# Si alguna prueba falla, no se emite ninguna afirmacion verificada: un fallo
# critico invalida el respaldo de todas las cifras de esta corrida.
claims <- if (n_fail > 0) c(
  "# Afirmaciones verificadas — Fase 1",
  "",
  sprintf("**Retenidas.** %d prueba(s) de validacion fallaron en esta corrida (%s).",
          n_fail, paste(validacion$id_prueba[validacion$estado == "FAIL"], collapse = ", ")),
  "No se emite ninguna afirmacion cuantitativa hasta que la validacion pase.",
  "Ver `validation_results.csv` y `FASE1_VALIDATION_REPORT.md`.",
  ""
) else c(
  "# Afirmaciones verificadas — Fase 1",
  "",
  "Solo afirmaciones cuantitativas comprobadas en esta corrida. Cada una enlaza con la",
  "tabla o prueba que la respalda.",
  "",
  sprintf("- El universo original son %d archivos del ICFES, uno por aplicacion, de 2016-1 a 2024-2. [`00_input_manifest.csv`](00_input_manifest.csv), prueba T01 en [`validation_results.csv`](validation_results.csv)",
          sum(grepl("\\.txt$", manifiesto$archivo))),
  sprintf("- La llave `periodo + estu_consecutivo` no tiene faltantes ni duplicados dentro de ningun periodo. [`02_integridad_llave_periodo.csv`](02_integridad_llave_periodo.csv), prueba T05"),
  sprintf("- El periodo declarado coincide con el periodo del archivo en las %s filas procesadas. [`02_integridad_llave_periodo.csv`](02_integridad_llave_periodo.csv), prueba T06",
          fmt(sum(num(integridad$filas)))),
  sprintf("- El catalogo de sedes 2025 tiene %s sedes unicas en %s filas, correspondientes a %s establecimientos, de los cuales %s tienen mas de una sede. [`07_crosswalk_sede_catalogo_2025.csv`](07_crosswalk_sede_catalogo_2025.csv)",
          fmt(esperados$observado[esperados$control == "filas_gpkg"]),
          fmt(esperados$observado[esperados$control == "filas_gpkg"]),
          fmt(esperados$observado[esperados$control == "establecimientos_gpkg"]),
          fmt(esperados$observado[esperados$control == "establecimientos_multisede"])),
  sprintf("- %s sedes del catalogo tienen coordenada plausible dentro de Bogota D.C. y %s son geometrias centinela. [`07_crosswalk_sede_catalogo_2025.csv`](07_crosswalk_sede_catalogo_2025.csv)",
          fmt(esperados$observado[esperados$control == "coordenadas_plausibles"]),
          fmt(esperados$observado[esperados$control == "coordenadas_anomalas"])),
  sprintf("- %s registros corresponden a colegios ubicados en Bogota segun el codigo municipal 11001. [`05_embudo_bogota_periodo.csv`](05_embudo_bogota_periodo.csv)",
          fmt(n_bogota)),
  sprintf("- Las tres reglas posibles para identificar Bogota -- codigo municipal 11001, codigo de departamento 11 y texto del municipio -- seleccionan exactamente el mismo conjunto: %d discrepancias en los 18 periodos. [`05_embudo_bogota_periodo.csv`](05_embudo_bogota_periodo.csv)",
          sum(num(embudo$discrepancia_mcpio_depto)) + sum(num(embudo$discrepancia_mcpio_texto))),
  sprintf("- %s de esos registros enlazan exactamente por codigo DANE de sede con el catalogo 2025 (%.2f%%). [`06_match_sede_periodo.csv`](06_match_sede_periodo.csv)",
          fmt(n_en_catalogo), 100 * n_en_catalogo / n_bogota),
  sprintf("- La muestra principal, con match exacto, coordenada plausible y puntaje valido, es de %s registros (%.2f%% de Bogota). [`05_embudo_bogota_periodo.csv`](05_embudo_bogota_periodo.csv)",
          fmt(n_principal), 100 * n_principal / n_bogota),
  sprintf("- El z-score nacional por periodo tiene media maxima en valor absoluto de %.2e y desviacion que se aparta de 1 en a lo sumo %.2e. [`03_momentos_nacionales_periodo.csv`](03_momentos_nacionales_periodo.csv), pruebas T08 y T09",
          max_media_z, max_sd_z),
  sprintf("- La union con el catalogo no altero el numero de observaciones: %s filas antes y despues. [`run_metadata.json`](run_metadata.json), prueba T10",
          fmt(filas_antes)),
  sprintf("- La muestra principal se construyo exclusivamente con `match_method = dane_sede_exacto`; no se uso nombre, coincidencia aproximada, proximidad espacial ni primera sede. Prueba T11"),
  ""
)
writeLines(claims, file.path(AUD, "VALIDATED_CLAIMS.md"))

# --- Handoff -----------------------------------------------------------------

archivos_aud <- sort(list.files(AUD))
gates <- validacion %>% select(id_prueba, estado)

handoff <- c(
  "# Handoff — Fase 1",
  "",
  "## Que se creo",
  "",
  "```",
  "R/01_reconstruir_base_geocodificada.R",
  "R/02_validar_fase1.R",
  "R/utils/validation_helpers.R",
  ".gitignore",
  "data/processed/private/saber11_bogota_sede_auditada.parquet",
  "data/processed/private/fase1_unmatched_review.parquet",
  "outputs/audit/fase1/",
  "```",
  "",
  "## Que se modifico",
  "",
  "Ningun archivo preexistente fue modificado.",
  "",
  "## Que permanecio intacto",
  "",
  "`notebooks/main_report.Rmd`, `notebooks/main_report.html`, `README.md`,",
  "`R/export_geom_shiny.R`, `R/export_lisa_units.R`, `shiny/`, `outputs/figures`,",
  "`outputs/maps`, `outputs/models`, `outputs/tables`, `data/raw/`, `data/cleaned/`,",
  "`data/analysis/`, `audit/` y los dos PDF de la raiz.",
  "",
  sprintf("Los %d insumos conservan su SHA-256 original: %s.", nrow(manifiesto), meta$insumos_intactos),
  "",
  "## Comandos de reproduccion",
  "",
  "```bash",
  "Rscript R/01_reconstruir_base_geocodificada.R",
  "Rscript R/02_validar_fase1.R",
  "```",
  "",
  "Ambos desde la raiz del proyecto. Los TXT y el GPKG deben estar materializados en disco:",
  "si estan como marcadores de iCloud, `01` se detiene con un mensaje explicito en lugar de",
  "bloquearse en E/S.",
  "",
  "## Dependencias",
  "",
  sprintf("%s. Paquetes: %s.", meta$r_version,
          paste(sprintf("%s %s", names(meta$paquetes), unlist(meta$paquetes)), collapse = ", ")),
  "No se instalo ningun paquete durante la ejecucion.",
  "",
  "## Conteos finales",
  "",
  md_tabla(data.frame(
    concepto = c("Archivos procesados", "Filas nacionales con punt_global no faltante",
                 "Registros Bogota (codigo municipal 11001)",
                 "Registros Bogota con puntaje valido",
                 "Coincidencia exacta de sede con catalogo 2025",
                 "Muestra principal", "Pendientes de revision manual",
                 "Codigo valido sin match", "Sin codigo de sede utilizable",
                 "Desacuerdos establecimiento ICFES vs catalogo"),
    valor = c(fmt(meta$n_archivos), fmt(meta$filas_nacionales_no_faltantes),
              fmt(n_bogota), fmt(n_valido), fmt(n_en_catalogo), fmt(n_principal),
              fmt(n_pendiente), fmt(n_sin_cat), fmt(n_sin_codigo), fmt(n_conflicto)),
    stringsAsFactors = FALSE)),
  "",
  "## Resultado de los gates",
  "",
  md_tabla(validacion %>% select(id_prueba, descripcion, estado)),
  "",
  sprintf("Veredicto: **%s**.", veredicto),
  "",
  "## Limitaciones",
  "",
  "- Geografia armonizada al catalogo de sedes de 2025 aplicado a resultados 2016-2024.",
  "  No es geocodificacion historica certificada.",
  "- La comparacion con la base legacy es agregada por periodo y codigo de sede. El CSV",
  "  legacy no contiene `estu_consecutivo`, de modo que **no fue posible una reconciliacion",
  "  fila a fila** y no se produjo `legacy_comparison_rowlevel.parquet`. Esta reconstruccion",
  "  no debe presentarse como si fuera la base original corregida registro por registro.",
  "- `cod_upz_catalogo` y `cod_upl_catalogo` son atributos heredados del GPKG, no el",
  "  resultado de un cruce espacial.",
  "- No hay repositorio Git en la raiz, por decision explicita. Las pruebas relacionadas con",
  "  Git quedan como `N/A - integracion pendiente` y no se genero `git_diff.patch`.",
  "",
  "## Privacidad",
  "",
  "`estu_consecutivo` y los microdatos viven unicamente en `data/processed/private/`, que",
  "`.gitignore` excluye junto con `data/raw/`. Ninguna tabla de `outputs/audit/fase1/`",
  "contiene identificadores individuales: los archivos 08 y 09 estan agregados por sede y",
  "periodo, y el crosswalk 07 no incluye datos de estudiantes.",
  "",
  "## Decisiones pendientes",
  "",
  "Ver `DECISIONES_PENDIENTES.md`.",
  "",
  "## Archivos para revision",
  "",
  "```",
  paste0("outputs/audit/fase1/", archivos_aud),
  "R/01_reconstruir_base_geocodificada.R",
  "R/02_validar_fase1.R",
  "R/utils/validation_helpers.R",
  ".gitignore",
  "```",
  "",
  "Empaquetados en `FASE1_HANDOFF.zip`.",
  ""
)
writeLines(handoff, file.path(AUD, "HANDOFF_FASE1.md"))

# --- Paquete de entrega ------------------------------------------------------

if (file.exists("FASE1_HANDOFF.zip")) invisible(file.remove("FASE1_HANDOFF.zip"))
utils::zip("FASE1_HANDOFF.zip",
           files = c("R", file.path("outputs", "audit", "fase1"), ".gitignore"),
           flags = "-rq")

cat(sprintf("Reportes escritos en %s\nPaquete: FASE1_HANDOFF.zip (%.1f KB)\n",
            AUD, file.size("FASE1_HANDOFF.zip") / 1024))

if (n_fail > 0) {
  fallidas <- validacion$id_prueba[validacion$estado == "FAIL"]
  invalidar_entrega("02_validar_fase1", fallidas)
  cat(sprintf("VALIDACION FALLIDA: %s. Entrega invalidada. Codigo de salida 1.\n",
              paste(fallidas, collapse = ", ")))
  quit(status = 1L)
}
registrar_estado_validacion("02_validar_fase1", "VALIDA",
                            list(pruebas_pass = n_pass, veredicto = veredicto,
                                 huella_parquet = huella_parquet()))
