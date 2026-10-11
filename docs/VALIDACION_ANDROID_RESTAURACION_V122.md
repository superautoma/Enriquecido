# Validación Android aislada de la restauración V122

**Estado: procedimiento preparado; pruebas Android no ejecutadas.**
Base: `e2cb20cc12f63fbfa84fa1754c85e7ee33e8591a`, APK oficial #126.
Las [15 pruebas Linux aprobadas](VALIDACION_LINUX_RESTAURACION_V122.md) y sus
60 workers no prueban los componentes Android descritos aquí. No se modifica
ni sustituye la APK instalada del usuario y no se usa su inventario.

## 1. Requisitos y límites de esta entrega

- Android SDK, platform-tools/adb, emulator, una imagen AVD desechable, JDK,
  Flutter de V122 y virtualización disponible. Usar API 29 como primera matriz
  y API 35 como segunda; un dispositivo físico solo si es exclusivo del laboratorio
  y está vacío, nunca el móvil personal.
- Un AVD nuevo llamado `V122_Restore_Lab_API29`, sin cuenta Google, sincronización,
  restauración del sistema, carpetas personales compartidas ni backups reales.
- `aapt`/`apkanalyzer`, `apksigner`, Python 3, SQLite y utilidades SHA-256 para auditar
  el paquete, los resultados y los archivos ficticios.
- Una **variante futura específica de pruebas** con applicationId
  `org.gestorherramientas.gestor_herramientas_quill_test.restorelab`, etiqueta
  «V122 LAB — DATOS FICTICIOS», almacenamiento propio y clave de laboratorio.
  No puede actualizar el paquete oficial. No emplear la clave de producción.
- Compilarla en modo debug: las costuras existentes `SafeRestore.testFault` y
  `testFreeBytes` se ignoran en release. Mantener el motor real y su esquema,
  `lib/main.dart`, plugins y código nativo de la revisión base. Conservar la
  configuración de iconos (`--no-tree-shake-icons` cuando proceda).

La variante y el controlador Android **no están implementados en este commit**.
Requieren trabajo posterior únicamente en configuración/archivos del laboratorio,
sin editar el identificador, firma o comportamiento de producción. Generar su
proyecto Android en una copia separada; no modificar el proyecto gestionado por
el workflow oficial. La variante quedará fuera de `Build Integrated Quill APK`,
sin dispararlo ni cambiarlo. Esta entrega no contiene APK ni crea emuladores.

## 2. Preparación posterior del emulador

En el gestor de dispositivos Android Studio, crear el AVD dedicado con una
imagen Google APIs sin Play Store, API 29 y almacenamiento desechable suficiente.
No clonar un AVD usado ni importar datos de otro dispositivo. Elegir el ABI
compatible con el host. Registrar imagen, API, ABI, filesystem y espacio inicial.
Repetir más adelante con otro AVD API 35 independiente.

Los siguientes son ejemplos para ejecutar **solo cuando el laboratorio esté
implementado y autorizado**. Ajustar el serial al AVD creado, nunca a un móvil:

```sh
LAB_AVD=V122_Restore_Lab_API29
LAB_SERIAL=emulator-5554
LAB_PACKAGE=org.gestorherramientas.gestor_herramientas_quill_test.restorelab

# Comprobación en cada llamada, sin usar adb sin -s ni seleccionar el único device.
lab_adb() {
  case "$LAB_SERIAL" in emulator-[0-9]*) ;; *) return 1 ;; esac
  test "$LAB_PACKAGE" = org.gestorherramientas.gestor_herramientas_quill_test.restorelab || return 1
  test "$(adb -s "$LAB_SERIAL" emu avd name | head -n 1 | tr -d '\r')" = "$LAB_AVD" || return 1
  adb -s "$LAB_SERIAL" "$@"
}

lab_adb get-state
lab_adb shell getprop ro.build.version.sdk
```

