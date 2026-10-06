# Nota metodológica

Documenta las decisiones no evidentes. Las que provienen del proyecto original están
marcadas como tales; el resto son de esta fase.

---

## 1. Unidad de observación y llave

La unidad es **una presentación del examen**, identificada por `periodo + estu_consecutivo`.
No es una persona: quien presenta dos veces aparece dos veces. Todos los conteos de este
caso —791.073, 770.319, 719.466— son de presentaciones, no de estudiantes únicos.

Verificado en los 18 archivos: 0 faltantes, 0 duplicados dentro de periodo, 0 discrepancias
entre el `periodo` de la columna y el del nombre del archivo.

El prefijo de `estu_consecutivo` **no** codifica el periodo de forma fiable: en 2019-2
empieza por `SB11201940`. La columna `periodo` es la autoridad.

---

## 2. Códigos DANE

Texto en todas las etapas. Normalización: únicamente `trimws`. **No se rellenan ceros**:
ambas fuentes entregan 12 caracteres, en el 100 % del catálogo y en 791.072 de 791.073
registros de Bogotá.

Formato: dígito de sector + código DIVIPOLA del municipio + seis dígitos. Las sedes rurales
usan prefijos municipales distintos de 11001 (`11769`, `11848`, `11850`), correspondientes
a la ruralidad del Distrito.

El código de establecimiento nunca sustituye al de sede; la prueba V09 lo verifica.

---

## 3. Regla de Bogotá

`cole_cod_mcpio_ubicacion == "11001"`, sobre la **ubicación del colegio**. Las dos
alternativas —código de departamento `11` y texto `BOGOT`— seleccionan exactamente el mismo
conjunto: **cero discrepancias en los 18 periodos**. La regla se fijó antes de observar los
conteos.

---

## 4. Población elegible y estandarización

Población nacional elegible: todo registro con `punt_global` numérico en `[0, 500]`, sin
restringir por `estu_estudiante` ni `estu_grado`. No hay valores fuera de rango ni
faltantes, de modo que coincide con el total de 5.982.829.

Los 874.112 registros sin código de colegio **sí entran** en la referencia nacional: son
presentaciones válidas. Lo que no pueden es clasificarse como Bogotá.

```
z_punt_global_nacional = (punt_global − media_nacional_periodo) / sd_nacional_periodo
```

Por periodo, antes de filtrar Bogotá, desviación muestral (n−1). Verificado dos veces:
dentro del pipeline y **releyendo los 18 TXT originales desde cero** (prueba V04).

Estandarizar por periodo es decisión del proyecto original: las escalas difieren entre
semestres por calendario y calibración del ICFES. Lo que cambia aquí es la **población de
referencia**, que pasa de la muestra bogotana a la nacional.

La desviación nacional varía entre **47,61 y 59,61** según el periodo. Por eso una magnitud
expresada en z agregada sobre varios periodos no tiene conversión única a puntos del
Saber 11, y este caso no la hace.

---

## 5. Vinculación geográfica

```
cole_cod_dane_sede  ==  DANE12_SED        (igualdad exacta, texto contra texto)
```

Unión `many-to-one`, no multiplicativa: `DANE12_SED` tiene 2.221 valores únicos en 2.221
filas. Verificado antes y después (791.073 → 791.073).

Métodos descartados para asignar la muestra: nombre, emparejamiento aproximado, proximidad
espacial, primera sede del establecimiento. La prueba T11 lo verifica inspeccionando el
**árbol sintáctico** de los scripts que construyen la muestra; buscar por texto encontraría
las cadenas de patrón del propio validador.

Los nombres solo proponen candidatos de revisión manual, por igualdad exacta de nombre de
sede normalizado. Sin Levenshtein. No portan coordenadas ni entran a la muestra principal.

### Estados del cruce

Exhaustivos y mutuamente excluyentes sobre las 791.073 presentaciones:

| Estado | Presentaciones |
|---|---:|
| `exact_match_valid_coordinates` | 770.319 |
| `valid_code_not_in_catalog` | 20.377 |
| `pending_manual_review` | 376 |
| `missing_or_invalid_seat_code` | 1 |
| `exact_match_invalid_coordinates` | 0 |
| `catalog_conflict` | 0 |

