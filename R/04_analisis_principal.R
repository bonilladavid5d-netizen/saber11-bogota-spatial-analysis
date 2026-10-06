#!/usr/bin/env Rscript

# Analisis principal del caso: concentracion espacial del rendimiento escolar en
# Bogota, estimada sobre la base corregida en la Fase 1, y sensibilidad de ese
# resultado a la calidad de la vinculacion geografica.
#
# Convenciones heredadas del proyecto original (notebooks/main_report.Rmd):
#   unidad espacial  = sede educativa
#   CRS de analisis  = EPSG:3116 (MAGNA-SIRGAS / Colombia Bogota zone)
#   matriz de pesos  = kNN k=5 estandarizada por filas
#   permutaciones    = 999
# Se conservan para que la comparacion con las cifras originales sea valida.
#
# Todo lo que se reporta es asociacion espacial, no efecto causal.
#
# Ejecutar desde la raiz del proyecto:  Rscript R/04_analisis_principal.R

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(arrow)
  library(sf)
  library(spdep)
  library(ggplot2)
})

source(file.path("R", "utils", "validation_helpers.R"))

TAB <- file.path("outputs", "portafolio", "tablas")
FIG <- file.path("outputs", "portafolio", "figuras")
dir.create(TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)

CRS_ANALISIS <- 3116
K_VECINOS    <- 5
NSIM         <- 999
set.seed(20260930)

# Puerta de entrada: el analisis no corre si los dos validadores no pasaron
# sobre exactamente este parquet. Evita que un resultado nuevo se mezcle con
# una base no validada.
HUELLA_VALIDADA <- exigir_validacion()

# Inventario completo de entradas. Se comprueba antes de producir nada, para
# no dejar resultados parciales si falta una capa.
INSUMOS_ANALISIS <- c(
  base_auditada        = file.path(RUTAS_FASE1$privado, "saber11_bogota_sede_auditada.parquet"),
  catalogo_sedes       = RUTAS_FASE1$gpkg,
  upz_poligonos        = file.path("data", "raw", "UPZ", "SHP", "IndUPZ.shp"),
  upl_poligonos        = file.path("data", "raw", "unidadplaneamientolocal",
                                   "UnidadPlaneamientoLocal.shp"),
  legacy_resumen       = file.path(RUTAS_FASE1$auditoria, "10_legacy_vs_corregido_resumen.csv"),
  embudo               = file.path(RUTAS_FASE1$auditoria, "05_embudo_bogota_periodo.csv"),
  crosswalk            = file.path(RUTAS_FASE1$auditoria, "07_crosswalk_sede_catalogo_2025.csv"),
  moran_original       = file.path("outputs", "tables", "moran_global_principal.csv"),
  lisa_original        = file.path("outputs", "tables", "tabla_resumen_lisa.csv")
)
inventario <- exigir_insumos(INSUMOS_ANALISIS)

log_etapa <- function(...) cat(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), ..., "\n", sep = "")

tema_caso <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(colour = "grey35", size = 9),
        plot.caption = element_text(colour = "grey45", size = 7.5, hjust = 0))

# ---------------------------------------------------------------------------
# 1. Muestra principal y agregacion a sede
# ---------------------------------------------------------------------------

log_etapa("Cargando muestra principal")

base <- read_parquet(file.path(RUTAS_FASE1$privado, "saber11_bogota_sede_auditada.parquet"))
mp <- base %>% filter(is_main_sample)

log_etapa("  registros en muestra principal: ", format(nrow(mp), big.mark = ","))

sede_periodo <- mp %>%
  group_by(periodo = periodo_fuente, sede = cole_cod_dane_sede_norm) %>%
  summarise(z_media = mean(z_punt_global_nacional),
            n_est = n(),
            lon = first(lon), lat = first(lat),
            cod_upz = first(cod_upz_catalogo), nombre_upz = first(nombre_upz_catalogo),
            cod_upl = first(cod_upl_catalogo), nombre_upl = first(nombre_upl_catalogo),
            .groups = "drop") %>%
  mutate(semestre = str_sub(periodo, 5, 5))

sede_pooled <- mp %>%
  group_by(sede = cole_cod_dane_sede_norm) %>%
  summarise(z_media = mean(z_punt_global_nacional),
            n_est = n(), n_periodos = n_distinct(periodo_fuente),
            lon = first(lon), lat = first(lat),
            cod_upz = first(cod_upz_catalogo), nombre_upz = first(nombre_upz_catalogo),
            cod_upl = first(cod_upl_catalogo), nombre_upl = first(nombre_upl_catalogo),
            .groups = "drop")

