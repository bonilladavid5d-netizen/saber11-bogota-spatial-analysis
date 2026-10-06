# Explicación para entrevista

## Versión de 60 segundos

Trabajé con un equipo de la Maestría en Economía Aplicada de los Andes en un estudio de
econometría espacial sobre el Saber 11 en Bogotá: seis millones de presentaciones del
examen, nueve años, la pregunta de si el rendimiento escolar está concentrado
territorialmente.

Al revisar el pipeline encontré que el cruce exacto por código DANE nunca había producido
una sola coincidencia. El código convertía códigos de doce dígitos con `as.integer()`, que
desborda el entero de 32 bits y devuelve nulo, así que el sistema caía a un emparejamiento
por nombre de colegio. Eso determinaba qué presentaciones llegaban a la muestra analítica.
Además, el z-score se describía como posición nacional pero se calculaba después de filtrar
Bogotá.

Reconstruí la base desde los archivos originales con una sola regla de vinculación —código
de sede contra código de sede, igualdad exacta— y con validación que invalida la entrega si
algo no cuadra. El resultado sustantivo sobrevive: hay concentración espacial fuerte y
estable, I de Moran de 0,34. La medición cambia respecto del 0,30 original, pero lo
presento como comparación entre especificaciones, no como una descomposición identificada:
cambian a la vez la variable dependiente, el conjunto de sedes y los vecinos.

## Si preguntan por el modelo

Estimé cuatro especificaciones sobre un panel pooled de sede por año: mínimos cuadrados
como referencia, SAR, SEM y Spatial Durbin. Elegí el Durbin por tener el menor AIC entre
las cuatro especificaciones sobre las mismas observaciones: 9047 frente a 9199 del MCO.
El Moran residual pasa de 0,031 en MCO a −0,0013 en SDM; es una comparación descriptiva,
sin valores p ni una conclusión de independencia de los residuos.

Lo interesante son los efectos descompuestos. El estrato del hogar, por una unidad, tiene
un efecto directo de 0,34 desviaciones nacionales y un indirecto de 0,03: casi todo es
propio de la sede. El acceso a internet, por un aumento de diez puntos porcentuales, tiene
un directo de 0,16 y un indirecto negativo de −0,06. El signo negativo del indirecto es un
hecho del ajuste; no tengo con estos datos manera de atribuirlo a un mecanismo concreto, y
no lo hago.

Son asociaciones condicionales entre agregados sede-año. No hay variación exógena en
ninguna covariable. Y los errores estándar se leen bajo los supuestos de la especificación
pooled: no corregí por dependencia temporal dentro de una misma sede.

## Si preguntan por el aprendizaje del caso

El caso muestra la importancia de distinguir selección de registros, asignación de
geometría y referencia del puntaje. El emparejamiento por nombre seleccionaba registros,
pero la geometría final del estudio original se construía por código de sede desde el
GeoPackage. La reconstrucción cambia la selección y la referencia del z-score; su
comparación con el original no aísla la contribución de cada cambio.

También importa conservar las unidades: la desviación nacional varía por periodo, así que
una diferencia entre z agregados de varios periodos no tiene una conversión única a
puntos del examen.

## Si preguntan qué haría distinto

Separaría desde el principio dos preguntas que se confunden: si el código corre, y si la
llave une. El pipeline original sí tenía diagnósticos —publicaba el conteo de cruces por
nivel y validaba los momentos del z-score— pero ninguno estaba conectado como compuerta:
el resultado de cero cruces por código era visible y la entrega seguía adelante. Eso es lo
que cambié.

Y la geografía: estamos aplicando un catálogo de sedes de 2025 a resultados desde 2016. Es
defendible como geografía armonizada y así está documentado, pero no es geocodificación
histórica, y esa limitación no se cierra con más código.

## Si preguntan por lo que no hice

No reestimé los dieciséis modelos del estudio original ni las cuatro escalas territoriales.
Elegí una especificación principal y la sometí a comprobaciones dirigidas a problemas
concretos de la base: conflictos de establecimiento, masa mínima por unidad, definición de
vecindad. Tampoco interpreto nada como causal.

## Si preguntan por tu contribución específica

En el proyecto original participé en la teoría, la planificación, el código y el análisis,
junto con otros cinco autores. El diseño econométrico espacial, las convenciones
cartográficas y la app Shiny original son trabajo del equipo. Lo mío en esta fase fue la
auditoría, la reconstrucción con validación que bloquea, la medición corregida y la
reestimación del modelo sobre la base corregida.

## Números que conviene tener a mano

| | |
|---|---|
| Volumen | 5.982.829 presentaciones, 18 aplicaciones, 2016-1 a 2024-2 |
| Bogotá | 791.073 presentaciones; 770.319 en la muestra principal (97,4 %) |
| Defecto | 0 cruces por código; 945 por nombre exacto y 168 por Levenshtein |
| Concentración | I de Moran 0,342, p = 0,001 con 999 permutaciones, 1.224 sedes |
| Modelo | SDM, ρ = 0,061 (p = 2,7e-5), AIC 9047 frente a 9199 del MCO |
| Efectos del estrato (+1 unidad) | directo 0,340, indirecto 0,029, total 0,369 |
| Efectos de internet (+10 p.p.) | directo 0,156, indirecto −0,056, total 0,100 |
| Validación | 16 + 23 pruebas; un fallo invalida la entrega y bloquea el análisis |
