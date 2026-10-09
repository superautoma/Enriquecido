# Editor SVG del Gestor de Herramientas

Base: `13a69bf82837db685a46ac64bac7fa0ed82ad1a8`, rama de referencia `desarrollo-edicion-multiple`, GitHub Actions 103. Desarrollo en `desarrollo-editor-svg`. Especificación del 9 de octubre de 2026, revisión 1.0.

## Fase 1 integrada

Gestor de iconos → Opciones del icono → **Editar SVG**. Está disponible para los SVG importados y los 50 eléctricos incorporados, desde lista, cuadrícula, galería, compacto, grupos, colores, favoritos/recientes y detalle (Más opciones). Los formatos raster conservan sus acciones anteriores.

El selector mantiene la pulsación larga para cambiar colores y añade **Editar SVG del icono actual**; en su vista Detalle ofrece Más opciones. Guardar una copia refresca la biblioteca, conservando la selección anterior. La nueva copia se puede elegir y asignar a Tipo/Estado por el flujo habitual.

El editor tiene relleno, línea, grosor, círculo SVG, escala uniforme, X/Y, giro, centrar/ajustar, vista previa de 24/48/80 px, deshacer/rehacer/restablecer, nombre y grupo. Dejar vacío un campo de color conserva su valor original; `none` elimina ese relleno/trazo o el círculo añadido. Paleta y hexadecimal `#RRGGBB`. El círculo de la vista previa es una opción de visualización; el círculo que se guarda está dentro del SVG y tiene identificador `svg_editor_background`. Los fondos originales identificados como `fondo` quedan fuera del recoloreado global.

Guardar genera XML real: geometría original y grupos conservados, más una transformación global; no rasteriza. Los límites de las formas/trazados se calculan con `Path`, incluyendo curvas/arcos normalizados, matrices de grupos y una estimación conservadora del trazo y sus uniones. **Centrar y ajustar** encaja esos límites en un lienzo de 100 unidades con margen mínimo orientativo del 10 %. Cuando se desplaza, escala o gira fuera del lienzo, el viewBox se amplía para no recortar; esto puede reducir el tamaño visual. Los límites conservadores de curvas/uniones pueden dejar más espacio vacío. La edición no es edición de nodos.

Los originales, incluidas claves `custom:<ruta>`, permanecen intactos. Los assets se leen en memoria y solo al guardar se escribe su copia externa; cancelar no crea archivos. La copia se guarda mediante temporal, validación XML/renderizador y rename dentro de documentos privados de Android, `tool_images/custom_icons/`. No precisa permiso de almacenamiento. Es externa a la APK pero no una carpeta pública de Descargas: se exporta con la copia de seguridad existente. Nombre de archivo seguro, único; se registran nombre/grupo y se restauran los metadatos anteriores si falla el guardado. No hay migración SQLite ni cambios en firma, paquete o permisos.

El atributo `data-gestor-svg="1"` identifica una copia editada, también tras restauración o importación aditiva con cambio de ruta. Por defecto se representa con sus colores reales, sin aplicar el ColorMapper de los iconos antiguos y con círculo de interfaz transparente. **Cambiar colores** sigue disponible como personalización explícita de representación; no modifica el SVG. Las asignaciones antiguas no se actualizan automáticamente.

## Subconjunto y seguridad

Se admiten `svg`, `g`, `path` (M/L/H/V/C/S/Q/T/A/Z), rectángulos, círculos, elipses, líneas, polígonos, polilíneas, título y descripción, colores SVG, estilos inline de pintura simples, translate/scale/rotate/matrix. No se admiten texto gráfico, SVG anidado, CSS complejo, defs/use, imágenes, filtros, máscaras, clipPath, gradientes o skew como comando independiente. Se rechazan con mensaje; el original se conserva y no se ofrece una exportación que pierda esas partes.

Se bloquean DOCTYPE/entidades, scripts/eventos, instrucciones XML, foreignObject, namespaces desconocidos, href y referencias externas/URL/data. Límites: 512 KiB por SVG, 1.500 elementos, profundidad 24, 120.000 caracteres de trazado, 12.000 números por trazado/puntos, coordenadas hasta 100.000 y matrices acumuladas acotadas. Escala de edición 0,1–3, X/Y ±100, giro ±180°, grosor 0–20. SVG vacío puede importarse por compatibilidad pero no editarse/exportarse.

Los nuevos SVG importados (individuales/ZIP) pasan esta validación antes de almacenarse. El ZIP se valida completo antes de escribir iconos; mantiene los límites previos de 20 MiB comprimidos, 50 MiB declarados descomprimidos, 1.024 entradas, 512 iconos y 5 MiB por archivo raster. Las rutas del ZIP se convierten en nombres seguros dentro de la biblioteca. Los SVG complejos antes importables quedan rechazados en las importaciones nuevas; los iconos existentes no se reescriben ni eliminan. Funciona sin red ni nuevos servicios.