Antes de instalar una futura APK de laboratorio, verificar con aapt/apkanalyzer
su applicationId exacto y con apksigner su certificado de laboratorio. Rechazar
el paquete oficial y cualquier artefacto no identificado. Instalar únicamente en
este serial verificado. No usar `adb install -r` sobre el paquete oficial.
Confirmar que `run-as "$LAB_PACKAGE"` funciona (debuggable), que el almacenamiento
pertenece a ese paquete y que no hay montajes hacia los datos del usuario.

## 3. Inventario y copias ficticias

La futura instrumentación debe crear dos inventarios distintos, «ANTERIOR LAB»
y «NUEVO LAB», mediante las APIs reales de `ToolsDatabase` y `BackupManager`.
En Android usar SQLite y path_provider reales, **sin FFI ni mocks de directorios**.
No importar directamente el worker Linux como si fuese una prueba Android.

Incluir conjuntos/piezas, artículo en papelera, tipos y estados, ubicaciones,
préstamo y eventos/contenidos, mantenimiento e intervención, documento PDF de
prueba válido, fotografía válida, SVG, asociaciones, alias, grupo y favoritos,
y preferencias. Usar fotos/documentos grandes para observar copias parciales.
No usar nombres, imágenes, cuentas, contactos ni documentos de personas reales.

Crear el ZIP NUEVO con el exportador real y conservar un hash externo. Preparar
otro ZIP corrupto ficticio. Guardar exclusivamente esas fixtures en Downloads
del emulador y en un DocumentsProvider de pruebas con autoridad propia y grants
de lectura. El proveedor será otro componente del laboratorio, no una cuenta
cloud ni almacenamiento real del móvil.

Antes de cada escenario, reinicializar **solo** la aplicación LAB con ANTERIOR,
registrar su snapshot canónico y el del origen NUEVO, cerrar/checkpoint SQLite y
registrar los hashes de los archivos. Evitar resetear después de un corte hasta
haber verificado la recuperación y recogido las evidencias.

## 4. Selector, URI y permisos

La implementación base usa `FilePicker.platform.pickFiles` y recibe
`picked.files.single.path`; no pasa una URI directamente a `restoreBackup`.
El plugin resuelve/copia el contenido del proveedor a una ruta local. Por tanto:

1. Abrir «Restaurar y sustituir» desde el menú y seleccionar el ZIP ficticio desde
   el selector Android, primero Downloads y luego el DocumentsProvider LAB.
2. Registrar desde el proveedor LAB la URI `content://` concedida, flags, aperturas
   y bytes leídos, sin acceder a proveedores ni documentos reales.
3. Comprobar que el archivo local obtenido por el plugin puede leerse completo
   y su hash coincide con el ZIP del proveedor. No tratar `content://` como File.
4. Cancelar el selector y denegar/revocar el grant antes de completar la lectura:
   debe cancelarse o fallar sin sustituir el inventario anterior.
5. Revocar el acceso al proveedor tras preparar una restauración y matar el
   proceso. La recuperación debe depender del rescate privado, no de volver a
   abrir la URI. No se presupone que el permiso URI persista tras reiniciar.

Si el plugin devuelve `path == null` para un proveedor, no contabilizarlo como
restauración aprobada: documentar proveedor/versión y comportamiento y valorar
la corrección por separado. Estas rutas Android aún no están verificadas.

## 5. Cortes reales y puntos deterministas

La futura variante de laboratorio instalará un controlador **solo de pruebas**
que permita esperar en las costuras existentes del motor, sin cambiar su lógica.
Debe arrancar de nuevo con recuperación habilitada, nunca volver a ejecutar el
seed ni borrar el diario automáticamente después de una muerte de proceso.
La selección de puntos será externa/instrumentada, sin botones destructivos
en la aplicación oficial y sin URI o intent exportado que permita controlarla.

Puntos mínimos: `removed_database`, `applied_database`, un `copy_chunk` parcial
de fotos/documentos/SVG, `recovered_database`, `removed_tool_images`,
`removed_tool_documents`, `prepared_incoming` y `confirmed`. En cada punto:

1. Esperar una señal del controlador LAB con fase y archivos parciales; comprobar
   que el diario persistente corresponde a la operación esperada.
2. Recoger PID y evidencia del paquete LAB. Matar realmente el proceso desde el
   host/emulador; no lanzar una excepción Dart ni pulsar «Salir».
