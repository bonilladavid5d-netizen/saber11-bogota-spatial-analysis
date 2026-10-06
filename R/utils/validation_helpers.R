# Utilidades compartidas por 01_reconstruir_base_geocodificada.R y 02_validar_fase1.R.
# Solo vive aqui lo que ambos scripts usan; el resto queda en el script que lo necesita.

RUTAS_FASE1 <- list(
  raw        = file.path("data", "raw"),
  gpkg       = file.path("data", "raw", "raw 2", "colegios06_2025.gpkg"),
  legacy_csv = file.path("data", "analysis", "estudiantes_bogota_geolocalizados.csv"),
  privado    = file.path("data", "processed", "private"),
  auditoria  = file.path("outputs", "audit", "fase1")
)

# Vigencia del catalogo de sedes. Corresponde al campo FECHA del GPKG y se
# propaga a la base para impedir que la geografia se lea como historica.
CATALOG_VINTAGE <- "2025-06-30"

# Ventana de plausibilidad para Bogota D.C. Incluye la ruralidad de Sumapaz,
# cuyas sedes bajan hasta lat 3.83 y quedarian fuera de un recorte urbano.
BBOX_BOGOTA <- list(lon_min = -74.50, lon_max = -73.95,
                    lat_min = 3.70, lat_max = 4.85)

# Rango admisible de punt_global. Define la poblacion nacional elegible.
PUNT_GLOBAL_MIN <- 0
PUNT_GLOBAL_MAX <- 500

# Cifras de contraste heredadas de la auditoria preliminar. Son diagnosticos:
# una diferencia se explica, nunca se corrige moviendo filtros.
CONTROLES_ESPERADOS <- data.frame(
  control  = c("archivos_periodos", "registros_nacionales", "registros_bogota",
               "match_exacto_sede", "filas_gpkg", "establecimientos_gpkg",
               "establecimientos_multisede", "coordenadas_plausibles",
               "coordenadas_anomalas", "llaves_faltantes", "llaves_duplicadas",
               "discrepancias_periodo"),
  esperado = c(18, 5982829, 791073, 770319, 2221, 1871, 216, 2219, 2, 0, 0, 0),
  stringsAsFactors = FALSE
)

sha256_archivo <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  digest::digest(file = path, algo = "sha256")
}

# Distingue un archivo real de un marcador de File Provider (iCloud). Leer un
# marcador dispara la descarga completa y puede bloquear el proceso por horas.
estado_archivo_local <- function(path) {
  if (!file.exists(path)) return("ausente")
  out <- tryCatch(
    system2("ls", c("-lO", shQuote(path)), stdout = TRUE, stderr = FALSE),
    error = function(e) character()
  )
  if (length(out) == 0) return(NA_character_)
  if (grepl("dataless", out[1], fixed = TRUE)) "dataless" else "local"
}

normalizar_codigo <- function(x) {
  x <- trimws(as.character(x))
  x[x == ""] <- NA_character_
  x
}

# Un DANE valido es exactamente 12 digitos. No se rellena con ceros: ambas
# fuentes ya entregan 12 caracteres y el relleno inventaria codigos.
es_dane_valido <- function(x) {
  !is.na(x) & grepl("^[0-9]{12}$", x)
}

tabla_cardinalidad <- function(df, llaves, etapa) {
  k <- do.call(paste, c(lapply(llaves, function(v) df[[v]]), list(sep = "\r")))
  data.frame(
    etapa         = etapa,
    filas         = nrow(df),
    llaves_unicas = length(unique(k)),
    duplicados    = nrow(df) - length(unique(k)),
    stringsAsFactors = FALSE
  )
}

# Parche 1.1. La version anterior usaba ifelse(), que devuelve un vector de la
# longitud de su condicion: con un total escalar y un x vectorial regresaba un
# unico valor que dplyr reciclaba, de modo que todas las filas heredaban el
# porcentaje de la primera. Afectaba a 01_schema_periodos, 06_match_sede_periodo
# y 10_legacy_vs_corregido_resumen.
pct <- function(x, total) {
  x <- as.numeric(x)
  total <- as.numeric(total)
  if (length(x) == 0L || length(total) == 0L) return(numeric(0))
  n <- max(length(x), length(total))
  if (length(x) == 1L) x <- rep(x, n)
  if (length(total) == 1L) total <- rep(total, n)
  if (length(x) != n || length(total) != n) {
    stop("pct(): longitudes incompatibles (x=", length(x), ", total=", length(total), ")")
  }
  out <- rep(NA_real_, n)
  ok <- !is.na(x) & !is.na(total) & total != 0
  out[ok] <- round(100 * x[ok] / total[ok], 4)
  out
}

escribir_csv <- function(df, nombre, dir = RUTAS_FASE1$auditoria) {
  readr::write_csv(df, file.path(dir, nombre), na = "")
  invisible(file.path(dir, nombre))
}

espacio_libre_gb <- function(path = ".") {
  out <- tryCatch(system2("df", c("-k", shQuote(path)), stdout = TRUE),
                  error = function(e) character())
  if (length(out) < 2) return(NA_real_)
  campos <- strsplit(trimws(out[length(out)]), "\\s+")[[1]]
  as.numeric(campos[4]) / 1024^2
}

# ---------------------------------------------------------------------------
# Estado de validacion compartido
# ---------------------------------------------------------------------------
# Un fallo en cualquier validador debe invalidar la entrega vigente, no solo
# devolver un codigo de salida. El analisis posterior comprueba este estado y
# la huella del parquet antes de ejecutarse.

RUTA_ESTADO_VALIDACION <- file.path(RUTAS_FASE1$auditoria, "estado_validacion.json")

