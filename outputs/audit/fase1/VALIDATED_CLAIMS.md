# Afirmaciones verificadas — Fase 1

Solo afirmaciones cuantitativas comprobadas en esta corrida. Cada una enlaza con la
tabla o prueba que la respalda.

- El universo original son 18 archivos del ICFES, uno por aplicacion, de 2016-1 a 2024-2. [`00_input_manifest.csv`](00_input_manifest.csv), prueba T01 en [`validation_results.csv`](validation_results.csv)
- La llave `periodo + estu_consecutivo` no tiene faltantes ni duplicados dentro de ningun periodo. [`02_integridad_llave_periodo.csv`](02_integridad_llave_periodo.csv), prueba T05
- El periodo declarado coincide con el periodo del archivo en las 5,982,829 filas procesadas. [`02_integridad_llave_periodo.csv`](02_integridad_llave_periodo.csv), prueba T06
- El catalogo de sedes 2025 tiene 2,221 sedes unicas en 2,221 filas, correspondientes a 1,871 establecimientos, de los cuales 216 tienen mas de una sede. [`07_crosswalk_sede_catalogo_2025.csv`](07_crosswalk_sede_catalogo_2025.csv)
- 2,219 sedes del catalogo tienen coordenada plausible dentro de Bogota D.C. y 2 son geometrias centinela. [`07_crosswalk_sede_catalogo_2025.csv`](07_crosswalk_sede_catalogo_2025.csv)
- 791,073 registros corresponden a colegios ubicados en Bogota segun el codigo municipal 11001. [`05_embudo_bogota_periodo.csv`](05_embudo_bogota_periodo.csv)
- Las tres reglas posibles para identificar Bogota -- codigo municipal 11001, codigo de departamento 11 y texto del municipio -- seleccionan exactamente el mismo conjunto: 0 discrepancias en los 18 periodos. [`05_embudo_bogota_periodo.csv`](05_embudo_bogota_periodo.csv)
- 770,319 de esos registros enlazan exactamente por codigo DANE de sede con el catalogo 2025 (97.38%). [`06_match_sede_periodo.csv`](06_match_sede_periodo.csv)
- La muestra principal, con match exacto, coordenada plausible y puntaje valido, es de 770,319 registros (97.38% de Bogota). [`05_embudo_bogota_periodo.csv`](05_embudo_bogota_periodo.csv)
- El z-score nacional por periodo tiene media maxima en valor absoluto de 1.31e-13 y desviacion que se aparta de 1 en a lo sumo 5.24e-13. [`03_momentos_nacionales_periodo.csv`](03_momentos_nacionales_periodo.csv), pruebas T08 y T09
- La union con el catalogo no altero el numero de observaciones: 791,073 filas antes y despues. [`run_metadata.json`](run_metadata.json), prueba T10
- La muestra principal se construyo exclusivamente con `match_method = dane_sede_exacto`; no se uso nombre, coincidencia aproximada, proximidad espacial ni primera sede. Prueba T11