log_etapa("  sedes en el pooled: ", nrow(sede_pooled),
          " | sede-periodo: ", nrow(sede_periodo))

# ---------------------------------------------------------------------------
# 2. Utilidades espaciales
# ---------------------------------------------------------------------------

pesos_knn <- function(df, k = K_VECINOS) {
  pts <- st_as_sf(df, coords = c("lon", "lat"), crs = 4326) %>% st_transform(CRS_ANALISIS)
  xy <- st_coordinates(pts)
  nb <- knn2nb(knearneigh(xy, k = k))
  nb2listw(nb, style = "W")
}

moran_de <- function(df, etiqueta, variable = "z_media", k = K_VECINOS, nsim = NSIM) {
  if (nrow(df) < 30) {
    return(data.frame(etiqueta = etiqueta, n = nrow(df), I = NA_real_, E_I = NA_real_,
                      z = NA_real_, p_normal = NA_real_, p_perm = NA_real_,
                      k = k, nota = "menos de 30 unidades: no se estima",
                      stringsAsFactors = FALSE))
  }
  lw <- pesos_knn(df, k)
  x <- df[[variable]]
  mt <- moran.test(x, lw, randomisation = TRUE)
  mc <- moran.mc(x, lw, nsim = nsim)
  data.frame(etiqueta = etiqueta, n = nrow(df),
             I = unname(mt$estimate[1]), E_I = unname(mt$estimate[2]),
             z = unname(mt$statistic), p_normal = mt$p.value, p_perm = mc$p.value,
             k = k, nota = "", stringsAsFactors = FALSE)
}

clasificar_lisa <- function(df, alpha = 0.05, k = K_VECINOS) {
  lw <- pesos_knn(df, k)
  x <- df$z_media
  li <- localmoran(x, lw)
  p <- li[, ncol(li)]
  xc <- x - mean(x)
  lagc <- lag.listw(lw, x) - mean(lag.listw(lw, x))
  cluster <- ifelse(p >= alpha, "NS",
             ifelse(xc > 0 & lagc > 0, "HH",
             ifelse(xc < 0 & lagc < 0, "LL",
             ifelse(xc > 0 & lagc < 0, "HL", "LH"))))
  df %>% mutate(lisa_I = li[, 1], lisa_p = p, cluster = cluster)
}

# ---------------------------------------------------------------------------
# 3. Analisis principal: Moran global
# ---------------------------------------------------------------------------

log_etapa("Moran global, pooled y por periodo")

moran_pooled <- moran_de(sede_pooled, "pooled_2016_2024")

moran_periodo <- sede_periodo %>%
  group_split(periodo) %>%
  lapply(function(d) moran_de(d, unique(d$periodo))) %>%
  bind_rows() %>%
  rename(periodo = etiqueta) %>%
  mutate(semestre = str_sub(periodo, 5, 5),
         anio = as.integer(str_sub(periodo, 1, 4))) %>%
  left_join(sede_periodo %>% count(periodo, wt = n_est, name = "n_estudiantes"),
            by = "periodo")

write_csv(bind_rows(
  moran_pooled %>% mutate(periodo = "pooled_2016_2024", .before = 1) %>% select(-etiqueta),
  moran_periodo %>% select(-semestre, -anio, -n_estudiantes)
), file.path(TAB, "01_moran_global_periodo.csv"))

log_etapa("  pooled I = ", round(moran_pooled$I, 4),
          " (n = ", moran_pooled$n, ", p_perm = ", moran_pooled$p_perm, ")")

# ---------------------------------------------------------------------------
# 4. LISA sobre el pooled
# ---------------------------------------------------------------------------

log_etapa("LISA sobre el pooled")

lisa_sede <- clasificar_lisa(sede_pooled)

lisa_resumen <- lisa_sede %>%
  count(cluster, name = "n_sedes") %>%
  mutate(pct_sedes = pct(n_sedes, sum(n_sedes))) %>%
  left_join(lisa_sede %>% group_by(cluster) %>%
              summarise(n_estudiantes = sum(n_est),
                        z_media_cluster = round(mean(z_media), 4), .groups = "drop"),
            by = "cluster") %>%
  mutate(pct_estudiantes = pct(n_estudiantes, sum(n_estudiantes))) %>%
  arrange(desc(n_sedes))
write_csv(lisa_resumen, file.path(TAB, "02_lisa_sede_resumen.csv"))

