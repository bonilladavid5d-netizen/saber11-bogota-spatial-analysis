# Cierre de entrega — Saber 11

Fecha: 6 de octubre de 2026. Paquete base: `ENTREGA_PORTAFOLIO_v4_1.zip`.
SHA-256 del ZIP recibido: `5c7d66c1a2fd0390f8b41d2a7997569c8781851accedd8d388dede14669fc7d3`.

## Resultado

El paquete contiene la app con mapa de 500 px, página desplazable, sin botón de ampliación,
teselas OpenStreetMap con atribución y el patrón corregido de T15. Los resultados, figuras
y agregados son idénticos a la entrega analítica previamente revisada. La revisión visual
se cierra por confirmación de David en la conversación; no se afirma una nueva inspección
visual propia ni una nueva ejecución de R en este entorno.

Se actualizaron exclusivamente los cuatro documentos de la tabla inferior: cierre visual
con su procedencia, 26 pruebas en la documentación actual y acceso directo a Shiny con los
agregados incluidos. `CIERRE_ENTREGA.md` es el único archivo nuevo.

## Integración en Proyecto - VP

1. Comparar las huellas previas de estos cuatro documentos con las del repositorio local.
   Si coinciden, incorporar las versiones de esta entrega; si difieren, integrar los cambios
   documentales conservando cualquier edición local posterior. Guardar el respaldo fuera del
   conjunto de publicación.
2. Incorporar solo esos cuatro documentos y, si se desea conservar esta nota, guardarla en
   la documentación de entrega. No copiar la carpeta entera. En particular, no sustituir
   `.gitignore`: el del repositorio contiene reglas y negaciones propias del equipo que no
   son idénticas a la copia mínima del ZIP. El código corregido ya está integrado localmente.
3. Revisar la selección real de archivos para el commit y prepararla con rutas explícitas.
   No usar `git add .` ni incluir por arrastre los cambios previos del equipo en
   `notebooks/main_report.Rmd`, `CLAUDE.md` y `.claude/settings.local.json`. Conservarlos.
4. Ejecutar T15 con el validador real después de preparar el índice. Registrar la salida
   local nueva en el log de evidencia; conservar las anteriores como historia. La revisión
   debe cubrir los archivos efectivamente preparados. Revisar `git diff --cached --stat`
   y `git diff --cached --check` antes de presentar el resumen del commit.
5. Entregar el resumen de archivos preparados, resultado de T15 y mensaje propuesto del
   commit. No hacer commit ni push con esta instrucción. No volver a estimar los modelos
   para integrar documentación.

El ZIP no contiene `.git`, insumos privados ni todos los archivos originales del equipo;
es una entrega del caso, no un reemplazo completo de su repositorio. Las referencias a
`shiny/` describen la carpeta original conservada localmente, no incluida en este paquete.

## Huellas de los documentos

| Archivo | SHA-256 recibido | SHA-256 de cierre |
|---|---|---|
| `README.md` | `b835a5d133e892661f9efedbb6439224790c3b39440329141213934bfc3db605` | `93969c44ac4f5c3bbc02f29e73159056a56a79e628d740cfaf3dcc187fe5cf3f` |
| `shiny_corregido/README.md` | `fc7a34da4fc66f19618da34c0cb4d030b77d67217dc18255d6bd670d75941451` | `df4ef56b81dfe22f1362c1aab1316d343ea7408cc91fa937a4212f1e522c9fa2` |
| `outputs/portafolio/evidencia/app_verificacion.md` | `cf633e074935b16fbf66b16dc306744fade1ca59d5450df8a322e0dd4c3bde6e` | `dd03bae3f7fbc725f20ff951fad7e1d6cd14171967adbba2e8f4454311a7624f` |
| `ESTADO_VALIDACION_v4_1.md` | `72d2ec3e9aeb7069d41073fd38f0c7256d102e1a6c6aa2f991176cf2f0e06019` | `8cf2a040aaf3be63e55566e9a34845a3a1262ed857c124e755b787562e95417a` |

## Alcance de la evidencia

- 91 archivos recibidos; 92 en esta entrega, por la adición de esta nota.
- Ausentes del ZIP: microdatos TXT, parquet, RDS de modelos, GPKG de entrada,
  `evolucion_periodo.csv` y restos `.invalidado`.
- Los agregados y GeoJSON de la app contienen datos de sedes y territorios, no identificadores
  individuales. La supresión de medias de 12 sedes pequeñas mantiene el alcance limitado
  documentado: no implica anonimato de la información de sedes.
- Los enlaces locales del README resuelven dentro del paquete.
- El PASS visual procede de David. No se adjuntaron capturas de su última comprobación.
- T15 fue comunicado como PASS en el repositorio original. El ZIP conserva un log histórico
  y una copia de los reportes de Fase 1 con T15 N/A por haberse generado fuera de un repositorio.
  No se alteraron pruebas históricas para hacerlas aparecer como recién ejecutadas.
- El archivo local `correcciones_visuales.log` no vino incluido. La nota de estado documenta
  esa ausencia; no se inventó un log para completarla.

## Mensaje propuesto de commit

`Completa caso Saber 11 con validación, modelos espaciales y app Shiny`
