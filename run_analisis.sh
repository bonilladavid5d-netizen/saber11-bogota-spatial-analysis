#!/usr/bin/env bash
# Ejecuta la cadena completa en orden y se detiene ante el primer fallo.
#
# Entorno comprobado: macOS (la deteccion de marcadores de iCloud usa `ls -lO`).
#
# Uso:  ./run_analisis.sh

set -euo pipefail

cd "$(dirname "$0")"

echo "== Comprobacion de insumos =="

faltan=0
requerir() {
  if [ ! -e "$1" ]; then
    echo "  FALTA  $1"
    faltan=$((faltan + 1))
  fi
}

if [ ! -d data/raw ]; then
  echo "  FALTA  el directorio data/raw/"
  faltan=$((faltan + 1))
else
  n_txt=$(find data/raw -name 'Examen_Saber_11_[0-9][0-9][0-9][0-9][0-9].txt' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n_txt" -ne 18 ]; then
    echo "  FALTAN microdatos: se encontraron $n_txt de 18 TXT bajo data/raw/"
    faltan=$((faltan + 1))
  fi
fi

requerir "data/raw/raw 2/colegios06_2025.gpkg"

# Un shapefile no es un archivo: sin .dbf, .shx o .prj la lectura falla o pierde
# los atributos y el CRS.
requerir_shapefile() {
  for ext in shp dbf shx prj; do
    requerir "${1}.${ext}"
  done
}
requerir_shapefile "data/raw/UPZ/SHP/IndUPZ"
requerir_shapefile "data/raw/unidadplaneamientolocal/UnidadPlaneamientoLocal"
requerir "data/analysis/estudiantes_bogota_geolocalizados.csv"
requerir "outputs/tables/moran_global_principal.csv"
requerir "outputs/tables/tabla_resumen_lisa.csv"

if [ "$faltan" -ne 0 ]; then
  echo
  echo "Faltan $faltan insumo(s). Ver docs/INSUMOS.md para procedencia y colocacion."
  exit 2
fi
echo "  18 TXT, catalogo de sedes, capas UPZ/UPL completas (.shp/.dbf/.shx/.prj),"
echo "  base legacy y tablas originales: presentes"

echo
echo "== 01 Reconstruccion =="
Rscript R/01_reconstruir_base_geocodificada.R

echo
echo "== 02 Validacion de la Fase 1 =="
Rscript R/02_validar_fase1.R

echo
echo "== 03 Validacion directa del parquet =="
Rscript R/03_validar_parquet.R

echo
echo "== 04 Analisis espacial =="
Rscript R/04_analisis_principal.R

if [ -f R/05_modelos.R ]; then
  echo
  echo "== 05 Modelos =="
  Rscript R/05_modelos.R
fi

if [ -f R/06_exportar_shiny.R ]; then
  echo
  echo "== 06 Exportacion para Shiny =="
  Rscript R/06_exportar_shiny.R
fi

echo
echo "== Cadena completa sin fallos =="