3. Para SIGKILL preciso, el controlador del host debe comprobar que todos los
   PID pertenecen al UID del paquete LAB y no matarse a sí mismo junto a una
   instrumentación que comparta proceso. En el emulador puede utilizarse
   `run-as` y `kill -9` si la imagen lo permite. No usar un PID fijo.
4. Alternativa para cierre Android: `lab_adb shell am force-stop "$LAB_PACKAGE"`.
   Registrar esta modalidad por separado: modifica el estado «stopped» del
   paquete y exige relanzamiento explícito. No etiquetarla como señal SIGKILL
   comprobada si no se midió dicha señal.
5. Confirmar que el proceso desapareció y que no se escribió un resultado de
   finalización; volver a abrir la variante mediante su launcher real, no mediante
   un helper que acceda a SQLite antes de la puerta de recuperación.

El host debe sobrevivir al cierre de la app para realizar la segunda interrupción.
No basta con un test de integración alojado en el mismo proceso que va a morir.

## 6. Matriz Android pendiente

Cada fila requiere evidencia y se marca **pendiente** hasta ejecutarse.

| Prueba | Procedimiento aislado | Resultado esperado |
| --- | --- | --- |
| Selector y cancelación | Elegir ZIP en Downloads, cancelar y confirmar por separado | Cancelar no modifica ANTERIOR; seleccionar entrega un ZIP completo |
| URI y grants | Proveedor LAB, URI content y revocación controlada | Lectura íntegra con grant; fallo seguro sin grant; nunca acceso a datos reales |
| Restauración completa | Restaurar NUEVO por la UI y reiniciar | Tablas, relaciones, preferencias y archivos coinciden con NUEVO; ZIP conservado |
| Corte SQLite | Cortar en removed_database y applied_database, en ejecuciones separadas | El siguiente arranque recupera ANTERIOR antes de permitir acceso |
| Cortes de archivos | Cortar en copia parcial de foto, PDF y SVG, por separado | Recuperación de ANTERIOR completo, no un inventario mixto |
| Segundo corte | Volver a cortar durante SQLite/fotos/documentos de recuperación | Tercer arranque recupera ANTERIOR; hashes del rescate no cambian |
| Error de recuperación | Fallo de escritura exclusivo LAB y reintento posterior | Acceso bloqueado, rescate intacto, ningún falso mensaje de éxito; reintento verificado |
| Espacio insuficiente | Costura LAB y después partición desechable realmente limitada | Cancelación previa sin cambios, o bloqueo con rescate conservado si falla al recuperar |
| Sincronización nativa | Usar restore_storage real con directorios privados y entradas inválidas | StatFs coherente; fstat de directorio, fsync y close; errores seguros y propagados |
| Límites del diario | Cortar antes de aplicar y después de confirmed | ANTERIOR antes de aplicar; NUEVO tras confirmed; no compensación duplicada |

Para espacio real, usar otro AVD desechable con cuota/tamaño acotado o un relleno
de pruebas limitado al almacenamiento LAB y con límite explícito de bytes. Medir
espacio y preservar presupuesto del host; no llenar una partición compartida
ni usar un bucle ilimitado. Registrar por separado falta de espacio detectada
antes de escribir y ENOSPC real durante copia/sincronización. Es una preparación
pendiente: el cero inyectado en Linux no demuestra esos comportamientos Android.

El canal `gestor_herramientas/restore_storage` debe ejercitarse sin mocks:
`freeBytes` se contrasta con StatFs/espacio del filesystem; `syncDirectory` usa
el Kotlin de #126 (O_RDONLY, S_ISDIR/fstat, fsync, cierre y manejo de errores).
Verificar rechazo de archivos normales y rutas ajenas al directorio privado de
la variante; el éxito de fsync no prueba por sí solo resistencia a corte eléctrico.

## 7. Verificación, hashes y registros