## Verificación

Pruebas nuevas en `svg_editor_test.dart`, `svg_editor_security_test.dart`, `svg_editor_widget_test.dart`: exportación/reapertura/renderizador, colores y matrices persistentes, SHA-256 original, asignaciones/favoritos/grupos, nombres únicos, fallos sin escritura, backup/restore e importación, centrado fuera de viewBox, curvas y los 50 assets, historial, HEX, pantalla 320×640, cancelar/restablecer, acceso desde lista/cuadrícula/galería/detalle y selector, tamaños 24/48/80, SVG maliciosos/no compatibles y preflight ZIP.

Ejecutar la suite Flutter completa, análisis del target real y todos sus parts nuevos, y chequeo Python nativo antes del build release. El workflow incluye la nueva rama y ejecuta el smoke previo completo más `smoke_test.py --svg-only` en Android API 29: abrir gestor/editor, editar colores/fondo, centrar, deshacer/rehacer, guardar, reiniciar, reabrir y regresar sin permisos de almacenamiento. Los errores se anotan en GitHub y guardan traceback/logcat/estado de actividades. Las capturas reales `svg-editor-open.png`, `svg-editor-adjusted.png`, `svg-library-saved.png`, `svg-editor-reopened.png` y el SVG de ejemplo generado por los tests se suben en **startup-check**. No son capturas simuladas. La APK solo se publica como artefacto después del éxito de las pruebas Android y la verificación de firma estable. Las ramas y etiqueta de referencia no se publican ni modifican.

La validación en un móvil del propietario y con sus datos reales sigue siendo posterior: crear copia externa antes de actualizar, sin desinstalar ni borrar datos. La fase 1 no implica haber validado todas las variantes de SVG de terceros ni las API 24/35 en esta ejecución; la prueba del editor se ejecuta en API 29.

## Fase 2 — diseño preparado, no implementado

Puerta de entrada: fase 1 validada en APK real y conformidad expresa del usuario.

1. Separar `SvgEditorDocument` en árbol con identidades estables por elemento y capa. Preservar XML y atributos originales del subconjunto ampliado; los nodos no editables deberán conservarse o bloquear la exportación.
2. Añadir comandos de dominio inmutables para seleccionar/mover/rotar/escalar/recolorear/reordenar una forma, crear/duplicar/eliminar y agrupar. Cada comando verifica límites y aporta operación inversa; reutilizar el límite de historial, sustituyendo snapshots globales por comandos y coalesciendo el arrastre en una operación.
3. Crear selección visual/hit-test a partir de Paths y matrices acumuladas/inversas. Lienzo con zoom/pan independientes de la geometría exportada, rejilla, guías y ajustes opcionales.
4. Modelar nodos y manejadores de segmentos M/L/C/Q/Z primero; normalizar S/T/H/V solo con equivalencia geométrica probada. Arcos A necesitarán representación propia y pruebas antes de habilitar sus nodos. No convertir ni descartar comandos desconocidos silenciosamente.
5. Incorporar capa/UI de elementos, rectángulos/elipses/polígonos y luego trazados; ampliar validador/renderizador solo con cobertura de seguridad y geometría.
6. Pruebas de pérdida cero, matrices anidadas, multicolor, orden, nodos/Bézier, undo/redo por operación y round-trip. Guardado mantiene copias, rutas/claves originales y compatibilidad con backup; reemplazar en uso requeriría un flujo separado y respaldado.

No se han añadido herramientas de capas, formas nuevas, selección de nodos ni manejadores Bézier a la fase 1.

## Selector de colores previo a la fase 2

En los controles de relleno, trazo y fondo, «Elegir color» abre una ventana clara con paleta circular, marca de selección y tonalidades. «Personalizar» permite introducir #RRGGBB. «Seleccionar» confirma un único cambio en el historial; «Cancelar», volver atrás o cerrar la ventana no cambia el SVG. «Sin color» elimina la pintura y «Conservar original» mantiene el valor del documento original. Los controles de entrada y accesos rápidos anteriores siguen disponibles. La ventana se desplaza en pantallas pequeñas y sus muestras tienen un área mínima de 48 píxeles lógicos.

Esta mejora pertenece al editor básico: no incorpora formas, capas ni nodos de la fase 2. No cambia SQLite, fotografías, préstamos, archivos originales, identificación ni firma Android.

Comprobaciones locales de esta mejora: 191 pruebas Flutter aprobadas (4 nuevas del selector), análisis integrado sin errores ni advertencias y con un aviso informativo previo, compilación Android release correcta e identificación y certificado estable verificados. La APK local utiliza versionCode 107; este número no corresponde a una ejecución de GitHub Actions. Pendiente: ejecución del selector en Android y publicación de una APK validada. No se ha iniciado la fase 2.