# Agregado por UPL para la narrativa: donde se concentran los conglomerados.
lisa_upl <- lisa_sede %>%
  filter(cluster %in% c("HH", "LL")) %>%
  count(nombre_upl, cluster, name = "n_sedes") %>%
  pivot_wider(names_from = cluster, values_from = n_sedes, values_fill = 0) %>%
  arrange(desc(HH + LL))
write_csv(lisa_upl, file.path(TAB, "07_lisa_por_upl.csv"))

# ---------------------------------------------------------------------------
# 5. Comprobaciones dirigidas
# ---------------------------------------------------------------------------
# Cada una ataca un problema concreto que podria cambiar la interpretacion del
# resultado principal. No son robusteces decorativas.

log_etapa("Comprobaciones dirigidas")

robustez <- list()

robustez[["principal"]] <- moran_de(sede_pooled, "Principal: todas las sedes del pooled") %>%
  mutate(bloque = "principal", motivo = "resultado de referencia")

# --- R1 Cobertura ----------------------------------------------------------
# La muestra principal cubre 97.4% de Bogota, pero no todas las sedes aportan
# el mismo numero de examenes. Si la concentracion dependiera de sedes con
# muy pocos estudiantes, el resultado seria fragil.

for (umbral in c(10, 30, 100)) {
  d <- sede_pooled %>% filter(n_est >= umbral)
  robustez[[paste0("cobertura_n", umbral)]] <-
    moran_de(d, sprintf("Cobertura: sedes con al menos %d examenes", umbral)) %>%
    mutate(bloque = "cobertura",
           motivo = sprintf("descarta %d sedes con menos de %d examenes",
                            nrow(sede_pooled) - nrow(d), umbral))
}

# Las aplicaciones de primer semestre tienen entre 67% y 76% de filas sin
# codigo de colegio a nivel nacional (registrantes individuales), de modo que
# su submuestra bogotana es pequena y potencialmente selectiva.
for (sem in c("1", "2")) {
  d <- sede_periodo %>%
    filter(semestre == sem) %>%
    group_by(sede) %>%
    summarise(z_media = weighted.mean(z_media, n_est), n_est = sum(n_est),
              lon = first(lon), lat = first(lat), .groups = "drop")
  robustez[[paste0("semestre_", sem)]] <-
    moran_de(d, sprintf("Cobertura: solo aplicaciones de semestre %s", sem)) %>%
    mutate(bloque = "cobertura",
           motivo = sprintf("%s examenes en %d sedes", format(sum(d$n_est), big.mark = ","), nrow(d)))
}

# Universo legacy frente a sedes recuperadas por la correccion.
legacy <- read_csv(file.path(RUTAS_FASE1$auditoria, "10_legacy_vs_corregido_resumen.csv"),
                   col_types = cols(.default = col_character()), progress = FALSE)
sedes_legacy <- unique(legacy$codigo_sede[legacy$presencia_legacy == "TRUE"])

d_comun <- sede_pooled %>% filter(sede %in% sedes_legacy)
d_nuevas <- sede_pooled %>% filter(!sede %in% sedes_legacy)
robustez[["legacy_comun"]] <- moran_de(d_comun, "Cobertura: solo sedes presentes tambien en la base legacy") %>%
  mutate(bloque = "cobertura", motivo = sprintf("%d sedes", nrow(d_comun)))
robustez[["legacy_nuevas"]] <- moran_de(d_nuevas, "Cobertura: solo sedes que la base legacy no tenia") %>%
  mutate(bloque = "cobertura", motivo = sprintf("%d sedes", nrow(d_nuevas)))

# --- R2 Conflictos de establecimiento --------------------------------------
# En 14.114 registros el establecimiento que reporta el ICFES no coincide con
# el que el catalogo 2025 asocia a esa sede. No se corrigieron; aqui se mide
# si sostienen el resultado.

sedes_conflicto <- base %>%
  filter(conflicto_est_status == "conflicto_establecimiento") %>%
  distinct(sede = cole_cod_dane_sede_norm) %>%
  pull(sede)

d_sin_conf <- sede_pooled %>% filter(!sede %in% sedes_conflicto)
robustez[["sin_conflicto"]] <- moran_de(d_sin_conf, "Conflictos: excluyendo sedes con desacuerdo de establecimiento") %>%
  mutate(bloque = "conflictos",
         motivo = sprintf("descarta %d sedes en conflicto", length(sedes_conflicto)))