Después del arranque y la recuperación, usar un auditor de instrumentación LAB
para abrir mediante `ToolsDatabase` y comprobar `PRAGMA integrity_check = ok`,
`PRAGMA foreign_key_check` vacío y esquema esperado. Comparar todas las tablas
no internas, no solo contar artículos. Verificar parentId, préstamos/historial,
mantenimiento, ubicaciones, papelera, tipos/estados y referencias de archivos.
Normalizar únicamente los prefijos propios de las dos fixtures.

El auditor debe comparar SHA-256 y tamaño de fotos, documentos, SVG y metadatos
con los manifiestos ANTERIOR/NUEVO, comprobar ausencia de enlaces y referencias
rotas, hash del ZIP seleccionado, diario, rescate y auxiliares. Durante una
recuperación fallida no exigir limpieza: exigir conservación del rescate y bloqueo.
Tras éxito verificado, exigir limpieza y otro arranque sin compensación duplicada.

Para auditoría externa, exportar solo archivos ficticios mediante `run-as` después
de una apertura/checkpoint/cierre controlados por el auditor. No copiar únicamente
el archivo .db de una SQLite abierta omitiendo WAL. Guardar íntegros los archivos
WAL/SHM y diario como evidencia de un corte; analizarlos sobre una copia, sin
abrir ni alterar el rescate original que se está comprobando.

Ejemplos de recogida posterior, siempre con `lab_adb` verificado:

```sh
mkdir -p work/android-restore-evidence
lab_adb shell dumpsys package "$LAB_PACKAGE" > work/android-restore-evidence/package.txt
lab_adb logcat -d -v threadtime > work/android-restore-evidence/emulator-logcat.txt
lab_adb exec-out run-as "$LAB_PACKAGE" cat app_flutter/.safe_restore_v122/journal.json \
  > work/android-restore-evidence/journal.json
```

El diario puede no existir tras limpiar una operación: registrar esa ausencia,
no crear un diario ficticio. Recogerlo también antes de relanzar. El emulador
debe carecer de cuentas/datos reales; sanear rutas, PID y logs antes de publicar.
Conservar por caso: API/ABI, hash APK LAB y certificado, fixture/manifiestos,
modalidad y punto del corte, fase previa y posterior, hashes del rescate,
capturas de progreso/mensaje, auditoría SQLite/archivos y resultado final.

## 8. Aprobación, fallo y eliminación

Una restauración pasa solo con NUEVO completo y verificado. Una recuperación
pasa solo con ANTERIOR completo y verificado y acceso normal habilitado después
de esa comprobación. Un error de recuperación pasa su prueba negativa solo si
bloquea escrituras, conserva el rescate y no afirma que los datos están seguros.
Debe comprobarse también el reintento exitoso tras retirar el fallo controlado.

Inventario mixto accesible, referencias rotas, pérdida/consumo del rescate,
falso éxito, confirmación prematura o recuperación repetida destructiva son fallos.
Detener el caso y conservar toda la evidencia antes de resetear el laboratorio.
No corregir la APK oficial ni borrar datos para esconder un fallo.

SIGKILL y force-stop terminan procesos; el kernel puede seguir escribiendo sus
cachés. Apagar un emulador de forma ordenada tampoco prueba un corte eléctrico.
Los cortes de alimentación exigirían una campaña aparte con dispositivo/VM y
almacenamiento desechables, política de caché documentada y snapshots controlados.
Esta matriz no promete durabilidad frente a pérdida de alimentación.

Tras recopilar evidencia y verificar el resultado, desinstalar **solo**
`$LAB_PACKAGE` mediante el wrapper validado, apagar ese AVD y eliminar únicamente
`V122_Restore_Lab_API29` desde Device Manager. Repetir para el AVD API 35 si se creó.
No usar borrados globales, limpiar otros AVD, ni ejecutar pm clear/uninstall sobre
el identificador oficial. En un eventual dispositivo físico de laboratorio,
desinstalar exclusivamente la variante; nunca aplicar estas instrucciones al
móvil del usuario ni conectarlo para esta campaña.

Bloqueos actuales: no SDK/emulador local disponible; falta implementar y revisar
la variante debug aislada, el DocumentsProvider LAB y el controlador/auditor
externo. No es necesario modificar el motor de producción para preparar ese
trabajo. Ninguna comprobación Android de este documento se da por realizada.
