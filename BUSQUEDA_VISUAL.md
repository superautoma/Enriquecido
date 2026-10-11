# Búsqueda visual local — primera fase

Cámara y Galería reutilizan image_picker. No se envían fotografías, descriptores ni datos del inventario a servicios externos; no se incluye OpenAI ni un modelo descargable. La consulta queda en el archivo temporal proporcionado por el selector, sin añadirse a las fotografías de las herramientas.

El descriptor se calcula sobre 128 × 128 píxeles: histograma de gradientes orientados (HOG simplificado, 4 × 4 celdas y 9 orientaciones sin signo) y estructura de luminancia centrada en 16 × 16 zonas. La puntuación combina coseno de HOG (75 %) y estructura (25 %). No usa nombres de archivo ni histogramas de colores. Para cada herramienta se conserva el mejor resultado entre todas sus fotografías locales.

Se comparan registros activos; texto, filtros y Mostrar piezas de conjuntos determinan qué resultados se presentan. Se muestran hasta 20, ordenados por similitud, con acceso al editor existente y al conjunto de la pieza. Cerrar la búsqueda visual recupera la vista de inventario.

Cada fotografía se decodifica reducida y por separado; los recursos nativos se liberan tras obtener el descriptor. La caché en memoria guarda hasta 256 descriptores, identificados por ruta, tamaño y fecha de modificación. Miniaturas de resultados limitadas a 112 píxeles. Se omiten archivos ausentes, ilegibles, uniformes, de más de 16 MiB o de más de 50 millones de píxeles. No hay escrituras ni migraciones de SQLite y no se modifican fotografías existentes.

Limitaciones: compara apariencia fotográfica, no identifica categorías ni modelos de herramientas. Cambios de perspectiva, rotación, fondo, oclusión, encuadre o iluminación pueden alterar mucho el resultado. El umbral 0,90 es una heurística conservadora sin calibración sobre un conjunto real de herramientas; no es una probabilidad de identidad. Incluso una puntuación alta requiere confirmación humana. Fotos tomadas con fondo y encuadre similares suelen funcionar mejor. No hay segmentación automática ni invariancia a rotación/perspectiva.

Validación automatizada: formas distintas con los mismos colores, variación de brillo, decodificación PNG, ordenación por contenido pese a nombres distintos, archivos ausentes/corruptos, caché e invalidación, cancelación y permisos denegados simulados, exclusión de piezas mediante selección del inventario y apertura del resultado seleccionado. La captura real y los permisos del dispositivo necesitan validación posterior en Android; no se genera APK en esta fase.