d_solo_conf <- sede_pooled %>% filter(sede %in% sedes_conflicto)
robustez[["solo_conflicto"]] <- moran_de(d_solo_conf, "Conflictos: solo sedes con desacuerdo de establecimiento") %>%
  mutate(bloque = "conflictos", motivo = sprintf("%d sedes", nrow(d_solo_conf)))

# --- R3 Sensibilidad a la matriz de pesos ----------------------------------
# El resultado no debe depender de k. Se reporta k = 3, 5, 8 y 10.
for (kk in c(3, 8, 10)) {
  robustez[[paste0("k", kk)]] <-
    moran_de(sede_pooled, sprintf("Pesos: kNN con k = %d", kk), k = kk) %>%
    mutate(bloque = "pesos", motivo = "misma muestra, distinto numero de vecinos")
}

tabla_robustez <- bind_rows(robustez) %>%
  select(bloque, etiqueta, motivo, n, I, p_perm, k, nota) %>%
  mutate(I = round(I, 4))
write_csv(tabla_robustez, file.path(TAB, "03_robustez_moran.csv"))

# ---------------------------------------------------------------------------
# 6. Cobertura: legacy frente a corregido
# ---------------------------------------------------------------------------

log_etapa("Cobertura legacy vs corregido")

embudo <- read_csv(file.path(RUTAS_FASE1$auditoria, "05_embudo_bogota_periodo.csv"),
                   col_types = cols(.default = col_character()), progress = FALSE)

cobertura <- legacy %>%
  mutate(conteo_legacy = as.numeric(conteo_legacy),
         conteo_corregido = as.numeric(conteo_corregido)) %>%
  group_by(periodo) %>%
  summarise(presentaciones_legacy = sum(conteo_legacy),
            presentaciones_bogota_total = sum(conteo_corregido),
            sedes_legacy = sum(presencia_legacy == "TRUE"),
            sedes_corregido = sum(presencia_corregida == "TRUE"),
            sedes_solo_legacy = sum(presencia_legacy == "TRUE" & presencia_corregida == "FALSE"),
            sedes_solo_corregido = sum(presencia_legacy == "FALSE" & presencia_corregida == "TRUE"),
            .groups = "drop") %>%
  left_join(embudo %>% transmute(periodo, bogota_total = as.numeric(bogota_total),
                                 muestra_principal = as.numeric(muestra_principal)),
            by = "periodo") %>%
  mutate(presentaciones_muestra_principal = muestra_principal,
         cobertura_legacy = pct(presentaciones_legacy, bogota_total),
         cobertura_muestra_principal = pct(muestra_principal, bogota_total),
         limitacion = "Comparacion agregada por periodo y codigo de sede; el CSV legacy no contiene estu_consecutivo.") %>%
  arrange(periodo)
write_csv(cobertura, file.path(TAB, "04_cobertura_legacy_vs_corregido.csv"))

# ---------------------------------------------------------------------------
# 7. Asignacion territorial: atributo del catalogo frente a cruce espacial
# ---------------------------------------------------------------------------

log_etapa("Asignacion territorial")

normaliza_txt <- function(x) {
  y <- toupper(trimws(as.character(x)))
  y <- iconv(y, to = "ASCII//TRANSLIT")
  y <- gsub("[^A-Z0-9]", "", y)
  y[y == ""] <- NA_character_
  y
}

sedes_sf <- st_as_sf(sede_pooled, coords = c("lon", "lat"), crs = 4326, remove = FALSE) %>%
  st_transform(CRS_ANALISIS)

upz_poly <- st_read("data/raw/UPZ/SHP/IndUPZ.shp", quiet = TRUE) %>%
  st_transform(CRS_ANALISIS) %>%
  transmute(upz_espacial_cod = as.character(CODIGO_UPZ), upz_espacial_nom = NOMBRE)

upl_poly <- st_read("data/raw/unidadplaneamientolocal/UnidadPlaneamientoLocal.shp", quiet = TRUE) %>%
  st_transform(CRS_ANALISIS) %>%
  transmute(upl_espacial_cod = str_remove(as.character(CODIGO_UPL), "^UPL"),
            upl_espacial_nom = NOMBRE)

