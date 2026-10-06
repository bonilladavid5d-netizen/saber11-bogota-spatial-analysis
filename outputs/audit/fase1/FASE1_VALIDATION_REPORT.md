# Fase 1 — Reporte de validacion

Corrida: 2026-10-05 22:59:41. Duracion: 3.14 minutos.

## Objetivo

Reconstruir desde los TXT originales del ICFES una base de resultados Saber 11 para
colegios ubicados en Bogota cuya procedencia, poblacion, llave, estandarizacion del
puntaje y vinculacion con sedes puedan auditarse y reproducirse.

## Contrato de datos

- Insumos: 19 archivos, con SHA-256 registrado antes y despues de la corrida (`00_input_manifest.csv`).
- Insumos intactos al cerrar: TRUE.
- Codigos DANE leidos y conservados como texto. Sin `as.integer`, sin relleno de ceros.
- Se conserva version original y normalizada de cada codigo.

## Unidad de observacion

Una presentacion del examen: `periodo + estu_consecutivo`. `estu_consecutivo` identifica
una presentacion, no una persona seguida en el tiempo.

## Definicion de la muestra

- Universo Bogota: 791,073 registros de colegios con `cole_cod_mcpio_ubicacion == "11001"`.
- Con puntaje global valido en [0,500]: 791,073.
- Con coincidencia exacta de sede en el catalogo 2025: 770,319.
- Muestra principal (`is_main_sample`): 770,319 (97.38% de Bogota).

## Regla de Bogota

`cole_cod_mcpio_ubicacion == "11001"`, sobre la ubicacion del colegio, no sobre la
residencia ni el municipio de presentacion del estudiante. Las reglas alternativas por
codigo de departamento y por texto se calcularon en paralelo y sus discrepancias estan
en `05_embudo_bogota_periodo.csv`.

## Formula del z-score

```
z_punt_global_nacional = (punt_global - media_nacional_periodo) / sd_nacional_periodo
```

Media y desviacion se calculan por periodo sobre la poblacion nacional elegible
(`punt_global` numerico y dentro de [0,500]), antes de cualquier filtro territorial.
La desviacion es muestral (n-1).

## Estrategia de vinculacion

`cole_cod_dane_sede` contra `DANE12_SED` del catalogo 2025, texto contra texto, igualdad
exacta. La union es many-to-one y esta garantizada por la unicidad de `DANE12_SED`.
Los nombres solo generan candidatos de revision manual; no asignan coordenadas ni
modifican `match_method`.

El catalogo declara `WGS 84 / Pseudo-Mercator` pero almacena grados (lon [-74.3933, -74.0162] lat [3.8295, 4.8239] sobre 2219 de 2221 filas con coordenada finita). Se corrige la etiqueta con
`st_set_crs(4326)`; no se reproyecta y no se modifica el archivo en disco.

## Resultados de las pruebas

| id_prueba | descripcion | valor_observado | estado |
|---|---|---|---|
| T01 | Hay exactamente 18 periodos unicos | 18 | PASS |
| T02 | Ningun insumo cambio durante y despues de la ejecucion | 19/19 SHA-256 identicos | PASS |
| T03 | Los codigos DANE permanecieron como texto | cole_cod_dane_sede_orig=character; cole_cod_dane_sede_norm=character; cole_cod_dane_establecimiento_orig=character; cole_cod_dane_establecimiento_norm=character; dane12_sed_catalogo=character; dane12_est_catalogo=character | PASS |
| T04 | La llave utilizada es periodo + estu_consecutivo | periodo + estu_consecutivo | PASS |
| T05 | La llave no tiene faltantes ni duplicados dentro del periodo | base: 0 faltantes, 0 duplicados | archivos: 0 faltantes, 0 duplicados | PASS |
| T06 | El periodo interno coincide con el periodo del archivo | archivos: 0 | base: 0 | PASS |
| T07 | Los momentos nacionales se calcularon antes de filtrar Bogota | en 18/18 periodos la poblacion de momentos supera a Bogota | PASS |
| T08 | La media del z-score nacional es aproximadamente 0 por periodo | max |media| = 1.314e-13 | PASS |
| T09 | La desviacion del z-score nacional es aproximadamente 1 por periodo | max |sd - 1| = 5.236e-13 | PASS |
| T10 | La union con el catalogo no multiplica estudiantes | 791,073 -> 791,073 filas | PASS |
| T11 | No se uso nombre, fuzzy, proximidad ni primera sede para la muestra principal | match_method: dane_sede_exacto, ninguno | funciones prohibidas en los scripts que construyen la muestra: ninguna | PASS |
| T12 | Los estados del cruce son exhaustivos y mutuamente excluyentes | 4 estados suman 791,073 de 791,073 filas | PASS |
| T13 | La suma del embudo reconcilia con el total de Bogota | desfase maximo por periodo: 0 | total embudo 791,073 vs base 791,073 | PASS |
| T14 | No existen rutas absolutas ni setwd() en los scripts nuevos | 0 llamadas a setwd, 0 cadenas con ruta absoluta | PASS |
| T15 | Raw, microdatos y bases privadas estan excluidos de Git | repositorio presente; 0 archivo(s) sensible(s) versionado(s) o preparado(s); reglas .gitignore 7/7 | PASS |
| T16 | Dos ejecuciones de 01 repiten los cinco agregados incluidos en el digest (momentos, integridad, embudo, match y controles) | actual a7340f855318 vs anterior a7340f855318 | PASS |