Los excluidos de la muestra principal son **20.754**: los 20.753 con código válido sin
coincidencia, más el único con código inválido.

---

## 6. CRS y plausibilidad de coordenadas

El GPKG declara `EPSG:3857` pero almacena grados (lon ∈ [−74,3933, −74,0162], lat ∈
[3,8295, 4,8239]). Se corrige la etiqueta con `st_set_crs(4326)`; **no se reproyecta**. El
archivo en disco no se modifica. La anomalía ya estaba documentada en el README del equipo.

Dos filas tienen coordenadas `−1,797693e+308` (`−DBL_MAX`), centinela que `st_is_empty()`
no detecta. Intentar invertir Pseudo-Mercator sobre esos valores es lo que bloquea
`st_transform` en este entorno.

**Ventana de plausibilidad**: `lon ∈ [−74,50, −73,95]`, `lat ∈ [3,70, 4,85]`. Incluye la
ruralidad de Sumapaz. Es un rectángulo, no el límite administrativo: la prueba V11 verifica
pertenencia a esa ventana, no al Distrito. Resultado: 2.219 plausibles, 2 centinela.

---

## 7. Medición de la concentración

Convenciones heredadas del proyecto original: unidad sede, EPSG:3116, W kNN k=5
estandarizada por filas, 999 permutaciones, LISA con p < 0,05, paleta GeoDa.

**Moran global** usa `moran.mc()` con 999 permutaciones. El p mínimo alcanzable es
**0,001**, que es el valor reportado; no es "p < 0,001".

**LISA** usa `localmoran()` con su **p analítico**, sin ajuste por comparaciones múltiples.
Con 1.224 unidades evaluadas, una fracción de los conglomerados significativos es esperable
por azar. El mapa es exploratorio.

**Convención de cuadrantes**: la variable y su rezago espacial se centran cada uno en su
propia media, convención heredada del informe original. `spdep` reconoce esta convención
junto a otras (`mean`, `median`, `pysal`); la elección cambia qué unidades caen en cada
cuadrante cerca de los ejes.

**Escalas agregadas.** Las cifras de UPZ y UPL no son directamente comparables con las del
estudio original, que usaba un z interno a Bogotá y otra agregación. Además, la comparación
entre asignación por atributo y por cruce espacial no aísla el tipo de asignación: agrupa
110 unidades frente a 104, con centros y vecinos distintos.

`st_join` se usa una sola vez, para medir esa discrepancia. No asigna geografía a ningún
registro de la muestra.

---

## 8. Modelación

**Especificación principal: Spatial Durbin Model** sobre panel pooled sede-año.

| Elemento | Decisión | Origen |
|---|---|---|
| Unidad | sede × año | proyecto original |
| Observaciones | 10.228 (1.224 sedes, 9 años) | esta fase |
| Dependiente | media por sede-año de `z_punt_global_nacional` | esta fase |
| Estructura temporal | efectos fijos de año | proyecto original |
| W | kNN k=5 en bloques por año | proyecto original |
| Estimación | máxima verosimilitud, log-determinante por LU | esta fase |

**Por qué bloques por año.** Una sede solo tiene vecinos dentro de su propio año: el panel
es pooled, no una estructura espacio-temporal con dependencia entre periodos.

**Por qué los indicadores de año no se rezagan.** Con W en bloques por año, `W %*% D_año`
reproduce exactamente `D_año` y la matriz sería singular. El término Durbin se especifica
solo sobre las covariables sustantivas.

**Por qué LU.** La W kNN estandarizada por filas es asimétrica; `method = "Matrix"` exige
simetría y falla. LU calcula el log-determinante exacto sobre la matriz dispersa.

**Covariables.** Estrato promedio del hogar, proporción de colegio oficial, con internet en
casa, en jornada completa, en calendario A, de mujeres, y tamaño de la sede en logaritmo.
Misma familia que el estudio original.

**`prop_bilingue` queda fuera de la especificación principal.** `cole_bilingue` no se
reporta en el 20,6 % de las sede-año, y esa ausencia se concentra en sedes pequeñas
(mediana de 38 presentaciones frente a 57). Incluirla costaría una quinta parte del panel
de forma no aleatoria. Se conserva como comprobación sobre la submuestra donde sí se
observa; el equipo original ya había explorado esta sensibilidad.