# st_join aqui compara asignaciones territoriales para medir discrepancia.
# No asigna geografia a ningun registro de la muestra: eso ya se resolvio en la
# Fase 1 exclusivamente por codigo DANE de sede.
cruce <- sedes_sf %>%
  st_join(upz_poly, join = st_within) %>%
  st_join(upl_poly, join = st_within) %>%
  st_drop_geometry() %>%
  mutate(
    upz_coincide = case_when(
      is.na(upz_espacial_cod) ~ "sin_poligono",
      normaliza_txt(nombre_upz) == normaliza_txt(upz_espacial_nom) ~ "coincide",
      TRUE ~ "discrepa"
    ),
    upl_coincide = case_when(
      is.na(upl_espacial_cod) ~ "sin_poligono",
      normaliza_txt(nombre_upl) == normaliza_txt(upl_espacial_nom) ~ "coincide",
      TRUE ~ "discrepa"
    )
  )

discrepancia <- bind_rows(
  cruce %>% count(escala = "UPZ", estado = upz_coincide, name = "n_sedes") %>%
    left_join(cruce %>% group_by(estado = upz_coincide) %>%
                summarise(n_estudiantes = sum(n_est), .groups = "drop"), by = "estado"),
  cruce %>% count(escala = "UPL", estado = upl_coincide, name = "n_sedes") %>%
    left_join(cruce %>% group_by(estado = upl_coincide) %>%
                summarise(n_estudiantes = sum(n_est), .groups = "drop"), by = "estado")
) %>%
  group_by(escala) %>%
  mutate(pct_sedes = pct(n_sedes, sum(n_sedes)),
         pct_estudiantes = pct(n_estudiantes, sum(n_estudiantes))) %>%
  ungroup() %>%
  mutate(fuente_atributo = "COD_UPZ / COD_UPL de colegios06_2025.gpkg",
         fuente_espacial = "IndUPZ.shp (112 poligonos) / UnidadPlaneamientoLocal.shp (33 poligonos, POT 2022)")
write_csv(discrepancia, file.path(TAB, "05_discrepancia_territorial.csv"))

# Moran por escala, con el atributo del catalogo y con el cruce espacial.
agrega_escala <- function(df, col_grupo) {
  df %>%
    filter(!is.na(.data[[col_grupo]])) %>%
    group_by(grupo = .data[[col_grupo]]) %>%
    summarise(z_media = weighted.mean(z_media, n_est), n_est = sum(n_est),
              lon = mean(lon), lat = mean(lat), .groups = "drop")
}

escalas <- bind_rows(
  moran_de(sede_pooled, "sede") %>% mutate(asignacion = "codigo DANE de sede"),
  moran_de(agrega_escala(cruce, "nombre_upz"), "UPZ (atributo del catalogo)") %>%
    mutate(asignacion = "atributo heredado del catalogo 2025"),
  moran_de(agrega_escala(cruce, "upz_espacial_nom"), "UPZ (cruce espacial)") %>%
    mutate(asignacion = "cruce espacial con poligonos vigentes"),
  moran_de(agrega_escala(cruce, "nombre_upl"), "UPL (atributo del catalogo)") %>%
    mutate(asignacion = "atributo heredado del catalogo 2025"),
  moran_de(agrega_escala(cruce, "upl_espacial_nom"), "UPL (cruce espacial)") %>%
    mutate(asignacion = "cruce espacial con poligonos vigentes")
) %>%
  mutate(I = round(I, 4)) %>%
  select(escala = etiqueta, asignacion, n, I, p_perm, nota)
write_csv(escalas, file.path(TAB, "06_moran_por_escala.csv"))

# ---------------------------------------------------------------------------
# 8. Comparacion con las cifras del proyecto original
# ---------------------------------------------------------------------------

log_etapa("Comparacion con el analisis original")

orig_moran <- read_csv("outputs/tables/moran_global_principal.csv",
                       col_types = cols(.default = col_character()), progress = FALSE) %>%
  filter(escala == "sede", variable == "punt_global_z_periodo_media") %>%
  transmute(I_original = as.numeric(I), n_original = as.numeric(n))

orig_lisa <- read_csv("outputs/tables/tabla_resumen_lisa.csv",
                      col_types = cols(.default = col_character()), progress = FALSE) %>%
  filter(escala == "sede") %>%
  transmute(cluster = cluster_type, n_sedes_original = as.numeric(n))

