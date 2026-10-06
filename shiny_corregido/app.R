# App de resultados corregidos — Saber 11 Bogota.
#
# Reutiliza la estructura y los creditos de la app original del equipo
# (shiny/app.R), que se conserva intacta. Esta version consume unicamente los
# agregados de la base reconstruida y validada en la Fase 1.
#
# Ejecutar desde la raiz del proyecto:
#   Rscript R/06_exportar_shiny.R      # genera shiny_corregido/data/
#   R -e 'shiny::runApp("shiny_corregido")'

library(shiny)
library(bslib)
library(leaflet)
library(sf)
library(ggplot2)
library(dplyr)
library(tidyr)
library(readr)
library(jsonlite)

source(file.path("R", "carga.R"))

DATA <- cargar_datos()

tabla_simple <- function(df, digitos = 4) {
  if (is.null(df)) return(data.frame(aviso = "tabla no disponible"))
  as.data.frame(df)
}

ui <- page_navbar(
  title = tags$div(tags$strong("Saber 11 Bogota"),
                   tags$span(" · resultados corregidos",
                             style = "font-size:.85em; opacity:.8;")),
  theme = bs_theme(version = 5, bootswatch = "minty"),
  # Ninguna pestaña llena el alto de la ventana: todas crecen con su contenido y
  # la pagina se desplaza. Con `fillable` activo (el valor por defecto de
  # bslib) el contenedor repartia el alto disponible entre el banner, los
  # filtros, el mapa y la tabla; a 1014x719 el mapa quedaba en una franja de
  # unos 46 px y el `height` del leafletOutput no se respetaba.
  fillable = FALSE,

  header = tags$div(
    class = "container-fluid py-2 border-bottom",
    style = "background:#f8f9fa;",
    tags$h5("Concentracion espacial del rendimiento escolar en Bogota",
            class = "mb-1 fw-bold"),
    tags$p(class = "text-muted mb-1", style = "font-size:.9em;",
           sprintf("%s sedes · %s presentaciones · %s periodos · catalogo de sedes %s",
                   format(DATA$meta$sedes, big.mark = "."),
                   format(DATA$meta$examenes, big.mark = "."),
                   DATA$meta$periodos, DATA$meta$catalog_vintage)),
    tags$p(class = "mb-0", style = "font-size:.82em; color:#555;",
           "Proyecto original: David Bonilla · David Olaya · Esteban Labastidas",
           tags$sup("†"), " · Laura Pinzon · Leandro Castellanos · Luisa Perdomo",
           tags$span(" | ", style = "color:#aaa;"),
           tags$em("Maestria en Economia Aplicada · Universidad de los Andes")),
    tags$p(class = "mb-0 mt-1", style = "font-size:.8em; color:#8a6d3b;",
           tags$strong("Asociaciones, no efectos causales."),
           " Geografia armonizada al catalogo de 2025; no es geocodificacion historica.")
  ),

  nav_panel(
    "Mapa de conglomerados",
    layout_sidebar(
      fillable = FALSE,
      sidebar = sidebar(
        width = 300,
        selectInput("f_cluster", "Conglomerado LISA",
                    choices = c("Todos", names(LISA_ETIQUETAS)), selected = "Todos"),
        selectInput("f_upl", "Unidad de Planeamiento Local",
                    choices = c("Todas", sort(unique(na.omit(DATA$sedes$nombre_upl))))),
        sliderInput("f_n", "Minimo de presentaciones por sede",
                    min = 0, max = 2000, value = 0, step = 50),
        checkboxInput("f_conf", "Excluir sedes con conflicto de establecimiento", FALSE),
        hr(),
        htmlOutput("resumen_mapa")
      ),
      # Sin boton de ampliacion: entrar y salir de pantalla completa redimensiona
      # el contenedor, y Leaflet conserva el tamano que cacheo al inicializarse
      # salvo que se le invoque invalidateSize(). Esa es la via por la que las
      # fichas quedaban cortadas y el mapa podia desaparecer al refiltrar. Con
      # una vista fija de 500 px y pagina desplazable el boton no hace falta.
      card(fill = FALSE, card_header("Sedes por conglomerado"),
           leafletOutput("mapa", height = "500px")),
      card(fill = FALSE, card_header("Conteos de la clasificacion"),
           div(style = "overflow-x: auto; width: 100%;", tableOutput("tabla_lisa")))
    )
  ),

  nav_panel(
    "Evolucion del desempeno",
    layout_sidebar(
      sidebar = sidebar(
        width = 300,
        radioButtons("f_sem", "Aplicacion",
                     choices = c("Ambas" = "ambas", "Primer semestre" = "1",
                                 "Segundo semestre" = "2"), selected = "ambas"),
        helpText("Las dos aplicaciones anuales reunen poblaciones distintas: ",
                 "el primer semestre agrupa entre 107 y 158 sedes, el segundo mas de mil.")
      ),
      card(fill = FALSE, card_header("Posicion de Bogota frente a la media nacional"),
           plotOutput("p_evolucion", height = "360px")),
      card(fill = FALSE, card_header("Concentracion espacial por periodo (I de Moran)"),
           plotOutput("p_moran", height = "360px"))
    )
  ),

  nav_panel(
    "Resultados del modelo",
    layout_sidebar(
      sidebar = sidebar(
        width = 330,
        htmlOutput("texto_modelo")
      ),
      card(fill = FALSE, card_header("Efectos directos, indirectos y totales del SDM"),
           plotOutput("p_impactos", height = "460px")),
      card(card_header("Comparacion de especificaciones"),
           div(style = "overflow-x: auto; width: 100%;", tableOutput("t_modelos"))),
      card(card_header("Comprobaciones dirigidas sobre el SDM"),
           div(style = "overflow-x: auto; width: 100%;", tableOutput("t_robustez")))
    )
  ),

  nav_panel(
    "Validacion y limitaciones",
    card(fill = FALSE, card_header("Limitaciones vigentes"), htmlOutput("t_limitaciones")),
    card(fill = FALSE, card_header("Autocorrelacion residual por especificacion"),
         div(style = "overflow-x: auto; width: 100%;", tableOutput("t_diag")),
         tags$p(class = "text-muted mb-0", style = "font-size:.85em;",
                "Magnitud descriptiva. El p de moran.test() sobre residuos estimados no es ",
                "un contraste valido post-estimacion y no se reporta. La comparacion entre ",
                "especificaciones se apoya en el AIC sobre las mismas 10.228 observaciones.")),
    card(fill = FALSE, card_header("Discrepancia de asignacion territorial"),
         div(style = "overflow-x: auto; width: 100%;", tableOutput("t_territorial"))),
    card(fill = FALSE, card_header("Procedencia"), htmlOutput("t_proc"))
  )
)