**Selección del modelo.** El SDM tiene el AIC más bajo (9047,1 frente a 9174,9 del SEM,
9178,3 del SAR y 9198,9 del MCO) sobre las mismas 10.228 observaciones. Esa es la base de
la comparación.

Como medida **descriptiva**, el I de Moran de los residuos pasa de 0,0308 en MCO a −0,0013
en SDM. **No se reportan valores p de ese procedimiento**: `moran.test()` trata los
residuos como una variable observada y su p no es un contraste válido después de estimar.
`lm.morantest()` sería el contraste apropiado para el MCO, pero este cierre es descriptivo
y no lo incorpora. Un p alto tampoco probaría independencia.

Las pruebas de multiplicadores de Lagrange sobre los residuos de MCO distinguen dos
lecturas: las **simples** (`RSerr`, `RSlag`) rechazan la ausencia de estructura espacial
pero no identifican el canal; las **ajustadas** contrastan un canal condicionando al otro y
aquí no respaldan ambos por igual (`adjRSerr` p = 0,012; `adjRSlag` p = 0,076).

**Efectos.** En un modelo con rezago de la dependiente los coeficientes no son efectos
marginales: hay retroalimentación por los vecinos. Se reportan efectos directos, indirectos
y totales por la descomposición de LeSage y Pace, con errores por simulación (R = 1.000) y
trazas por el método de multiplicación con m = 30. Los **efectos indirectos recogen la
propagación completa de la matriz de pesos**, no únicamente los vecinos inmediatos.

**Unidades.** Las covariables de proporción viven en `[0, 1]`: un coeficiente "por unidad"
sería el salto de 0 % a 100 %. La tabla 13 incluye por eso columnas `*_presentado`, que
multiplican estimación e incertidumbre por 0,1 para expresar el cambio **por 10 puntos
porcentuales**. `estrato_promedio` se presenta por una unidad de estrato y
`n_estudiantes_log` en escala logarítmica. Todo son asociaciones entre agregados sede-año.

**Supuestos de inferencia.** Los errores estándar y p se interpretan bajo los supuestos de
la especificación pooled. No se aplicó una corrección específica por dependencia temporal
entre observaciones de una misma sede; las simulaciones de impactos propagan la covarianza
del modelo ajustado. Los efectos fijos de año no resuelven esa dependencia.

**Diagnósticos.** VIF máximo 2,60 (`prop_oficial`); ninguna observación sin vecinos;
ρ = 0,0609 dentro del intervalo admisible (−1, 0,999). En la variante que incluye
`prop_bilingue`, el Hessiano de diferencias finitas no devuelve error estándar de ρ, de
modo que esa fila se reporta sin contraste.

**Lo que no se hizo.** No se reestimaron los 16 modelos del estudio original ni las cuatro
escalas territoriales. Se eligió una especificación principal coherente con la pregunta y
se la sometió a comprobaciones dirigidas a problemas concretos de la base.

---

## 8 bis. Alcance de la supresión en la entrega pública

La exportación para la app suprime la media (`z_publicado`) de las sedes con menos de 10
presentaciones en los nueve años: son 12 de 1.224, y con n = 1 la media es el puntaje de
una persona redondeado. **Esas sedes conservan su clasificación LISA, su conteo y su
ubicación.** La supresión limita la divulgación de un promedio; no convierte la entrega en
anónima, y no equivale a afirmar que sin ella se identificaría a una persona.

Por la misma razón se retiró de la exportación pública la tabla de evolución por periodo y
conglomerado: con 18 periodos por 5 conglomerados quedaban celdas de 1 y 2 presentaciones.
La app nunca la consumió. La evolución total por periodo, que sí consume, agrega decenas de
miles de presentaciones por celda.

---

## 9. Control de ejecución

Un fallo de validación **invalida la entrega**, no solo devuelve un código de salida.

- `02` y `03` marcan su estado como `EN_CURSO` al arrancar y solo lo cambian a `VALIDA` al
  terminar con éxito. Una excepción deja el estado en `EN_CURSO`, de modo que una
  aprobación anterior no sobrevive a una corrida que no terminó.