comparacion <- bind_rows(
  data.frame(
    indicador = "Moran global I, escala sede",
    original = sprintf("%.4f", orig_moran$I_original),
    corregido = sprintf("%.4f", moran_pooled$I),
    nota = "El original estandariza dentro de la muestra bogotana; el corregido usa la referencia nacional por periodo.",
    stringsAsFactors = FALSE),
  data.frame(
    indicador = "Unidades espaciales (sedes)",
    original = format(orig_moran$n_original, big.mark = ","),
    corregido = format(nrow(sede_pooled), big.mark = ","),
    nota = "El original vinculaba por nombre a nivel de establecimiento; el corregido por codigo DANE de sede.",
    stringsAsFactors = FALSE),
  data.frame(
    indicador = "Presentaciones en el CSV legacy geolocalizado",
    original = "719,466",
    corregido = format(sum(sede_pooled$n_est), big.mark = ","),
    nota = "719.466 es el CSV legacy completo (1.149 sedes), no su muestra analitica final. La corregida es la muestra principal de la Fase 1.",
    stringsAsFactors = FALSE),
  data.frame(
    indicador = "Presentaciones en las 1.132 sedes analiticas comunes",
    original = "716,279",
    corregido = format(sum(sede_pooled$n_est[sede_pooled$sede %in% sedes_legacy]), big.mark = ","),
    nota = "Sedes presentes en ambas bases y con coordenada plausible. En ellas no hay diferencia de conteo por periodo x sede.",
    stringsAsFactors = FALSE)
) %>%
  bind_rows(
    lisa_resumen %>%
      select(cluster, n_sedes) %>%
      full_join(orig_lisa, by = "cluster") %>%
      transmute(indicador = paste("Sedes en conglomerado", cluster),
                original = format(coalesce(n_sedes_original, 0), big.mark = ","),
                corregido = format(coalesce(n_sedes, 0L), big.mark = ","),
                nota = "Clasificacion LISA con p < 0.05 y la misma W kNN k=5.")
  )
write_csv(comparacion, file.path(TAB, "08_comparacion_con_original.csv"))

# ---------------------------------------------------------------------------
# 9. Figuras
# ---------------------------------------------------------------------------

log_etapa("Figuras")

# Paleta categorica en orden fijo. El orden importa: azul -> naranja -> purpura
# -> verde mantiene toda pareja adyacente por encima de dE 16 bajo protanopia,
# deuteranopia y tritanopia. Invertir naranja y verde la rompe.
PAL_CAT <- c("#2166AC", "#B35806", "#762A83", "#1B7837")

# Paleta LISA estandar GeoDa, heredada de main_report.Rmd seccion 1.4.
LISA_PALETTE <- c(HH = "#B2182B", LL = "#2166AC", HL = "#E08214",
                  LH = "#92C5DE", NS = "#F0F0F0")

theme_caso <- theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(colour = "grey40", size = 9.5),
        plot.caption = element_text(colour = "grey50", size = 7.5, hjust = 0),
        panel.grid.minor = element_blank(),
        panel.grid.major = element_line(colour = "grey90", linewidth = 0.3),
        legend.title = element_text(size = 9.5, face = "bold"),
        legend.text = element_text(size = 9),
        plot.background = element_rect(fill = "#FAFAF9", colour = NA))

PIE <- "Fuente: ICFES Saber 11 (2016-2024), catalogo de sedes 2025 (SDP/IDECA) y elaboracion propia."

# --- F1: Moran global por periodo -----------------------------------------
f1_df <- moran_periodo %>%
  mutate(aplicacion = if_else(semestre == "1", "Primer semestre", "Segundo semestre"),
         etiqueta_periodo = factor(paste0(anio, "-", semestre))) %>%
  arrange(periodo)

f1 <- ggplot(f1_df, aes(x = etiqueta_periodo, y = I, colour = aplicacion, group = aplicacion)) +
  geom_hline(yintercept = orig_moran$I_original, linetype = "dashed",
             colour = "grey55", linewidth = 0.4) +
  annotate("text", x = "2021-1", y = orig_moran$I_original + 0.075,
           label = sprintf("Resultado original (pooled): I = %.3f", orig_moran$I_original),
           hjust = 0.5, size = 2.9, colour = "grey40") +
  geom_line(linewidth = 0.7) +
  geom_point(size = 2.4) +
  scale_colour_manual(values = PAL_CAT[1:2], name = NULL) +
  scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.08))) +
  labs(title = "Las dos aplicaciones anuales dan niveles de concentracion distintos",
       subtitle = paste("I de Moran del puntaje global estandarizado a la media nacional, escala sede, W kNN k=5.",
                        "\nSegundo semestre: 0,248 a 0,300 sobre 1.029 a 1.125 sedes. Primer semestre: 0,468 a 0,723 sobre 107 a 158 sedes."),
       x = NULL, y = "I de Moran",
       caption = paste(PIE,
                       "\nTodos los periodos con p = 0,001, el minimo alcanzable con 999 permutaciones.",
                       "\nEl grafico describe el nivel por periodo; no mide la permanencia de sedes concretas en un conglomerado.")) +
  theme_caso +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
        legend.position = "top", plot.title.position = "plot")
