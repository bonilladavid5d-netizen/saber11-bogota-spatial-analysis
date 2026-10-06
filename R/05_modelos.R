#!/usr/bin/env Rscript

# Modelacion econometrica espacial sobre la base corregida.
#
# Que se conserva del estudio original: la unidad (sede), el CRS de analisis
# (EPSG:3116), la familia de covariables, la estructura pooled con efectos fijos
# de ano y el Spatial Durbin Model como especificacion principal.
#
# Que se reconstruye: la variable dependiente pasa a estandarizarse contra la
# poblacion nacional del periodo, la muestra proviene del cruce exacto por
# codigo DANE de sede, y la matriz de pesos se recalcula sobre las coordenadas
# verificadas.
#
# Lo que se estima son asociaciones condicionales con estructura espacial.
# Ningun coeficiente admite lectura causal: no hay variacion exogena.
#
# Ejecutar desde la raiz del proyecto:  Rscript R/05_modelos.R

suppressPackageStartupMessages({
  library(readr); library(dplyr); library(tidyr); library(stringr)
  library(arrow); library(sf); library(spdep); library(spatialreg)
  library(Matrix); library(ggplot2)
})

source(file.path("R", "utils", "validation_helpers.R"))

HUELLA_VALIDADA <- exigir_validacion()
# Limpia un INVALIDA de una corrida anterior: esta empieza de cero.
marcar_validacion_en_curso("05_modelos")

TAB <- file.path("outputs", "portafolio", "tablas")
FIG <- file.path("outputs", "portafolio", "figuras")
MOD <- file.path("outputs", "portafolio", "modelos")
dir.create(MOD, recursive = TRUE, showWarnings = FALSE)

CRS_ANALISIS <- 3116
K_VECINOS    <- 5
R_IMPACTS    <- 1000
set.seed(20261001)

log_etapa <- function(...) cat(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), ..., "\n", sep = "")

vacio_a_na <- function(x) { x <- trimws(x); x[x == ""] <- NA_character_; x }
prop_de <- function(x, valor) mean(vacio_a_na(x) == valor, na.rm = TRUE)

# ---------------------------------------------------------------------------
# 1. Panel sede-ano
# ---------------------------------------------------------------------------

log_etapa("Construyendo panel sede-ano")

base <- read_parquet(file.path(RUTAS_FASE1$privado, "saber11_bogota_sede_auditada.parquet")) %>%
  filter(is_main_sample) %>%
  mutate(anio = as.integer(str_sub(periodo_fuente, 1, 4)))

sedes_conflicto <- base %>%
  filter(conflicto_est_status == "conflicto_establecimiento") %>%
  distinct(cole_cod_dane_sede_norm) %>% pull()

panel <- base %>%
  group_by(sede = cole_cod_dane_sede_norm, anio) %>%
  summarise(
    z_global              = mean(z_punt_global_nacional),
    n_estudiantes         = n(),
    estrato_promedio      = mean(suppressWarnings(as.integer(str_extract(fami_estratovivienda, "[0-9]"))), na.rm = TRUE),
    prop_oficial          = prop_de(cole_naturaleza, "OFICIAL"),
    prop_internet_hogar   = prop_de(fami_tieneinternet, "Si"),
    prop_jornada_completa = prop_de(cole_jornada, "COMPLETA"),
    prop_calendario_a     = prop_de(cole_calendario, "A"),
    prop_genero_femenino  = prop_de(estu_genero, "F"),
    prop_bilingue         = prop_de(cole_bilingue, "S"),
    lon = first(lon), lat = first(lat),
    .groups = "drop"
  ) %>%
  mutate(n_estudiantes_log = log(n_estudiantes),
         conflicto_est = sede %in% sedes_conflicto)

# prop_bilingue queda fuera de la especificacion principal: cole_bilingue no se
# reporta en el 20,6% de las sede-ano, y esa ausencia se concentra en sedes
# pequenas (mediana de 38 examenes frente a 57). Incluirla costaria una quinta
# parte del panel de forma no aleatoria. Se conserva como comprobacion sobre la
# submuestra donde si se observa; el equipo original ya habia explorado esa
# sensibilidad en outputs/tables/sensibilidad_pooled_sin_bilingue.csv.
COVARIABLES <- c("estrato_promedio", "prop_oficial", "prop_internet_hogar",
                 "prop_jornada_completa", "prop_calendario_a",
                 "prop_genero_femenino", "n_estudiantes_log")