- Ambos registran la huella SHA-256 del parquet, y `exigir_validacion()` comprueba que las
  **dos** correspondan al archivo que se va a consumir.
- El cálculo de impactos del SDM es obligatorio: si falla, `05` invalida la tabla 13 y la
  figura 5 renombrándolas, registra el estado y sale con código distinto de cero.
- `06` exige las ocho tablas que consume la app antes de copiar ninguna, para no dejar
  destinos de una corrida anterior pasando por actuales.
- Ante un fallo, `VALIDATED_CLAIMS.md` se sobrescribe con un aviso de retención y el estado
  queda `INVALIDA`.
- `04`, `05` y `06` llaman a `exigir_validacion()` antes de hacer nada: exigen que ambos
  validadores hayan pasado **sobre exactamente el parquet que van a consumir**. Si el
  archivo cambió después de validarse, se detienen.
- `run_analisis.sh` encadena las seis etapas con `set -e` y comprueba la presencia de todos
  los insumos antes de empezar.

**Prueba del bloqueo.** Se alteró un valor de `z` en una copia de la base. `02` no lo
detecta y devuelve 0; `03` falla en V01 y devuelve 1; `04` se niega a ejecutarse y devuelve
1; las figuras no cambian de fecha y las afirmaciones quedan retenidas. Al restaurar la
base (SHA idéntico) los tres vuelven a 0.

**T16** mide exactamente la repetibilidad de los cinco agregados incluidos en su digest
—momentos, integridad, embudo, match y controles— entre dos ejecuciones de `01`. No es una
identidad del parquet completo ni del análisis.

**T15** inspecciona el índice de Git cuando hay repositorio en la raíz: una regla en
`.gitignore` no desversiona un archivo ya rastreado. Si no hay repositorio, se registra
`N/A — sin repositorio` con su alcance, sin prometer un PASS futuro.

---

## 10. Dependencias

R 4.4.0. Ningún paquete se instaló.

| Paquete | Versión | Uso |
|---|---|---|
| `readr` / `dplyr` / `tidyr` / `stringr` / `purrr` | 2.1.6 / 1.2.0 / 1.3.1 / 1.6.0 / 1.0.2 | lectura y transformación |
| `arrow` | 23.0.1.1 | Parquet |
| `sf` | 1.1.0 | lectura espacial, CRS, cruces |
| `spdep` | 1.4.1 | Moran, LISA, matrices de pesos |
| `spatialreg` | 1.4.3 | SAR, SEM, SDM, impactos |
| `Matrix` | — | W dispersa en bloques |
| `ggplot2` | 4.0.2 | figuras |
| `shiny` / `bslib` / `leaflet` | 1.13.0 / 0.10.0 / 2.2.3 | aplicación |
| `digest` / `jsonlite` / `janitor` | 0.6.35 / 1.8.8 / 2.2.1 | huellas, metadatos, nombres |

`DT` y `bsicons` **no están instalados**: la app corregida los evita deliberadamente. La app
original del equipo los requiere y por eso no arranca en este entorno.

`colorspace` y `farver` se usaron fuera del pipeline para validar la paleta bajo simulación
de daltonismo.

Sesión exacta en `outputs/audit/fase1/sessionInfo.txt`.

---

## 11. Reproducción

```bash
./run_analisis.sh                            # cadena completa, se detiene ante el primer fallo
R -e 'shiny::runApp("shiny_corregido")'      # app local
Rscript shiny_corregido/test_app.R           # 21 comprobaciones de la app
```

Sin `setwd()` y sin rutas absolutas; la prueba T14 lo verifica sobre el árbol sintáctico.

**Precondición.** Los insumos deben estar materializados. Si el proyecto vive en una
carpeta sincronizada con iCloud pueden ser marcadores `dataless`; `01` lo comprueba y se
detiene con un mensaje explícito. Inventario completo en `docs/INSUMOS.md`.

**Entorno comprobado:** macOS (Darwin 25.2.0), R 4.4.0. La detección de marcadores de
iCloud usa `ls -lO`, específico de macOS.