ggsave(file.path(FIG, "f1_moran_por_periodo.png"), f1, width = 9, height = 5, dpi = 300)

# --- F2: mapa LISA de sedes -----------------------------------------------
lisa_sf <- st_as_sf(lisa_sede, coords = c("lon", "lat"), crs = 4326) %>%
  st_transform(CRS_ANALISIS) %>%
  mutate(cluster = factor(cluster, levels = c("HH", "LL", "HL", "LH", "NS")))

etiquetas_lisa <- lisa_resumen %>%
  mutate(etq = sprintf("%s (%d)", cluster, n_sedes)) %>%
  select(cluster, etq) %>%
  tibble::deframe()

# Bogota D.C. incluye la ruralidad de Sumapaz, que ocupa la mayor parte del
# area pero casi ninguna sede. El proyecto original ya producia variantes
# "_urbano" por esta razon; se mantiene esa convencion y se declara cuantas
# sedes quedan fuera del recorte.
LAT_URBANO <- 4.45
sedes_rurales <- sum(lisa_sede$lat < LAT_URBANO)
limites_urbano <- st_bbox(
  st_transform(
    st_as_sf(lisa_sede %>% filter(lat >= LAT_URBANO),
             coords = c("lon", "lat"), crs = 4326),
    CRS_ANALISIS))

f2 <- ggplot() +
  geom_sf(data = upl_poly, fill = "white", colour = "grey70", linewidth = 0.25) +
  geom_sf(data = lisa_sf %>% filter(cluster == "NS"),
          aes(fill = cluster), shape = 21, size = 1.5, stroke = 0.15, colour = "grey75") +
  geom_sf(data = lisa_sf %>% filter(cluster != "NS"),
          aes(fill = cluster), shape = 21, size = 2.2, stroke = 0.3, colour = "white") +
  scale_fill_manual(values = LISA_PALETTE, name = "Conglomerado LISA",
                    labels = etiquetas_lisa[c("HH", "LL", "HL", "LH", "NS")]) +
  coord_sf(xlim = c(limites_urbano["xmin"] - 1500, limites_urbano["xmax"] + 1500),
           ylim = c(limites_urbano["ymin"] - 1500, limites_urbano["ymax"] + 1500),
           expand = FALSE) +
  labs(title = "Alto y bajo rendimiento ocupan zonas distintas de la ciudad",
       subtitle = sprintf("LISA sobre %s sedes, pooled 2016-2024, p < 0.05. Poligonos: 33 UPL del POT 2022",
                          format(nrow(lisa_sede), big.mark = ",")),
       caption = paste(PIE,
                       "\nHH: sede alta rodeada de sedes altas. LL: baja rodeada de bajas. HL y LH: atipicas. NS: sin significancia.",
                       sprintf("\nRecorte urbano: %d sedes de la ruralidad de Sumapaz quedan fuera del encuadre pero si entran al calculo.",
                               sedes_rurales),
                       "\nConteos exactos en outputs/portafolio/tablas/02_lisa_sede_resumen.csv")) +
  theme_caso +
  theme(axis.text = element_blank(), panel.grid.major = element_blank(),
        plot.title.position = "plot")
ggsave(file.path(FIG, "f2_lisa_sedes.png"), f2, width = 8.5, height = 7.5, dpi = 300)

# --- F3: cobertura legacy vs corregido ------------------------------------
f3_df <- cobertura %>%
  select(periodo, cobertura_legacy, cobertura_muestra_principal) %>%
  pivot_longer(-periodo, names_to = "version", values_to = "cobertura") %>%
  mutate(version = recode(version,
                          cobertura_legacy = "CSV legacy geolocalizado",
                          cobertura_muestra_principal = "Muestra principal corregida"),
         etiqueta_periodo = paste0(str_sub(periodo, 1, 4), "-", str_sub(periodo, 5, 5)))

