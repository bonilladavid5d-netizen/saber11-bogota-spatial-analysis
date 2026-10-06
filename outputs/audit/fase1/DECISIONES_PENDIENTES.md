# Decisiones pendientes — Fase 1

Decision: Que hacer con los registros de Bogota sin coincidencia exacta de sede en el catalogo 2025.
Evidencia disponible: 376 registros en pending_manual_review y 20,377 registros en valid_code_not_in_catalog; el detalle por sede esta en 09_sin_match_agregado.csv.
Opciones: (a) dejarlos excluidos y documentar la perdida; (b) resolverlos manualmente sede por sede a partir de los candidatos por nombre; (c) incorporar un catalogo historico de sedes como fuente independiente.
Consecuencia de cada opcion: (a) conserva la trazabilidad y reduce cobertura; (b) recupera cobertura pero introduce criterio humano que debe quedar registrado; (c) es la unica via que permitiria hablar de geografia historica.
Recomendacion tecnica: (a) para cerrar la Fase 1, y abrir (c) como tarea propia antes de cualquier afirmacion historica.
Estado: REQUIERE DECISION DE DAVID

Decision: Como tratar los desacuerdos entre el establecimiento reportado por ICFES y el asociado a la sede en el catalogo 2025.
Evidencia disponible: 14,114 registros en 26 sedes, listados en 08_conflictos_sede_establecimiento.csv. No se corrigieron automaticamente.
Opciones: (a) conservarlos en la muestra principal marcados; (b) excluirlos de la muestra principal; (c) resolverlos caso por caso.
Consecuencia de cada opcion: (a) mantiene la cobertura y traslada el juicio a la Fase 2; (b) reduce la muestra por un desacuerdo administrativo que no afecta la ubicacion de la sede; (c) es costoso y requiere fuente externa.
Recomendacion tecnica: (a): el cruce es sede contra sede y la coordenada proviene de la sede, no del establecimiento. El conflicto es informativo, no invalidante.
Estado: REQUIERE DECISION DE DAVID

Decision: Si la Fase 2 debe recalcular UPZ y UPL desde la geometria de la sede en lugar de heredar los atributos del catalogo.
Evidencia disponible: La base conserva cod_upz_catalogo y cod_upl_catalogo como atributos del GPKG, sin cruce espacial. La auditoria preliminar reporto discrepancias entre atributo y cruce espacial en UPZ y ZAT.
Opciones: (a) heredar los atributos del catalogo; (b) recalcular por cruce espacial contra los poligonos vigentes; (c) calcular ambos y reportar la discrepancia.
Consecuencia de cada opcion: (a) es barato pero arrastra la vigencia del catalogo; (b) es coherente con la unidad espacial declarada; (c) documenta el desacuerdo sin ocultarlo.
Recomendacion tecnica: (c), y fijar la convencion temporal de las geografias antes de estimar.
Estado: REQUIERE DECISION DE DAVID

---

Archivo generado por `R/02_validar_fase1.R` en cada corrida.
Las decisiones ya tomadas estan en `docs/DECISIONES_HUMANAS.md`, que ningun script sobrescribe.