## Estados del cruce

| match_status | registros | pct_bogota |
|---|---|---|
| exact_match_valid_coordinates | 770,319 | 97.38% |
| valid_code_not_in_catalog | 20,377 | 2.58% |
| pending_manual_review | 376 | 0.05% |
| missing_or_invalid_seat_code | 1 | 0.00% |

## Embudo final

| periodo | total_nacional | punt_global_valido | bogota_regla_municipio | dane_sede_valido | match_exacto_catalogo | coordenada_valida | muestra_principal | excluidos |
|---|---|---|---|---|---|---|---|---|
| 20202 | 556891 | 556891 | 78367 | 78367 | 76608 | 76608 | 76608 | 1759 |
| 20211 | 58708 | 58708 | 3278 | 3278 | 3224 | 3224 | 3224 | 54 |
| 20212 | 606030 | 606030 | 80333 | 80333 | 79260 | 79260 | 79260 | 1073 |
| 20221 | 73795 | 73795 | 4888 | 4888 | 4564 | 4564 | 4564 | 324 |
| 20222 | 589183 | 589183 | 78181 | 78181 | 77172 | 77172 | 77172 | 1009 |
| 20231 | 77555 | 77555 | 4971 | 4971 | 4723 | 4723 | 4723 | 248 |
| 20232 | 602093 | 602093 | 79596 | 79595 | 79020 | 79020 | 79020 | 576 |
| 20241 | 84072 | 84072 | 4739 | 4739 | 4688 | 4688 | 4688 | 51 |
| 20242 | 592436 | 592436 | 79385 | 79385 | 79337 | 79337 | 79337 | 48 |
| 20161 | 74224 | 74224 | 5214 | 5214 | 4652 | 4652 | 4652 | 562 |
| 20162 | 589593 | 589593 | 91138 | 91138 | 86860 | 86860 | 86860 | 4278 |
| 20171 | 85149 | 85149 | 4923 | 4923 | 4472 | 4472 | 4472 | 451 |
| 20172 | 590996 | 590996 | 89514 | 89514 | 85916 | 85916 | 85916 | 3598 |
| 20181 | 65854 | 65854 | 4979 | 4979 | 4579 | 4579 | 4579 | 400 |
| 20182 | 609136 | 609136 | 88514 | 88514 | 85391 | 85391 | 85391 | 3123 |
| 20191 | 66104 | 66104 | 5150 | 5150 | 4687 | 4687 | 4687 | 463 |
| 20192 | 614789 | 614789 | 84293 | 84293 | 81742 | 81742 | 81742 | 2551 |
| 20201 | 46221 | 46221 | 3610 | 3610 | 3424 | 3424 | 3424 | 186 |

## Comparacion esperado contra observado

| control | esperado | observado | diferencia | estado |
|---|---|---|---|---|
| archivos_periodos | 18 | 18 | 0 | PASS |
| registros_nacionales | 5982829 | 5982829 | 0 | PASS |
| registros_bogota | 791073 | 791073 | 0 | PASS |
| match_exacto_sede | 770319 | 770319 | 0 | PASS |
| filas_gpkg | 2221 | 2221 | 0 | PASS |
| establecimientos_gpkg | 1871 | 1871 | 0 | PASS |
| establecimientos_multisede | 216 | 216 | 0 | PASS |
| coordenadas_plausibles | 2219 | 2219 | 0 | PASS |
| coordenadas_anomalas | 2 | 2 | 0 | PASS |
| llaves_faltantes | 0 | 0 | 0 | PASS |
| llaves_duplicadas | 0 | 0 | 0 | PASS |
| discrepancias_periodo | 0 | 0 | 0 | PASS |

## Limitaciones

- La geografia es armonizada a una referencia contemporanea: el catalogo de sedes es de
  2025-06-30 y se aplica a resultados 2016-2024. No es geocodificacion historica certificada.
- Un cambio de establecimiento asociado a una misma sede no se corrige; se registra.
- La comparacion con la base legacy es agregada por periodo y sede: el CSV legacy no
  contiene `estu_consecutivo` y no permite reconciliacion fila a fila.
- No hay repositorio Git en la raiz; la exclusion de microdatos se verifica por
  inspeccion de `.gitignore`, no por el indice de Git.

## Casos pendientes

- 376 registros en `pending_manual_review`: codigo de sede valido, sin match, con candidato por nombre.
- 20,377 registros en `valid_code_not_in_catalog`: codigo valido, sin match y sin candidato.
- 1 registro sin codigo de sede utilizable.
- 14,114 registros con desacuerdo de establecimiento entre ICFES y catalogo, en 26 sedes.

## Conclusion

**PASS** — 16 pruebas PASS, 0 FAIL, 0 en otro estado.

