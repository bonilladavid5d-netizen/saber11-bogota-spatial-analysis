# Insumos requeridos

Inventario completo de entradas de la cadena. `run_analisis.sh` comprueba su presencia
antes de producir cualquier resultado y se detiene con codigo 2 si falta alguna.

## Resumen

|rol                          |ruta                                                         |procedencia                                                |redistribuible                                  |
|:----------------------------|:------------------------------------------------------------|:----------------------------------------------------------|:-----------------------------------------------|
|Microdatos Saber 11 (18 TXT) |data/raw/raw 1/, data/raw/raw 2/                             |ICFES, descarga publica de resultados Saber 11             |No: contienen identificadores individuales      |
|Catalogo de sedes 2025       |data/raw/raw 2/colegios06_2025.gpkg                          |SDP / IDECA, corte 2025-06-30                              |No se redistribuye aqui; se documenta la fuente |
|Poligonos UPZ                |data/raw/UPZ/SHP/IndUPZ.shp                                  |SDP / IDECA, 112 poligonos, EPSG:4686                      |No se redistribuye aqui; se documenta la fuente |
|Poligonos UPL                |data/raw/unidadplaneamientolocal/UnidadPlaneamientoLocal.shp |SDP, POT 2022 (Decreto 555 de 2021), 33 poligonos          |No se redistribuye aqui; se documenta la fuente |
|Base legacy geolocalizada    |data/analysis/estudiantes_bogota_geolocalizados.csv          |Producto del pipeline original (notebooks/main_report.Rmd) |No: 719.466 filas a nivel de presentacion       |
|Moran original               |outputs/tables/moran_global_principal.csv                    |Producto del estudio original del equipo                   |Si: agregado, incluido en la entrega            |
|LISA original                |outputs/tables/tabla_resumen_lisa.csv                        |Producto del estudio original del equipo                   |Si: agregado, incluido en la entrega            |

## Huellas de las entradas no-microdato

|ruta                                                         |     MB|sha256 (32 car.)                 |
|:------------------------------------------------------------|------:|:--------------------------------|
|data/raw/raw 2/colegios06_2025.gpkg                          |   1.24|440d9b818d8b7ee63bd4c17dcfec645c |
|data/raw/UPZ/SHP/IndUPZ.shp                                  |   1.23|bde6ce225033dde9cc60f85f718f7bbe |
|data/raw/unidadplaneamientolocal/UnidadPlaneamientoLocal.shp |   0.77|e91654d7a1eefcc08c21975d8f93037a |
|data/analysis/estudiantes_bogota_geolocalizados.csv          | 373.84|c36b247cdf417266860c804df0996ba9 |
|outputs/tables/moran_global_principal.csv                    |   0.00|6a3799f1c5a3d70a2fb610d2c89b8f6f |
|outputs/tables/tabla_resumen_lisa.csv                        |   0.00|5a684b81e81392f53b2e5aae2a034b06 |

## Microdatos Saber 11

18 archivos, 3.56 GB en total. Huella completa de cada uno en `outputs/audit/fase1/00_input_manifest.csv`.

| periodo|archivo                   |    MB|filas   |sha256 (16 car.) |
|-------:|:-------------------------|-----:|:-------|:----------------|
|   20202|Examen_Saber_11_20202.txt | 399.8|556,891 |5997bb114859fa45 |
|   20211|Examen_Saber_11_20211.txt |  21.4|58,708  |88d5305d9c7431a6 |
|   20212|Examen_Saber_11_20212.txt | 419.8|606,030 |3fa500fd2e975b65 |
|   20221|Examen_Saber_11_20221.txt |  27.1|73,795  |ad7029a0257c6ab7 |
|   20222|Examen_Saber_11_20222.txt | 406.0|589,183 |253839279b9ae69c |
|   20231|Examen_Saber_11_20231.txt |  28.1|77,555  |d664b1d1894cbd0f |
|   20232|Examen_Saber_11_20232.txt | 412.8|602,093 |edd969737084c5d4 |
|   20241|Examen_Saber_11_20241.txt |  29.7|84,072  |93daf9af22e0aa56 |
|   20242|Examen_Saber_11_20242.txt | 404.8|592,436 |525c5af65bfb455a |
|   20161|Examen_Saber_11_20161.txt |  26.1|74,224  |6e0fdb79b296342e |
|   20162|Examen_Saber_11_20162.txt | 284.3|589,593 |5e3ec3d0879ea7f9 |
|   20171|Examen_Saber_11_20171.txt |  29.8|85,149  |72934e403012b911 |
|   20172|Examen_Saber_11_20172.txt | 415.3|590,996 |106800a20ebba62e |
|   20181|Examen_Saber_11_20181.txt |  25.2|65,854  |71d67259367a0d56 |
|   20182|Examen_Saber_11_20182.txt | 422.5|609,136 |0689ac39f933f89d |
|   20191|Examen_Saber_11_20191.txt |  26.3|66,104  |d66f6f16cb644109 |
|   20192|Examen_Saber_11_20192.txt | 427.3|614,789 |d02110c11c6cec0b |
|   20201|Examen_Saber_11_20201.txt |  18.3|46,221  |128b1a338cb55797 |

## Que se reproduce y que se revisa

| Con los insumos privados | Solo con lo entregado |
|---|---|
| La cadena completa 01 -> 06 | Todas las tablas agregadas y figuras |
| La base auditada y sus 23 pruebas | La evidencia de validacion en `outputs/audit/fase1/` |
| La comparacion legacy fila a sede | El resumen agregado `10_legacy_vs_corregido_resumen.csv` |
| Los modelos sobre el panel de sedes | Coeficientes, impactos y diagnosticos exportados |

La base legacy `estudiantes_bogota_geolocalizados.csv` permanece privada. Lo que de ella
se puede revisar sin microdatos es su agregacion por periodo y codigo de sede, incluida
en la entrega.

## Entorno

Comprobado en macOS (Darwin 25.2.0) con R 4.4.0. La deteccion de marcadores `dataless`
de iCloud usa `ls -lO`, que es especifico de macOS.