COVARIABLE_OPCIONAL <- "prop_bilingue"

# Las proporciones son NaN si todas las respuestas de una sede-ano faltan.
# Se declaran como perdida y se documenta cuantas filas caen.
n_antes <- nrow(panel)
panel <- panel %>%
  mutate(across(all_of(c(COVARIABLES, COVARIABLE_OPCIONAL)),
                ~ ifelse(is.finite(.x), .x, NA_real_))) %>%
  filter(if_all(all_of(c("z_global", COVARIABLES)), ~ !is.na(.x))) %>%
  arrange(anio, sede)
log_etapa("  panel: ", nrow(panel), " obs sede-ano (", n_antes - nrow(panel),
          " descartadas por covariable faltante), ", n_distinct(panel$sede), " sedes, ",
          n_distinct(panel$anio), " anos")

write_csv(
  panel %>%
    group_by(anio) %>%
    summarise(sedes = n(), estudiantes = sum(n_estudiantes),
              across(all_of(c("z_global", COVARIABLES)), ~ round(mean(.x), 4)),
              prop_bilingue_observada = round(mean(!is.na(prop_bilingue)), 4),
              .groups = "drop"),
  file.path(TAB, "10_panel_descriptivas.csv"))

# ---------------------------------------------------------------------------
# 2. Matriz de pesos en bloques por ano
# ---------------------------------------------------------------------------
# Una sede solo tiene vecinos dentro de su propio ano: el panel es pooled, no
# una serie espacio-temporal con dependencia entre periodos.

construir_W_bloque <- function(df, k = K_VECINOS) {
  anios <- sort(unique(df$anio))
  bloques <- lapply(anios, function(y) {
    d <- df[df$anio == y, ]
    xy <- st_coordinates(st_transform(
      st_as_sf(d, coords = c("lon", "lat"), crs = 4326), CRS_ANALISIS))
    lw <- nb2listw(knn2nb(knearneigh(xy, k = k)), style = "W")
    as(listw2mat(lw), "dgCMatrix")
  })
  W <- Matrix::bdiag(bloques)
  mat2listw(W, style = "W", zero.policy = TRUE)
}

log_etapa("Matriz de pesos en bloques (k = ", K_VECINOS, ")")
lw <- construir_W_bloque(panel)

# ---------------------------------------------------------------------------
# 3. Modelos
# ---------------------------------------------------------------------------

f_base <- as.formula(paste("z_global ~", paste(COVARIABLES, collapse = " + "), "+ factor(anio)"))

# Los indicadores de ano no se rezagan: con W en bloques por ano, W %*% D_ano
# reproduce exactamente D_ano y la matriz seria singular.
f_durbin <- as.formula(paste("~", paste(COVARIABLES, collapse = " + ")))

log_etapa("Modelo de referencia: MCO")
m_ols <- lm(f_base, data = panel)

log_etapa("Pruebas de multiplicadores de Lagrange sobre los residuos de MCO")
rs <- tryCatch(spdep::lm.RStests(m_ols, lw, test = "all", zero.policy = TRUE),
               error = function(e) tryCatch(spdep::lm.LMtests(m_ols, lw, test = "all", zero.policy = TRUE),
                                            error = function(e2) NULL))

log_etapa("SAR (rezago de y)")
m_sar <- lagsarlm(f_base, data = panel, listw = lw, method = "LU", zero.policy = TRUE)

log_etapa("SEM (error espacial)")
m_sem <- errorsarlm(f_base, data = panel, listw = lw, method = "LU", zero.policy = TRUE)

log_etapa("SDM (principal)")
m_sdm <- lagsarlm(f_base, data = panel, listw = lw, Durbin = f_durbin,
                  method = "LU", zero.policy = TRUE)

log_etapa("  rho SDM = ", round(m_sdm$rho, 4), " | LL = ", round(logLik(m_sdm), 1))

saveRDS(list(ols = m_ols, sar = m_sar, sem = m_sem, sdm = m_sdm),
        file.path(MOD, "modelos_principales.rds"))

