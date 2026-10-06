suppressPackageStartupMessages(library(shiny))
ok <- 0; fallos <- character()
chk <- function(etq, expr) {
  r <- tryCatch({ force(expr); TRUE }, error = function(e) { fallos <<- c(fallos, paste(etq, "->", conditionMessage(e))); FALSE })
  if (r) ok <<- ok + 1
  cat(sprintf("  [%s] %s\n", if (r) "OK" else "FALLA", etq))
}

testServer("shiny_corregido", {
  session$setInputs(f_cluster = "Todos", f_upl = "Todas", f_n = 0,
                    f_conf = FALSE, f_sem = "ambas")

  n_total <- nrow(sedes_filtradas())
  chk(sprintf("filtro base devuelve todas las sedes (%d)", n_total), stopifnot(n_total == 1224))

  session$setInputs(f_cluster = "HH")
  n_hh <- nrow(sedes_filtradas())
  chk(sprintf("filtro HH devuelve %d sedes y coincide con la tabla LISA", n_hh),
      stopifnot(n_hh == 120))

  session$setInputs(f_cluster = "Todos", f_conf = TRUE)
  n_sc <- nrow(sedes_filtradas())
  chk(sprintf("excluir conflicto quita 26 sedes (%d -> %d)", n_total, n_sc),
      stopifnot(n_total - n_sc == 26))

  session$setInputs(f_conf = FALSE, f_n = 500)
  chk(sprintf("umbral de presentaciones filtra (%d sedes)", nrow(sedes_filtradas())),
      stopifnot(nrow(sedes_filtradas()) < n_total, all(sedes_filtradas()$n_examenes >= 500)))

  session$setInputs(f_n = 0, f_upl = "TEUSAQUILLO")
  chk(sprintf("filtro por UPL devuelve %d sedes", nrow(sedes_filtradas())),
      stopifnot(nrow(sedes_filtradas()) > 0))

  # Seleccion vacia: combinacion de filtros que no deja ninguna sede.
  session$setInputs(f_cluster = "HH", f_upl = "SUMAPAZ", f_n = 0, f_conf = FALSE)
  n_vacio <- nrow(sedes_filtradas())
  chk(sprintf("combinacion de filtros deja seleccion vacia (%d sedes)", n_vacio),
      stopifnot(n_vacio == 0))
  chk("resumen del mapa no falla con seleccion vacia", output$resumen_mapa)
  chk("tabla LISA no falla con seleccion vacia", output$tabla_lisa)

  session$setInputs(f_cluster = "Todos", f_upl = "Todas")
  chk("resumen del mapa renderiza", output$resumen_mapa)
  chk("tabla LISA renderiza", output$tabla_lisa)
  chk("mapa leaflet renderiza", output$mapa)

  # El mapa base no debe depender de un proveedor con clave de API.
  widget <- jsonlite::fromJSON(output$mapa)
  metodos <- unlist(widget$x$calls$method)
  urls <- paste(unlist(widget$x$calls$args), collapse = " ")
  chk("el mapa base usa teselas de OpenStreetMap, sin clave de API",
      stopifnot("addTiles" %in% metodos,
                grepl("tile.openstreetmap.org", urls, fixed = TRUE),
                !grepl("addProviderTiles", paste(metodos, collapse = " "))))
  chk("la atribucion de OpenStreetMap esta presente",
      stopifnot(grepl("openstreetmap.org/copyright", urls, fixed = TRUE)))
  chk("grafico de evolucion renderiza", output$p_evolucion)
  chk("grafico de Moran renderiza", output$p_moran)

  session$setInputs(f_sem = "1")
  chk("evolucion filtrada a primer semestre", stopifnot(nrow(evol()) == 9))
  session$setInputs(f_sem = "2")
  chk("evolucion filtrada a segundo semestre", stopifnot(nrow(evol()) == 9))
  session$setInputs(f_sem = "ambas")
  chk("evolucion con ambas aplicaciones", stopifnot(nrow(evol()) == 18))

  chk("texto del modelo renderiza", output$texto_modelo)
  chk("grafico de impactos renderiza", output$p_impactos)
  chk("tabla de modelos renderiza", output$t_modelos)
  chk("tabla de robustez renderiza", output$t_robustez)
  chk("limitaciones renderizan", output$t_limitaciones)
  chk("diagnosticos renderizan", output$t_diag)
  chk("tabla territorial renderiza", output$t_territorial)
  chk("procedencia renderiza", output$t_proc)
})

cat(sprintf("\n%d comprobaciones OK, %d fallos\n", ok, length(fallos)))
if (length(fallos)) { cat(paste(fallos, collapse = "\n"), "\n"); quit(status = 1) }