f3 <- ggplot(f3_df, aes(x = etiqueta_periodo, y = cobertura, colour = version, group = version)) +
  geom_line(linewidth = 0.7) +
  geom_point(size = 2.2) +
  scale_colour_manual(values = PAL_CAT[1:2], name = NULL) +
  scale_y_continuous(limits = c(0, 100), labels = function(x) paste0(x, "%")) +
  labs(title = "La correccion recupera cobertura en todos los periodos",
       subtitle = "Porcentaje de registros de Bogota con sede geolocalizada, sobre el total de Bogota del periodo",
       x = NULL, y = "Cobertura",
       caption = paste(PIE,
                       "\nComparacion agregada por periodo y codigo de sede: la base original no conserva estu_consecutivo.")) +
  theme_caso +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
        legend.position = "top", plot.title.position = "plot")
ggsave(file.path(FIG, "f3_cobertura.png"), f3, width = 9, height = 5, dpi = 300)

# --- F4: comprobaciones dirigidas -----------------------------------------
f4_df <- tabla_robustez %>%
  filter(!is.na(I)) %>%
  mutate(bloque = factor(bloque, levels = c("principal", "cobertura", "conflictos", "pesos"),
                         labels = c("Principal", "Cobertura", "Conflictos", "Pesos")),
         etiqueta = factor(etiqueta, levels = rev(etiqueta)))

f4 <- ggplot(f4_df, aes(x = I, y = etiqueta, colour = bloque)) +
  geom_vline(xintercept = moran_pooled$I, linetype = "dashed",
             colour = "grey55", linewidth = 0.4) +
  geom_point(size = 2.8) +
  geom_text(aes(label = sprintf("%.3f", I)), hjust = -0.45, size = 2.9,
            colour = "grey25", show.legend = FALSE) +
  scale_colour_manual(values = PAL_CAT, name = NULL) +
  scale_x_continuous(limits = c(0, max(f4_df$I) * 1.18)) +
  labs(title = "I de Moran bajo cada variante de muestra y de vecindad",
       subtitle = sprintf(paste("Linea discontinua: resultado principal (I = %.3f).",
                                "\nLos umbrales, los conflictos y el numero de vecinos lo mueven dentro de un rango estrecho;",
                                "\ncambiar la poblacion (semestre, universo legacy) lo mueve mucho mas."),
                          moran_pooled$I),
       x = "I de Moran", y = NULL,
       caption = paste(PIE, "\nDetalle y valores p en outputs/portafolio/tablas/03_robustez_moran.csv")) +
  theme_caso +
  theme(axis.text.y = element_text(size = 8), legend.position = "top",
        plot.title.position = "plot")
ggsave(file.path(FIG, "f4_robustez.png"), f4, width = 9.5, height = 6, dpi = 300)

# ---------------------------------------------------------------------------
# 10. Resumen de hallazgos para la documentacion
# ---------------------------------------------------------------------------

resumen <- list(
  generado = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  unidad = "sede educativa",
  crs_analisis = paste0("EPSG:", CRS_ANALISIS),
  w = sprintf("kNN k=%d estandarizada por filas", K_VECINOS),
  nsim = NSIM,
  estudiantes_muestra_principal = sum(sede_pooled$n_est),
  sedes_pooled = nrow(sede_pooled),
  moran_pooled_I = round(moran_pooled$I, 4),
  moran_pooled_p_perm = moran_pooled$p_perm,
  moran_periodo_min = round(min(moran_periodo$I, na.rm = TRUE), 4),
  moran_periodo_max = round(max(moran_periodo$I, na.rm = TRUE), 4),
  moran_original_sede = round(orig_moran$I_original, 4),
  sedes_original = orig_moran$n_original,
  lisa = setNames(as.list(lisa_resumen$n_sedes), lisa_resumen$cluster),
  lisa_pct_estudiantes = setNames(as.list(lisa_resumen$pct_estudiantes), lisa_resumen$cluster),
  robustez_I_min = round(min(tabla_robustez$I, na.rm = TRUE), 4),
  robustez_I_max = round(max(tabla_robustez$I, na.rm = TRUE), 4),
  discrepancia_territorial = discrepancia %>%
    filter(estado == "discrepa") %>%
    transmute(escala, n_sedes, pct_sedes, n_estudiantes, pct_estudiantes),
  escalas = escalas
)
jsonlite::write_json(resumen, file.path("outputs", "portafolio", "resumen_hallazgos.json"),
                     auto_unbox = TRUE, pretty = TRUE)

write_csv(inventario %>% mutate(huella_parquet_validada = HUELLA_VALIDADA),
          file.path(TAB, "09_insumos_del_analisis.csv"))

log_etapa("Analisis completo. Tablas en ", TAB, " y figuras en ", FIG)