# ---------------------------------------------------------------------------
# 4. Comparacion de especificaciones
# ---------------------------------------------------------------------------

log_etapa("Comparacion de especificaciones")

# lagsarlm no siempre rellena LR1; el contraste de rho se hace con su error
# estandar asintotico.
p_rho <- function(m) {
  if (is.null(m$rho) || is.null(m$rho.se)) return(NA_real_)
  2 * stats::pnorm(-abs(unname(m$rho) / unname(m$rho.se)))
}
p_lambda <- function(m) {
  if (is.null(m$lambda) || is.null(m$lambda.se)) return(NA_real_)
  2 * stats::pnorm(-abs(unname(m$lambda) / unname(m$lambda.se)))
}

fila_modelo <- function(m, nombre, tipo) {
  data.frame(
    modelo = nombre, tipo = tipo,
    n = tryCatch(length(residuals(m)), error = function(e) NA_integer_),
    k = length(coef(m)),
    logLik = as.numeric(logLik(m)),
    AIC = AIC(m),
    rho = if (!is.null(m$rho)) round(unname(m$rho), 4) else NA_real_,
    rho_p = signif(p_rho(m), 4),
    lambda = if (!is.null(m$lambda)) round(unname(m$lambda), 4) else NA_real_,
    lambda_p = signif(p_lambda(m), 4),
    stringsAsFactors = FALSE
  )
}

comparacion <- bind_rows(
  fila_modelo(m_ols, "MCO (referencia)", "sin estructura espacial"),
  fila_modelo(m_sar, "SAR", "rezago de la dependiente"),
  fila_modelo(m_sem, "SEM", "error espacial"),
  fila_modelo(m_sdm, "SDM (principal)", "rezago de y y de las covariables")
)

if (!is.null(rs)) {
  pruebas_lm <- data.frame(
    prueba = names(rs),
    tipo = ifelse(grepl("^adj", names(rs)), "ajustada", "simple"),
    estadistico = round(vapply(rs, function(x) unname(x$statistic), numeric(1)), 3),
    p_valor = signif(vapply(rs, function(x) unname(x$p.value), numeric(1)), 4),
    stringsAsFactors = FALSE)
  pruebas_lm$lectura <- ifelse(
    pruebas_lm$tipo == "simple",
    "rechaza ausencia de estructura espacial, pero no distingue el canal",
    "contrasta un canal condicionando al otro; aqui no respaldan ambos por igual")
} else {
  pruebas_lm <- data.frame(prueba = NA_character_, estadistico = NA_real_,
                           p_valor = NA_real_,
                           nota = "no disponible en esta version de spdep")
}

write_csv(comparacion, file.path(TAB, "11_comparacion_modelos.csv"))
write_csv(pruebas_lm, file.path(TAB, "12_pruebas_lm.csv"))

# ---------------------------------------------------------------------------
# 5. Efectos directos, indirectos y totales
# ---------------------------------------------------------------------------
# En un modelo con rezago de y, los coeficientes no son efectos marginales: hay
# retroalimentacion a traves de los vecinos. Los impactos se calculan con la
# descomposicion de LeSage y Pace y errores por simulacion.

log_etapa("Impactos del SDM (R = ", R_IMPACTS, ")")

W_sparse <- as(listw2mat(lw), "dgCMatrix")
trMat <- trW(W_sparse, m = 30, type = "mult")

# El calculo de impactos no es opcional: sin el, la tabla 13 y la figura 5 de una
# corrida anterior sobrevivirian y R/06 las copiaria como actuales.
PRODUCTOS_IMPACTOS <- c(file.path(TAB, "13_impactos_sdm.csv"),
                        file.path(FIG, "f5_impactos_sdm.png"))

imp <- tryCatch(
  spatialreg::impacts(m_sdm, tr = trMat, R = R_IMPACTS),
  error = function(e) { log_etapa("  impacts fallo: ", conditionMessage(e)); NULL })

if (is.null(imp)) {
  invalidar_productos(PRODUCTOS_IMPACTOS, "impacts() del SDM fallo")
  registrar_estado_validacion("05_modelos", "INVALIDA",
                              list(motivo = "impacts() del SDM fallo"))
  stop("El calculo de impactos del SDM fallo. Sin el no hay especificacion ",
       "principal que reportar: productos invalidados y exportacion bloqueada.",
       call. = FALSE)
}

