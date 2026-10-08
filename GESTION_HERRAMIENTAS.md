# Base de herramientas

«Opciones → Sonido y vibración» permite activar por separado un clic corto y
la respuesta háptica al pulsar botones, elegir opciones o abrir una ficha.
«Probar botón» reproduce los efectos seleccionados. Las preferencias se guardan
en SQLite y viajan con la copia completa. El sonido respeta el modo silencio;
la vibración utiliza un pulso directo de 70 ms a intensidad máxima, con
compatibilidad para Android anteriores y comprobación del motor disponible.
El instalador declara el permiso normal VIBRATE, sin petición interactiva.
Los campos de texto,
desplazamientos y pulsaciones canceladas no generan efectos. La respuesta no
retrasa las acciones.

La aplicación reúne herramientas individuales y conjuntos con piezas vinculadas. Las piezas conservan su ficha, fotografías, documentos, mantenimiento y préstamos; no se duplican en el listado principal.

En cada ficha se dispone de cuatro accesos con iconos: Conjunto, Documentos, Mantenimiento y Préstamos. Abrir estos apartados guarda primero la ficha para que los registros queden vinculados a una herramienta existente.

Los documentos admiten archivos, fotografías de cámara/galería y enlaces. Los archivos se copian al almacenamiento de la aplicación. Se pueden abrir, compartir, renombrar, sustituir y eliminar.

Los mantenimientos pueden ser puntuales o repetirse por días o meses. Registrar una intervención conserva fecha, trabajo, piezas y coste; calcula la siguiente fecha. Las intervenciones y tareas pueden editarse. Fuera de servicio bloquea nuevos préstamos y se cambia manualmente cuando la herramienta vuelve a estar disponible.

Los préstamos admiten cantidades y selección de piezas, contacto del destinatario, accesorios, estado de entrega, observaciones y fecha prevista. Las devoluciones pueden ser parciales, mantienen el préstamo abierto mientras queda contenido pendiente y registran estado, notas y necesidad de mantenimiento. Se conserva el historial de cambios; las cantidades entregadas pertenecen al registro original y las cantidades devueltas se añaden mediante devoluciones.

El menú Gestión de herramientas reúne los apartados, los vencimientos y los avisos configurables en el teléfono. La antelación se elige en cada préstamo o mantenimiento. Android entrega los avisos sin requerir que la aplicación esté abierta; su hora puede ajustarse por el sistema.

La base SQLite pasa de versión 8 a 9 mediante una migración que conserva los registros existentes. La copia ZIP incluye base de datos, imágenes y documentos; también acepta las copias anteriores y conserva los préstamos y sus historiales.


## Listado, vistas y filtros

En «Mis herramientas», el botón junto a Filtrar permite elegir tarjetas, lista compacta o cuadrícula. «Filtrar» combina disponibilidad, tipos, estados, tensiones, existencias, conjuntos/piezas, documentos, fotos y mantenimiento. Las selecciones múltiples admiten cualquiera de los valores elegidos dentro de un grupo; los grupos se combinan entre sí. Los resultados y el número se actualizan al aplicar.

Puede ordenarse por incorporación, nombre, cantidad o precio. La vista, orden y filtros se guardan en management_settings y viajan con las copias de seguridad. «Limpiar filtros» conserva la vista y orden. «Actualizar herramientas» o deslizar hacia abajo vuelve a leer los datos sin perder la búsqueda.

Los conjuntos reflejan los documentos, mantenimiento y piezas fuera de servicio de su contenido. La búsqueda admite nombres sin tildes, todas las personas con préstamos activos y nombres de piezas. Las fichas de piezas se incluyen cuando se solicita, con el nombre de su conjunto. La consulta de disponibilidad se realiza en bloque para reducir las lecturas repetidas al mostrar inventarios grandes.


## Importar sin sustituir

«Importar y añadir», en el menú principal y en Gestión de base de datos, admite los ZIP de copia existentes (formatos 1 y 2). Primero muestra cuántas herramientas, piezas, documentos, préstamos y mantenimientos va a añadir. Los datos se incorporan como fichas nuevas. Si un nombre o referencia coincide, se conservan ambas fichas.

La importación reasigna los identificadores y todos sus enlaces dentro de una transacción. Copia imágenes, documentos e iconos a nombres nuevos; conserva las devoluciones parciales, los eventos de préstamo y las intervenciones. Las opciones de Tipo y Estado nuevas se añaden; las existentes, contactos guardados y ajustes actuales se mantienen. No sustituye los archivos de nombres ni ajustes de iconos.

El mismo ZIP, identificado por SHA-256 de sus bytes, se importa una sola vez, aunque se cambie su nombre. Ese historial se guarda en management_settings y viaja con las copias completas. Una copia distinta se considera una nueva importación. Ante una copia incompleta o una operación fallida, no se conservan inserciones parciales y se retiran los archivos nuevos de ese intento. Las copias antiguas se actualizan solamente en el directorio temporal.

«Restaurar y sustituir» conserva su función de recuperación completa y explica que sustituye el inventario. Para unir bases se utiliza «Importar y añadir».