leer_estado_validacion <- function() {
  if (!file.exists(RUTA_ESTADO_VALIDACION)) return(list())
  tryCatch(jsonlite::fromJSON(RUTA_ESTADO_VALIDACION, simplifyVector = TRUE),
           error = function(e) list())
}

registrar_estado_validacion <- function(script, estado, detalle = list()) {
  st <- leer_estado_validacion()
  st[[script]] <- c(list(estado = estado,
                         momento = format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
                    detalle)
  jsonlite::write_json(st, RUTA_ESTADO_VALIDACION, auto_unbox = TRUE, pretty = TRUE)
  invisible(st)
}

# Marca el script como en curso antes de empezar a validar. Si el proceso muere
# por una excepcion, el estado queda EN_CURSO y nunca VALIDA: una aprobacion
# anterior no sobrevive a una corrida que no termino.
marcar_validacion_en_curso <- function(script) {
  registrar_estado_validacion(script, "EN_CURSO",
                              list(huella_parquet = huella_parquet()))
}

huella_parquet <- function() {
  sha256_archivo(file.path(RUTAS_FASE1$privado, "saber11_bogota_sede_auditada.parquet"))
}

# Deja constancia visible de que la entrega vigente no esta respaldada.
invalidar_entrega <- function(script, pruebas_fallidas) {
  writeLines(c(
    "# Afirmaciones verificadas",
    "",
    sprintf("**Retenidas.** %s encontro %d prueba(s) fallida(s): %s.",
            script, length(pruebas_fallidas), paste(pruebas_fallidas, collapse = ", ")),
    "",
    "La entrega vigente queda **invalidada**. No se emite ninguna afirmacion",
    "cuantitativa, y los resultados de analisis anteriores no deben citarse hasta",
    "que ambos validadores vuelvan a pasar sobre la base actual.",
    "",
    "Ver `validation_results.csv`, `13_validacion_parquet.csv` y `estado_validacion.json`.",
    ""
  ), file.path(RUTAS_FASE1$auditoria, "VALIDATED_CLAIMS.md"))
  registrar_estado_validacion(script, "INVALIDA",
                              list(pruebas_fallidas = pruebas_fallidas,
                                   huella_parquet = huella_parquet()))
}

# Puerta de entrada del analisis: exige que ambos validadores hayan pasado
# sobre exactamente el parquet que se va a consumir.
# `requerir` lista los scripts cuyo estado debe ser VALIDA. Por defecto son solo
# los dos validadores: un script que marco su propia corrida como INVALIDA tiene
# que poder reintentarse, de lo contrario queda en bloqueo mutuo consigo mismo.
exigir_validacion <- function(requerir = c("02_validar_fase1", "03_validar_parquet")) {
  st <- leer_estado_validacion()
  faltan <- setdiff(requerir, names(st))
  if (length(faltan) > 0) {
    stop("No hay estado de validacion para: ", paste(faltan, collapse = ", "),
         ".\nEjecute primero ./run_analisis.sh", call. = FALSE)
  }
  malos <- requerir[vapply(st[requerir], function(x) !identical(x$estado, "VALIDA"), logical(1))]
  if (length(malos) > 0) {
    estados <- vapply(st[malos], function(x) as.character(x$estado), character(1))
    stop("La validacion no esta vigente en: ",
         paste(sprintf("%s (%s)", malos, estados), collapse = ", "),
         ".\nLa entrega esta invalidada; corrija y vuelva a validar.", call. = FALSE)
  }
  # Todas las etapas requeridas deben corresponder al parquet que se va a usar.
  actual <- huella_parquet()
  for (sc in requerir) {
    registrada <- st[[sc]]$huella_parquet
    if (!identical(actual, registrada)) {
      stop("El parquet no coincide con el registrado por ", sc, ".\n  registrado: ",
           substr(registrada, 1, 16), "\n  actual:   ", substr(actual, 1, 16),
           "\nVuelva a ejecutar las etapas requeridas.", call. = FALSE)
    }
  }
  invisible(actual)
}

# Invalida productos que ya no estan respaldados por una corrida exitosa.
invalidar_productos <- function(rutas, motivo) {
  existentes <- rutas[file.exists(rutas)]
  for (r in existentes) {
    file.rename(r, paste0(r, ".invalidado"))
  }
  if (length(existentes) > 0) {
    message("Productos invalidados (", motivo, "): ",
            paste(basename(existentes), collapse = ", "))
  }
  invisible(existentes)
}

# Exige que existan todas las tablas que un consumidor va a copiar o leer.
exigir_tablas <- function(dir, nombres) {
  faltan <- nombres[!file.exists(file.path(dir, nombres))]
  if (length(faltan) > 0) {
    stop("Faltan tablas requeridas en ", dir, ":\n  ",
         paste(faltan, collapse = "\n  "),
         "\nEjecute ./run_analisis.sh completo antes de exportar.", call. = FALSE)
  }
  invisible(nombres)
}

# Comprueba que existan todas las entradas antes de producir resultados
# parciales. Devuelve el inventario para documentarlo.
exigir_insumos <- function(rutas) {
  inv <- data.frame(ruta = unname(rutas), rol = names(rutas),
                    existe = file.exists(unname(rutas)),
                    stringsAsFactors = FALSE)
  if (any(!inv$existe)) {
    stop("Faltan insumos requeridos:\n  ",
         paste(inv$ruta[!inv$existe], collapse = "\n  "), call. = FALSE)
  }
  inv$bytes <- file.size(inv$ruta)
  inv$sha256 <- vapply(inv$ruta, sha256_archivo, character(1))
  inv
}
