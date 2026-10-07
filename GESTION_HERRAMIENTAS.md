# Base de herramientas

La aplicación reúne herramientas individuales y conjuntos con piezas vinculadas. Las piezas conservan su ficha, fotografías, documentos, mantenimiento y préstamos; no se duplican en el listado principal.

En cada ficha se dispone de cuatro accesos con iconos: Conjunto, Documentos, Mantenimiento y Préstamos. Abrir estos apartados guarda primero la ficha para que los registros queden vinculados a una herramienta existente.

Los documentos admiten archivos, fotografías de cámara/galería y enlaces. Los archivos se copian al almacenamiento de la aplicación. Se pueden abrir, compartir, renombrar, sustituir y eliminar.

Los mantenimientos pueden ser puntuales o repetirse por días o meses. Registrar una intervención conserva fecha, trabajo, piezas y coste; calcula la siguiente fecha. Las intervenciones y tareas pueden editarse. Fuera de servicio bloquea nuevos préstamos y se cambia manualmente cuando la herramienta vuelve a estar disponible.

Los préstamos admiten cantidades y selección de piezas, contacto del destinatario, accesorios, estado de entrega, observaciones y fecha prevista. Las devoluciones pueden ser parciales, mantienen el préstamo abierto mientras queda contenido pendiente y registran estado, notas y necesidad de mantenimiento. Se conserva el historial de cambios; las cantidades entregadas pertenecen al registro original y las cantidades devueltas se añaden mediante devoluciones.

El menú Gestión de herramientas reúne los apartados, los vencimientos y los avisos configurables en el teléfono. La antelación se elige en cada préstamo o mantenimiento. Android entrega los avisos sin requerir que la aplicación esté abierta; su hora puede ajustarse por el sistema.

La base SQLite pasa de versión 8 a 9 mediante una migración que conserva los registros existentes. La copia ZIP incluye base de datos, imágenes y documentos; también acepta las copias anteriores y conserva los préstamos y sus historiales.