if (!is.null(imp)) {
  sm <- summary(imp, zstats = TRUE, short = TRUE)
  tabla_impactos <- data.frame(
    variable = names(imp$res$direct),
    directo = round(unname(imp$res$direct), 5),
    indirecto = round(unname(imp$res$indirect), 5),
    total = round(unname(imp$res$total), 5),
    p_directo = signif(sm$pzmat[, "Direct"], 4),
    p_indirecto = signif(sm$pzmat[, "Indirect"], 4),
    p_total = signif(sm$pzmat[, "Total"], 4),
    stringsAsFactors = FALSE)
  tabla_impactos <- tabla_impactos %>% filter(!grepl("^factor\\(anio\\)", variable))

  # Las proporciones viven en [0,1]; un coeficiente por "una unidad" seria el
  # salto de 0% a 100%. Se reporta tambien el cambio por 10 puntos
  # porcentuales, que es el multiplicador 0,1 sobre estimacion e incertidumbre.
  ES_PROPORCION <- grepl("^prop_", tabla_impactos$variable)
  tabla_impactos <- tabla_impactos %>%
    mutate(
      unidad = case_when(
        ES_PROPORCION ~ "proporcion en [0,1]",
        variable == "estrato_promedio" ~ "una unidad de estrato",
        variable == "n_estudiantes_log" ~ "un log-punto de tamano",
        TRUE ~ "una unidad"),
      escala_presentacion = ifelse(ES_PROPORCION, "por 10 puntos porcentuales", "por unidad"),
      directo_presentado = ifelse(ES_PROPORCION, round(directo * 0.1, 5), directo),
      indirecto_presentado = ifelse(ES_PROPORCION, round(indirecto * 0.1, 5), indirecto),
      total_presentado = ifelse(ES_PROPORCION, round(total * 0.1, 5), total))
  write_csv(tabla_impactos, file.path(TAB, "13_impactos_sdm.csv"))
  log_etapa("  impactos calculados para ", nrow(tabla_impactos), " covariables")
}

# Coeficientes del SDM, incluidos los rezagos de las covariables.
coefs_sdm <- as.data.frame(summary(m_sdm)$Coef)
coefs_sdm$termino <- rownames(coefs_sdm)
names(coefs_sdm)[1:4] <- c("estimador", "ee", "z", "p_valor")
write_csv(coefs_sdm %>%
            select(termino, estimador, ee, z, p_valor) %>%
            mutate(across(c(estimador, ee, z), ~ round(.x, 5)),
                   p_valor = signif(p_valor, 4)),
          file.path(TAB, "14_coeficientes_sdm.csv"))

# ---------------------------------------------------------------------------
# 6. Diagnosticos
# ---------------------------------------------------------------------------

log_etapa("Diagnosticos")

vif_manual <- function(df, vars) {
  vapply(vars, function(v) {
    f <- as.formula(paste(v, "~", paste(setdiff(vars, v), collapse = " + ")))
    1 / (1 - summary(lm(f, data = df))$r.squared)
  }, numeric(1))
}

# moran.test() trata los residuos como una variable observada y su p no es un
# contraste valido despues de estimar. Se conserva I como medida descriptiva y
# el p se deja explicitamente sin reportar. lm.morantest() seria el contraste
# apropiado para el MCO, pero este cierre es descriptivo y no lo incorpora.
moran_resid <- function(m, etiqueta) {
  mt <- moran.test(residuals(m), lw, zero.policy = TRUE, randomisation = TRUE)
  data.frame(modelo = etiqueta,
             I_residuos_descriptivo = round(unname(mt$estimate[1]), 5),
             p_valor = NA_real_,
             nota_p = "no reportado: moran.test() sobre residuos estimados no es un contraste valido post-estimacion",
             stringsAsFactors = FALSE)
}

diagnosticos <- bind_rows(
  moran_resid(m_ols, "MCO (referencia)"),
  moran_resid(m_sar, "SAR"),
  moran_resid(m_sem, "SEM"),
  moran_resid(m_sdm, "SDM (principal)")
) %>%
  left_join(comparacion %>% select(modelo, AIC, logLik), by = "modelo")

