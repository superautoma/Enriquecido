# Base de herramientas

## Crear una ficha desde una foto con ChatGPT

En «Opciones → Crear ficha con IA», toma una foto de la herramienta y su etiqueta
o elige una imagen de la galería. «Conectar ChatGPT» abre la pantalla de conexión:
«Continuar con ChatGPT» usa el navegador del móvil para seleccionar la cuenta,
autorizar el plan compatible y volver a la aplicación. No pide la contraseña
dentro del gestor ni necesita una clave de API. Las cuentas guardadas se mantienen
por separado; se muestran los modelos que ofrece la cuenta activa y un enlace
«Gestionar uso». La autorización utiliza el flujo oficial de Sign in with ChatGPT
para proyectos personales locales. Su disponibilidad y límites dependen del plan.

La fotografía solo se envía a OpenAI cuando se pulsa «Analizar con ChatGPT».
La app conserva el texto recibido por partes y espera la confirmación final antes
de preparar la ficha. Acepta un único objeto JSON completo, incluso si viene en un
bloque de texto. Si la respuesta no se puede convertir en ficha, «Ver respuesta de
ChatGPT» permite leerla en esa pantalla; no se guarda ni se crea un artículo.
La respuesta prepara nombre, tipo, descripción y datos de identificación que
sean legibles. Los identificadores que no aparecen en el texto leído se dejan
vacíos. La cantidad, el precio, la ubicación y la condición se revisan en el
formulario normal. «Revisar ficha» abre ese formulario y el artículo solo se
crea al pulsar «GUARDAR». No se aceptan respuestas interrumpidas o incompletas.
El análisis se puede cancelar y los errores de uso remiten a «Gestionar uso».

Las credenciales se cifran con Android Keystore y se conservan fuera del directorio
de las copias de inventario y de las copias automáticas de Android. La sesión se
renueva de forma serializada; cerrar sesión intenta revocar el permiso remoto y
elimina los tokens locales. Las respuestas se solicitan con `store:false` al
endpoint público de Responses, sin acceder a conversaciones guardadas en ChatGPT.
La autenticación usa PKCE, estado y nonce, y valida firma, emisor, audiencia,
caducidad e identidad de la cuenta. Una sesión iniciada sin el permiso de usar
el plan no habilita el análisis de fotos.

Documentación oficial:
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations

Las pruebas locales/CI simulan la red para errores, cancelación y respuestas,
y comprueban las pantallas y el almacenamiento nativo. La autorización real de
la cuenta y el reconocimiento real de una fotografía deben probarse en el móvil
del propietario; no se presupone acceso por el hecho de instalar la APK.

«Opciones → Sonido y vibración» permite activar por separado un clic corto y
la respuesta háptica al pulsar botones, elegir opciones o abrir una ficha.
«Probar botón» reproduce los efectos seleccionados. Las preferencias se guardan
en SQLite y viajan con la copia completa. El sonido respeta el modo silencio;
la vibración utiliza un pulso de 120 ms sin exigir control de amplitud, con
compatibilidad para Android antiguos, Android modernos y varios motores.
Si una API falla, se intenta el patrón clásico. Se respetan los ajustes táctiles
de Android. La pantalla detecta motor, permiso y respuesta táctil, muestra la
versión instalada y explica los bloqueos en vez de ocultarlos.
«Probar vibración (1 segundo)» prueba el motor aunque el efecto de los botones
esté apagado, sin añadir un clic ni otro pulso. «Ajustes del móvil» abre los
ajustes de sonido con alternativa a los ajustes generales; al volver se actualiza
el estado. Una orden enviada no se presenta como una vibración físicamente confirmada.
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
