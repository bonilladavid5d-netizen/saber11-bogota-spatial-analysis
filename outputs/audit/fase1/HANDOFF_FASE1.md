# Handoff — Fase 1

## Que se creo

```
R/01_reconstruir_base_geocodificada.R
R/02_validar_fase1.R
R/utils/validation_helpers.R
.gitignore
data/processed/private/saber11_bogota_sede_auditada.parquet
data/processed/private/fase1_unmatched_review.parquet
outputs/audit/fase1/
```

## Que se modifico

Ningun archivo preexistente fue modificado.

## Que permanecio intacto

`notebooks/main_report.Rmd`, `notebooks/main_report.html`, `README.md`,
`R/export_geom_shiny.R`, `R/export_lisa_units.R`, `shiny/`, `outputs/figures`,
`outputs/maps`, `outputs/models`, `outputs/tables`, `data/raw/`, `data/cleaned/`,
`data/analysis/`, `audit/` y los dos PDF de la raiz.

Los 19 insumos conservan su SHA-256 original: TRUE.

## Comandos de reproduccion

```bash
Rscript R/01_reconstruir_base_geocodificada.R
Rscript R/02_validar_fase1.R
```

Ambos desde la raiz del proyecto. Los TXT y el GPKG deben estar materializados en disco:
si estan como marcadores de iCloud, `01` se detiene con un mensaje explicito en lugar de
bloquearse en E/S.

## Dependencias

R version 4.4.0 (2024-04-24). Paquetes: .
No se instalo ningun paquete durante la ejecucion.

## Conteos finales

| concepto | valor |
|---|---|
| Archivos procesados | 18 |
| Filas nacionales con punt_global no faltante | 5,982,829 |
| Registros Bogota (codigo municipal 11001) | 791,073 |
| Registros Bogota con puntaje valido | 791,073 |
| Coincidencia exacta de sede con catalogo 2025 | 770,319 |
| Muestra principal | 770,319 |
| Pendientes de revision manual | 376 |
| Codigo valido sin match | 20,377 |
| Sin codigo de sede utilizable | 1 |
| Desacuerdos establecimiento ICFES vs catalogo | 14,114 |

## Resultado de los gates

| id_prueba | descripcion | estado |
|---|---|---|
| T01 | Hay exactamente 18 periodos unicos | PASS |
| T02 | Ningun insumo cambio durante y despues de la ejecucion | PASS |
| T03 | Los codigos DANE permanecieron como texto | PASS |
| T04 | La llave utilizada es periodo + estu_consecutivo | PASS |
| T05 | La llave no tiene faltantes ni duplicados dentro del periodo | PASS |
| T06 | El periodo interno coincide con el periodo del archivo | PASS |
| T07 | Los momentos nacionales se calcularon antes de filtrar Bogota | PASS |
| T08 | La media del z-score nacional es aproximadamente 0 por periodo | PASS |
| T09 | La desviacion del z-score nacional es aproximadamente 1 por periodo | PASS |
| T10 | La union con el catalogo no multiplica estudiantes | PASS |
| T11 | No se uso nombre, fuzzy, proximidad ni primera sede para la muestra principal | PASS |
| T12 | Los estados del cruce son exhaustivos y mutuamente excluyentes | PASS |
| T13 | La suma del embudo reconcilia con el total de Bogota | PASS |
| T14 | No existen rutas absolutas ni setwd() en los scripts nuevos | PASS |
| T15 | Raw, microdatos y bases privadas estan excluidos de Git | PASS |
| T16 | Dos ejecuciones de 01 repiten los cinco agregados incluidos en el digest (momentos, integridad, embudo, match y controles) | PASS |

Veredicto: **PASS**.

## Limitaciones

- Geografia armonizada al catalogo de sedes de 2025 aplicado a resultados 2016-2024.
  No es geocodificacion historica certificada.
- La comparacion con la base legacy es agregada por periodo y codigo de sede. El CSV
  legacy no contiene `estu_consecutivo`, de modo que **no fue posible una reconciliacion
  fila a fila** y no se produjo `legacy_comparison_rowlevel.parquet`. Esta reconstruccion
  no debe presentarse como si fuera la base original corregida registro por registro.
- `cod_upz_catalogo` y `cod_upl_catalogo` son atributos heredados del GPKG, no el
  resultado de un cruce espacial.
- No hay repositorio Git en la raiz, por decision explicita. Las pruebas relacionadas con
  Git quedan como `N/A - integracion pendiente` y no se genero `git_diff.patch`.

## Privacidad

`estu_consecutivo` y los microdatos viven unicamente en `data/processed/private/`, que
`.gitignore` excluye junto con `data/raw/`. Ninguna tabla de `outputs/audit/fase1/`
contiene identificadores individuales: los archivos 08 y 09 estan agregados por sede y
periodo, y el crosswalk 07 no incluye datos de estudiantes.

## Decisiones pendientes

Ver `DECISIONES_PENDIENTES.md`.

## Archivos para revision

```
outputs/audit/fase1/00_input_manifest.csv
outputs/audit/fase1/01_schema_periodos.csv
outputs/audit/fase1/02_integridad_llave_periodo.csv
outputs/audit/fase1/03_momentos_nacionales_periodo.csv
outputs/audit/fase1/04_calidad_dane_periodo.csv
outputs/audit/fase1/05_embudo_bogota_periodo.csv
outputs/audit/fase1/06_match_sede_periodo.csv
outputs/audit/fase1/07_crosswalk_sede_catalogo_2025.csv
outputs/audit/fase1/08_conflictos_sede_establecimiento.csv
outputs/audit/fase1/09_sin_match_agregado.csv
outputs/audit/fase1/10_legacy_vs_corregido_resumen.csv
outputs/audit/fase1/11_diccionario_base.csv
outputs/audit/fase1/12_expected_vs_observed.csv
outputs/audit/fase1/13_validacion_parquet.csv
outputs/audit/fase1/DECISIONES_PENDIENTES.md
outputs/audit/fase1/estado_validacion.json
outputs/audit/fase1/FASE1_VALIDATION_REPORT.md
outputs/audit/fase1/HANDOFF_FASE1.md
outputs/audit/fase1/run_metadata.json
outputs/audit/fase1/sessionInfo.txt
outputs/audit/fase1/VALIDATED_CLAIMS.md
outputs/audit/fase1/validation_results.csv
R/01_reconstruir_base_geocodificada.R
R/02_validar_fase1.R
R/utils/validation_helpers.R
.gitignore
```

Empaquetados en `FASE1_HANDOFF.zip`.