vifs <- data.frame(variable = COVARIABLES,
                   vif = round(vif_manual(panel, COVARIABLES), 3),
                   stringsAsFactors = FALSE)

intervalo_rho <- tryCatch(sprintf("(%.3f, %.3f)", m_sdm$interval[1], m_sdm$interval[2]),
                          error = function(e) "no reportado por el ajuste")
convergencia <- data.frame(
  aspecto = c("Ajuste del SDM", "rho estimado", "Intervalo admisible de rho",
              "Covariable con VIF mas alto", "Observaciones sin vecinos",
              "Observaciones y parametros"),
  valor = c(
    sprintf("log-verosimilitud %.2f, AIC %.1f", as.numeric(logLik(m_sdm)), AIC(m_sdm)),
    sprintf("%.4f (ee %.4f, p = %s)", m_sdm$rho, m_sdm$rho.se, signif(p_rho(m_sdm), 4)),
    intervalo_rho,
    sprintf("%s = %.2f", vifs$variable[which.max(vifs$vif)], max(vifs$vif)),
    as.character(sum(card(lw$neighbours) == 0)),
    sprintf("n = %d, k = %d", length(residuals(m_sdm)), length(coef(m_sdm)))
  ), stringsAsFactors = FALSE)
write_csv(convergencia, file.path(TAB, "17_convergencia_sdm.csv"))

write_csv(diagnosticos, file.path(TAB, "15_diagnosticos_modelos.csv"))
write_csv(vifs, file.path(TAB, "16_vif.csv"))

# ---------------------------------------------------------------------------
# 7. Comprobaciones dirigidas sobre el SDM
# ---------------------------------------------------------------------------
# Cada variante ataca un problema concreto de la base, no una exploracion
# generica del espacio de especificaciones.

log_etapa("Comprobaciones dirigidas sobre el SDM")

ajustar_sdm <- function(df, etiqueta, motivo, k = K_VECINOS, formula_extra = NULL) {
  cov_v <- if (is.null(formula_extra)) COVARIABLES else c(COVARIABLES, formula_extra)
  fb <- as.formula(paste("z_global ~", paste(cov_v, collapse = " + "), "+ factor(anio)"))
  fd <- as.formula(paste("~", paste(cov_v, collapse = " + ")))
  lw_v <- construir_W_bloque(df, k = k)
  m <- tryCatch(lagsarlm(fb, data = df, listw = lw_v, Durbin = fd,
                         method = "LU", zero.policy = TRUE),
                error = function(e) NULL)
  if (is.null(m)) {
    return(data.frame(variante = etiqueta, motivo = motivo, n = nrow(df),
                      sedes = n_distinct(df$sede), rho = NA_real_, rho_p = NA_real_,
                      estrato_directo = NA_real_, AIC = NA_real_,
                      nota = "el ajuste no convergio", stringsAsFactors = FALSE))
  }
  tr_v <- trW(as(listw2mat(lw_v), "dgCMatrix"), m = 30, type = "mult")
  im <- tryCatch(spatialreg::impacts(m, tr = tr_v, R = 200), error = function(e) NULL)
  se_ok <- !is.null(m$rho.se) && is.finite(m$rho.se)
  data.frame(
    variante = etiqueta, motivo = motivo, n = nrow(df), sedes = n_distinct(df$sede),
    rho = round(unname(m$rho), 4), rho_p = if (se_ok) signif(p_rho(m), 4) else NA_real_,
    estrato_directo = if (!is.null(im)) round(unname(im$res$direct["estrato_promedio"]), 5) else NA_real_,
    AIC = round(AIC(m), 1),
    nota = if (se_ok) "" else "el Hessiano de diferencias finitas no devuelve error estandar de rho en esta submuestra; el coeficiente se reporta sin contraste",
    stringsAsFactors = FALSE)
}

