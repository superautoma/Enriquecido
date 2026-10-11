# Búsqueda avanzada · base 127

La búsqueda reutiliza el inventario y sus filtros, fotografías, iconos y fichas.
Se actualiza al escribir y permanece encima de los resultados al desplazarlos.
Todos los términos deben aparecer, en cualquier orden y en campos distintos:
`taladro 18V`, `18 v taladro` o `bosch hormigón`.
Se ignoran mayúsculas y tildes, incluidas las tildes Unicode descompuestas.

Los filtros se combinan con la búsqueda. Dentro de tipo, condición y tensión,
varias selecciones son alternativas. El estado/disponibilidad permite distinguir
préstamos, vencimientos y fuera de servicio, y puede combinarse con la condición
física guardada. Se mantiene la opción histórica «Prestado».

Se buscan nombre, descripción, códigos, tipo, tensión, condición, marca, modelo,
número de serie, ubicación, notas de servicio, cantidades, unidad y precio,
además de los datos textuales de los préstamos y las piezas de un conjunto.
Los filtros existentes controlan si las piezas aparecen también por separado.
Todo funciona localmente sobre las fichas cargadas desde SQLite; no cambia el
esquema, no migra datos y no envía consultas o fotografías a Internet.

## Fases posteriores

Los botones de cámara y galería están reservados y deshabilitados, con la
indicación «Próximamente». No capturan ni procesan imágenes.

- Comparación local: reutilizar las fotografías existentes y el selector de
  imágenes para comparar una imagen con el inventario sin conexión.
- Identificación avanzada con ChatGPT: modo separado y explícito, que requerirá
  conexión y selección de la imagen que el usuario quiera enviar. La búsqueda
  local debe seguir disponible sin este servicio.

Pendientes: diseñar los descriptores y la clasificación de similitud local,
la presentación de candidatos y la integración opcional con ChatGPT.
