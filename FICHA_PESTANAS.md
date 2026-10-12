# Ficha de artículos con pestañas — base V132

Base comprobada: `e010382a1dfe3c9d112709eb679d9507a0802dd0`, compartida por la rama de trabajo y `respaldo-gestor-herramientas-v132` al iniciar el cambio.

La misma ficha `EditToolPage` se utiliza al crear y editar artículos y piezas. Las cinco pestañas tienen icono, texto, desplazamiento horizontal e indicador de selección. Cada sección conserva su desplazamiento y sus widgets montados dentro de un único Form; los controladores y las variables del borrador no se sustituyen al cambiar de pestaña. El guardado superior y el inferior están disponibles en todas las secciones. La validación mantiene nombre y tipo obligatorios y vuelve a General cuando son incorrectos.

## Inventario de campos de la ficha

| Pestaña | Campo o control existente | Almacenamiento existente |
|---|---|---|
| General | Nombre obligatorio | `tools.name` |
| General | Tipo obligatorio; determina si se muestra tensión | `tools.tool_type` |
| General | Descripción con editor enriquecido Quill | `tools.description`, `tools.description_delta` |
| General | Código de barras y lectura con cámara | `tools.barcode` |
| General | Etiqueta QR propia | `tools.label_code`; generación y consulta existentes |
| General | Crear ficha con IA y revisión del borrador, cuando corresponda | Controles existentes; no son campos nuevos |
| Técnica | Marca | `tools.brand` |
| Técnica | Modelo | `tools.model` |
| Técnica | Número de serie | `tools.serial_number` |
| Técnica | Tensión, para tipos eléctricos | `tools.voltage` |
| Inventario | Cantidad | `tools.quantity` |
| Inventario | Unidad | `tools.unit` |
| Inventario | Cantidad mínima | `tools.minimum_stock` |
| Inventario | Estado de la herramienta / condición | `tools.condition`; es un único campo existente, no dos campos nuevos |
| Inventario | Lugar / taller | `tools.location_site` |
| Inventario | Estantería | `tools.location_rack` |
| Inventario | Balda | `tools.location_shelf` |
| Inventario | Caja / maletín | `tools.location_container` |
| Inventario | Ubicación heredada del conjunto si la ubicación propia está vacía | Consulta existente del padre; no se copia ni crea un campo |
| Inventario | Es un conjunto, solo cuando el artículo no es una pieza | `tools.is_set` |
| Inventario | Pertenencia a un conjunto y gestión de piezas | `tools.parent_id`; acceso Conjunto y pantalla de piezas existentes |
| Inventario | Fuera de servicio; gestión desde Mantenimiento | `tools.out_of_service` |
| Inventario | Accesos Conjunto, Documentos, Mantenimiento y Préstamos | Pantallas y tablas relacionadas existentes |
| Imágenes | Fotografías; cámara, galería múltiple, URL y opción IA existentes | `tool_images.path`; ruta heredada `tools.image_path` sigue conservada |
| Imágenes | Descripción de cada fotografía | `tool_images.description` |
| Imágenes | Tipo de fotografía | `tool_images.type` |
| Imágenes | Fotografía principal | `tool_images.is_primary` |
| Imágenes | Orden / posición | `tool_images.position`; lógica existente |
| Imágenes | Ver todas, ampliar, editar datos, hacer principal y eliminar mediante los controles existentes | Sin cambio de lógica de gestión |
| Otros | Precio de compra (€) | `tools.purchase_price` |
| Otros | Notas de mantenimiento, mostradas solo para consulta | `tools.service_notes`; su edición continúa en Mantenimiento, accesible desde Inventario |

No existía un campo independiente de notas generales en esta ficha: no se ha añadido ninguno. Marca, modelo y número de serie siguen agrupados en Identificación; la ubicación conserva su desplegable existente, ahora en Inventario.

## Datos relacionados y metadatos conservados

Los préstamos siguen accesibles tanto desde Inventario como desde el botón de estado de la barra superior, visible en todas las pestañas. Sus formularios existentes conservan destinatario, contacto, cantidades, unidad, fechas, notas, devoluciones, contenido del conjunto e historial. Documentos y mantenimiento mantienen sus pantallas y formularios actuales; no se redistribuyen sus campos internos dentro de esta ficha.

`tools.id`, `deleted_at` y `trash_group` siguen siendo metadatos internos, sin controles de edición nuevos. Los identificadores `id`, `tool_id` y la fecha `created_at` de las fotografías mantienen la lógica anterior, sin nuevos controles de edición. Disponibilidad calculada, préstamos activos, borradores de préstamo y fecha de devolución mantienen su lógica existente; no se convierten en columnas nuevas.

No hay cambios en el esquema, migraciones, construcción del objeto guardado, consultas ni gestión de archivos de fotografías. Solo cambian la presentación, la distribución de componentes existentes y la navegación a General al validar. Las pruebas usan bases y archivos temporales independientes del inventario del usuario.

Las pruebas Android de arranque se adaptan a los nuevos pasos de navegación —Técnica antes de Identificación e Inventario antes de Ubicación/Documentos— conservando las comprobaciones. No se cambia ningún workflow ni se genera una APK.

## Validación realizada

41 pruebas Flutter superadas: siete nuevas de pestañas y las comprobaciones existentes de tensión, identificación/ubicación, préstamos, conjuntos/gestión y arranque. Incluyen creación, retorno y guardado del artículo, reapertura SQLite, edición sin pérdida de campos, validación desde secciones ocultas, modificación enriquecida en Quill, vista de fotografía y selección de principal conservando los bytes del archivo, contenido del conjunto y relación padre/pieza, préstamo activo y pestañas en pantalla de 320 × 640.

Análisis estático de los archivos Dart afectados y pruebas: sin incidencias. Sintaxis Python del smoke Android comprobada; no se ha ejecutado el emulador ni una compilación APK en esta fase.