variantes <- bind_rows(
  ajustar_sdm(panel, "Principal", "especificacion de referencia"),
  ajustar_sdm(panel %>% filter(!conflicto_est),
              "Sin sedes en conflicto de establecimiento",
              sprintf("descarta %d sedes con desacuerdo ICFES vs catalogo", length(sedes_conflicto))),
  ajustar_sdm(panel %>% filter(n_estudiantes >= 30),
              "Sedes con al menos 30 examenes al ano", "descarta sede-ano con poca masa"),
  ajustar_sdm(panel, "Pesos kNN k = 3", "sensibilidad a la definicion de vecindad", k = 3),
  ajustar_sdm(panel, "Pesos kNN k = 8", "sensibilidad a la definicion de vecindad", k = 8),
  ajustar_sdm(panel %>% filter(!is.na(prop_bilingue)),
              "Incluyendo prop_bilingue",
              "submuestra donde cole_bilingue si se reporta",
              formula_extra = COVARIABLE_OPCIONAL)
)
write_csv(variantes, file.path(TAB, "18_robustez_sdm.csv"))

# ---------------------------------------------------------------------------
# 8. Figuras
# ---------------------------------------------------------------------------

log_etapa("Figuras de modelos")

PAL_CAT <- c("#2166AC", "#B35806", "#762A83", "#1B7837")
theme_caso <- theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(colour = "grey40", size = 9.5),
        plot.caption = element_text(colour = "grey50", size = 7.5, hjust = 0),
        panel.grid.minor = element_blank(),
        panel.grid.major = element_line(colour = "grey90", linewidth = 0.3),
        legend.title = element_text(size = 9.5, face = "bold"),
        legend.text = element_text(size = 9),
        plot.title.position = "plot",
        plot.background = element_rect(fill = "#FAFAF9", colour = NA))
PIE <- "Fuente: ICFES Saber 11 (2016-2024), catalogo de sedes 2025 (SDP/IDECA) y elaboracion propia."

etiquetas_cov <- c(
  estrato_promedio = "Estrato promedio del hogar",
  prop_oficial = "Proporcion de colegio oficial",
  prop_internet_hogar = "Proporcion con internet en casa",
  prop_jornada_completa = "Proporcion en jornada completa",
  prop_calendario_a = "Proporcion en calendario A",
  prop_genero_femenino = "Proporcion de mujeres",
  n_estudiantes_log = "Tamano de la sede (log)")

if (!is.null(tabla_impactos)) {
  f5_df <- tabla_impactos %>%
    filter(variable %in% names(etiquetas_cov)) %>%
    select(variable, escala_presentacion,
           directo = directo_presentado, indirecto = indirecto_presentado,
           total = total_presentado) %>%
    pivot_longer(c(directo, indirecto, total), names_to = "efecto", values_to = "valor") %>%
    left_join(tabla_impactos %>%
                select(variable, p_directo, p_indirecto, p_total) %>%
                pivot_longer(-variable, names_to = "efecto", values_to = "p") %>%
                mutate(efecto = str_remove(efecto, "^p_")),
              by = c("variable", "efecto")) %>%
    mutate(etiqueta = paste0(unname(etiquetas_cov[variable]),
                            ifelse(escala_presentacion == "por 10 puntos porcentuales",
                                   " (+10 p.p.)", "")),
           efecto = factor(efecto, levels = c("directo", "indirecto", "total"),
                           labels = c("Directo", "Indirecto", "Total")),
           significativo = p < 0.05)

  f5 <- ggplot(f5_df, aes(x = valor, y = reorder(etiqueta, valor), colour = efecto,
                          shape = significativo)) +
    geom_vline(xintercept = 0, colour = "grey55", linewidth = 0.4) +
    geom_point(size = 2.6, position = position_dodge(width = 0.6)) +
    scale_colour_manual(values = PAL_CAT[1:3], name = NULL) +
    scale_shape_manual(values = c(`TRUE` = 16, `FALSE` = 1),
                       labels = c(`TRUE` = "p < 0,05", `FALSE` = "no significativo"),
                       name = NULL) +
    labs(title = "Efectos directos, indirectos y totales del SDM",
         subtitle = sprintf("Descomposicion de LeSage y Pace, %d simulaciones. Variable dependiente: z nacional del puntaje global", R_IMPACTS),
         x = "Cambio en desviaciones nacionales", y = NULL,
         caption = paste(PIE,
                         "\nProporciones: +10 puntos porcentuales. Estrato: +1 unidad. Tamano: +1 log-punto.",
                         "\nAsociaciones condicionales, no efectos causales: no hay variacion exogena en las covariables.",
                         "\nSignificancia nominal bajo el modelo pooled; sin correccion por dependencia temporal dentro de sede.",
                         "\nValores en outputs/portafolio/tablas/13_impactos_sdm.csv")) +
    theme_caso + theme(legend.position = "top")
  ggsave(file.path(FIG, "f5_impactos_sdm.png"), f5, width = 9.5, height = 5.5, dpi = 300)
}