server <- function(input, output, session) {

  sedes_filtradas <- reactive({
    d <- DATA$sedes
    if (input$f_cluster != "Todos") d <- d[d$cluster == input$f_cluster, ]
    if (input$f_upl != "Todas") d <- d[!is.na(d$nombre_upl) & d$nombre_upl == input$f_upl, ]
    d <- d[d$n_examenes >= input$f_n, ]
    if (isTRUE(input$f_conf)) d <- d[!d$conflicto_est, ]
    d
  })

  output$resumen_mapa <- renderUI({
    d <- sedes_filtradas()
    HTML(sprintf(
      "<b>%s</b> sedes seleccionadas<br><b>%s</b> presentaciones<br>%s con media suprimida",
      format(nrow(d), big.mark = "."),
      format(sum(d$n_examenes), big.mark = "."),
      sum(is.na(d$z_publicado))))
  })

  # leaflet.providers 3.0.0 enruta las teselas de CartoDB por un servicio que
  # exige clave y devuelve mosaicos "API KEY REQUIRED". Se usan las teselas
  # estandar de OpenStreetMap, de uso libre, con su atribucion explicita como
  # exige su licencia.
  output$mapa <- renderLeaflet({
    leaflet(options = leafletOptions(minZoom = 9, maxZoom = 17)) %>%
      addTiles(
        urlTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        attribution = paste0("&copy; <a href='https://www.openstreetmap.org/copyright'>",
                             "OpenStreetMap</a> contributors"),
        options = tileOptions(maxZoom = 17)
      ) %>%
      addPolygons(data = DATA$upl, fill = FALSE, color = "#888", weight = 1) %>%
      setView(lng = -74.09, lat = 4.63, zoom = 11)
  })

  observe({
    d <- sedes_filtradas()
    pal <- colorFactor(LISA_COLORES, levels = names(LISA_COLORES))
    prox <- leafletProxy("mapa") %>% clearMarkers() %>% clearControls()
    if (nrow(d) == 0) return(prox)
    prox %>%
      addCircleMarkers(
        data = d, radius = 4, stroke = TRUE, weight = 0.8, color = "white",
        fillColor = ~pal(cluster), fillOpacity = 0.9,
        # autoPan desplaza el mapa para que la ficha completa quede visible.
        # El margen inferior derecho reserva el espacio de la leyenda, que antes
        # tapaba la ultima linea del popup.
        popupOptions = popupOptions(autoPan = TRUE, keepInView = TRUE,
                                    maxWidth = 300, maxHeight = 260,
                                    autoPanPaddingTopLeft = c(20, 20),
                                    autoPanPaddingBottomRight = c(240, 210)),
        popup = ~sprintf(
          "<b>%s</b><br>%s<br>UPL: %s<br>Presentaciones: %s<br>z medio: %s<br>Conglomerado: %s (p = %s)%s",
          ifelse(is.na(nombre_sede), "(sin nombre)", nombre_sede),
          ifelse(is.na(nombre_est), "", nombre_est),
          ifelse(is.na(nombre_upl), "sin asignar", nombre_upl),
          format(n_examenes, big.mark = "."),
          ifelse(is.na(z_publicado), "no divulgado (menos de 10 presentaciones)",
                 format(z_publicado)),
          LISA_ETIQUETAS[cluster], format(lisa_p),
          ifelse(conflicto_est, "<br><i>Conflicto de establecimiento ICFES vs catalogo</i>", ""))) %>%
      addLegend("bottomright", colors = unname(LISA_COLORES),
                labels = unname(LISA_ETIQUETAS), opacity = 0.9,
                title = "Conglomerado LISA")
  })

  output$tabla_lisa <- renderTable({
    d <- sedes_filtradas()
    st_drop_geometry(d) %>%
      count(cluster, name = "sedes") %>%
      mutate(descripcion = unname(LISA_ETIQUETAS[cluster]),
             pct = round(100 * sedes / sum(sedes), 2)) %>%
      arrange(desc(sedes)) %>%
      select(Conglomerado = cluster, Descripcion = descripcion,
             Sedes = sedes, `% del filtro` = pct)
  }, digits = 2)

  evol <- reactive({
    d <- DATA$evol_total
    if (input$f_sem != "ambas") d <- d[substr(d$periodo, 5, 5) == input$f_sem, ]
    d
  })

  output$p_evolucion <- renderPlot({
    d <- evol()
    ggplot(d, aes(x = etiqueta, y = z_medio, group = 1)) +
      geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
      geom_line(colour = PAL_CAT[1], linewidth = 0.8) +
      geom_point(colour = PAL_CAT[1], size = 2.6) +
      labs(title = "Bogota frente a la media nacional del periodo",
           subtitle = "Media del puntaje global estandarizado contra la poblacion nacional. Cero = media del pais",
           x = NULL, y = "Desviaciones nacionales") +
      tema_app() + theme(axis.text.x = element_text(angle = 45, hjust = 1))
  })

  output$p_moran <- renderPlot({
    d <- DATA$moran %>% filter(periodo != "pooled_2016_2024") %>%
      mutate(etiqueta = paste0(substr(periodo, 1, 4), "-", substr(periodo, 5, 5)),
             aplicacion = ifelse(substr(periodo, 5, 5) == "1", "Primer semestre", "Segundo semestre"))
    if (input$f_sem != "ambas") d <- d[substr(d$periodo, 5, 5) == input$f_sem, ]
    ggplot(d, aes(x = etiqueta, y = I, colour = aplicacion, group = aplicacion)) +
      geom_line(linewidth = 0.8) + geom_point(size = 2.6) +
      scale_colour_manual(values = PAL_CAT[1:2]) +
      scale_y_continuous(limits = c(0, NA)) +
      labs(title = "I de Moran por periodo, escala sede",
           subtitle = "W kNN k=5. Todos los periodos con p = 0,001 (999 permutaciones, minimo alcanzable)",
           x = NULL, y = "I de Moran") +
      tema_app() + theme(axis.text.x = element_text(angle = 45, hjust = 1))
  })

  output$texto_modelo <- renderUI({
    m <- DATA$modelos
    HTML(paste0(
      "<p><b>Especificacion principal:</b> Spatial Durbin Model sobre un panel pooled ",
      "sede-ano, con efectos fijos de ano y matriz de pesos kNN k=5 en bloques por ano.</p>",
      "<p>Se eligio por tener el AIC mas bajo de las cuatro especificaciones sobre las ",
      "mismas 10.228 observaciones. El I de Moran residual se presenta como medida ",
      "descriptiva, sin valores p ni una conclusion de independencia de los residuos.</p>",
      "<p><b>Como leer los efectos:</b> en un modelo con rezago de la dependiente los ",
      "coeficientes no son efectos marginales. El <i>directo</i> recoge el cambio en la ",
      "propia sede, el <i>indirecto</i> el que pasa por las sedes vecinas, y el ",
      "<i>total</i> su suma.</p>",
      "<p>Las proporciones viven entre 0 y 1: sus efectos se presentan por un aumento ",
      "de <b>10 puntos porcentuales</b>. El estrato se presenta por una unidad y el tamano ",
      "en escala logaritmica. Los efectos indirectos incluyen la propagacion de la matriz ",
      "de pesos, no solo los vecinos inmediatos.</p>",
      "<p style='color:#8a6d3b'><b>Son asociaciones condicionales entre agregados ",
      "sede-ano.</b> No hay variacion exogena en las covariables: nada aqui identifica un ",
      "efecto causal.</p>",
      "<p style='font-size:.9em; color:#666'>Los errores estandar y p se interpretan bajo ",
      "los supuestos de la especificacion pooled. No se aplico una correccion especifica ",
      "por dependencia temporal entre observaciones de una misma sede; las simulaciones de ",
      "impactos propagan la covarianza del modelo ajustado.</p>"))
  })

  output$p_impactos <- renderPlot({
    d <- DATA$impactos %>%
      filter(variable %in% names(ETIQUETAS_COV)) %>%
      select(variable, escala_presentacion,
             directo = directo_presentado, indirecto = indirecto_presentado,
             total = total_presentado, p_directo, p_indirecto, p_total) %>%
      pivot_longer(c(directo, indirecto, total), names_to = "efecto", values_to = "valor") %>%
      left_join(DATA$impactos %>%
                  select(variable, p_directo, p_indirecto, p_total) %>%
                  pivot_longer(-variable, names_to = "efecto", values_to = "p") %>%
                  mutate(efecto = sub("^p_", "", efecto)),
                by = c("variable", "efecto")) %>%
      mutate(etiqueta = paste0(unname(ETIQUETAS_COV[variable]),
                               ifelse(escala_presentacion == "por 10 puntos porcentuales",
                                      " (+10 p.p.)", "")),
             efecto = factor(efecto, levels = c("directo", "indirecto", "total"),
                             labels = c("Directo", "Indirecto", "Total")),
             sig = p < 0.05)
    ggplot(d, aes(x = valor, y = reorder(etiqueta, valor), colour = efecto, shape = sig)) +
      geom_vline(xintercept = 0, colour = "grey55", linewidth = 0.4) +
      geom_point(size = 3, position = position_dodge(width = 0.6)) +
      scale_colour_manual(values = PAL_CAT[1:3]) +
      scale_shape_manual(values = c(`TRUE` = 16, `FALSE` = 1),
                         labels = c(`TRUE` = "p < 0,05", `FALSE` = "no significativo")) +
      labs(x = "Cambio en desviaciones nacionales", y = NULL,
           caption = "Proporciones: por 10 puntos porcentuales. Estrato: por unidad. Tamano: por log-punto.") +
      tema_app()
  })

  output$t_modelos <- renderTable({
    DATA$modelos %>%
      transmute(Modelo = modelo, Tipo = tipo, n = n, k = k,
                `log-verosimilitud` = round(logLik, 1), AIC = round(AIC, 1),
                rho = rho, `p de rho` = rho_p, lambda = lambda)
  }, digits = 4, na = "")

  output$t_robustez <- renderTable({
    DATA$robustez_sdm %>%
      transmute(Variante = variante, Motivo = motivo, n = n, Sedes = sedes,
                rho = rho, `p de rho` = rho_p,
                `Efecto directo del estrato` = estrato_directo, AIC = AIC,
                Nota = ifelse(is.na(nota), "", nota))
  }, digits = 4, na = "")

  output$t_limitaciones <- renderUI({
    HTML(paste0("<ul>", paste0("<li>", DATA$meta$limitaciones, "</li>", collapse = ""), "</ul>"))
  })

  output$t_diag <- renderTable({
    DATA$diagnosticos %>%
      transmute(Modelo = modelo,
                `I de Moran de los residuos (descriptivo)` = I_residuos_descriptivo,
                AIC = round(AIC, 1))
  }, digits = 5)

  output$t_territorial <- renderTable({
    DATA$territorial %>%
      transmute(Escala = escala, Estado = estado, Sedes = n_sedes,
                `% de sedes` = pct_sedes, Presentaciones = n_estudiantes,
                `% de presentaciones` = pct_estudiantes)
  }, digits = 2)

  output$t_proc <- renderUI({
    HTML(sprintf(
      paste0("<p>Agregados generados el %s desde la base validada ",
             "(huella <code>%s</code>).</p>",
             "<p>La app no contiene microdatos. La unidad de los conteos es la ",
             "presentacion del examen, no la persona.</p>",
             "<p>La app original del equipo se conserva sin modificar en <code>shiny/</code>.</p>"),
      DATA$meta$generado, DATA$meta$huella_parquet_validada))
  })
}

shinyApp(ui, server)