f6_df <- diagnosticos %>%
  mutate(modelo = factor(modelo, levels = rev(c("MCO (referencia)", "SAR", "SEM", "SDM (principal)"))))

f6 <- ggplot(f6_df, aes(x = I_residuos_descriptivo, y = modelo)) +
  geom_vline(xintercept = 0, colour = "grey55", linewidth = 0.4) +
  geom_segment(aes(x = 0, xend = I_residuos_descriptivo, yend = modelo),
               colour = "grey75", linewidth = 0.5) +
  geom_point(size = 3, colour = PAL_CAT[1]) +
  geom_text(aes(label = sprintf("%.4f", I_residuos_descriptivo),
                hjust = ifelse(I_residuos_descriptivo < 0, 1.25, -0.3)),
            size = 3, colour = "grey25") +
  scale_x_continuous(expand = expansion(mult = c(0.18, 0.18))) +
  labs(title = "Autocorrelacion residual: magnitud descriptiva por especificacion",
       subtitle = "I de Moran de los residuos sobre la misma W en bloques por ano. Sin contraste de hipotesis",
       x = "I de Moran de los residuos (descriptivo)", y = NULL,
       caption = paste(PIE,
                       "\nEl p de moran.test() sobre residuos estimados no es un contraste valido post-estimacion y no se reporta.",
                       "\nLa comparacion entre especificaciones se apoya en el AIC sobre las mismas 10.228 observaciones.")) +
  theme_caso
ggsave(file.path(FIG, "f6_moran_residuos.png"), f6, width = 8.5, height = 4.2, dpi = 300)

# ---------------------------------------------------------------------------
# 9. Resumen
# ---------------------------------------------------------------------------

resumen_modelos <- list(
  generado = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  huella_parquet_validada = HUELLA_VALIDADA,
  panel = list(observaciones = nrow(panel), sedes = n_distinct(panel$sede),
               anios = n_distinct(panel$anio),
               examenes = sum(panel$n_estudiantes)),
  especificacion_principal = "SDM pooled sede-ano, W kNN k=5 en bloques por ano, efectos fijos de ano",
  covariables = COVARIABLES,
  covariable_excluida = list(variable = COVARIABLE_OPCIONAL,
                             motivo = "no reportada en 20,6% de las sede-ano"),
  rho = round(unname(m_sdm$rho), 4),
  rho_p = signif(p_rho(m_sdm), 4),
  AIC = round(sapply(list(MCO = m_ols, SAR = m_sar, SEM = m_sem, SDM = m_sdm), AIC), 1),
  moran_residuos_descriptivo = setNames(diagnosticos$I_residuos_descriptivo, diagnosticos$modelo),
  nota_moran_residuos = "I descriptivo; el p de moran.test() sobre residuos estimados no se reporta",
  nota_inferencia = paste("Los errores estandar y p se interpretan bajo los supuestos de la",
                          "especificacion pooled. No se aplico una correccion especifica por",
                          "dependencia temporal entre observaciones de una misma sede; las",
                          "simulaciones de impactos propagan la covarianza del modelo ajustado."),
  impactos = if (!is.null(tabla_impactos)) tabla_impactos else "no calculados",
  robustez = variantes %>% select(variante, n, sedes, rho, estrato_directo, AIC)
)
# digits = NA conserva la precision completa: con el valor por defecto un p de
# 2,6e-5 se serializa como 0.
jsonlite::write_json(resumen_modelos, file.path("outputs", "portafolio", "resumen_modelos.json"),
                     auto_unbox = TRUE, pretty = TRUE, digits = NA)

registrar_estado_validacion("05_modelos", "VALIDA",
                            list(huella_parquet = HUELLA_VALIDADA,
                                 impactos = nrow(tabla_impactos)))

log_etapa("Modelos completos. Tablas 10-18 en ", TAB)
