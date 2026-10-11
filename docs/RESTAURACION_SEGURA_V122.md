# Restauración segura de V122

Base de desarrollo: `079ff0b39c2251c09bda5d64220f3032d7d3c46b` (APK #124).

«Restaurar y sustituir» conserva el formato ZIP existente (versiones 1 y 2).
«Importar datos» / «Importar y añadir» no utiliza este motor y no se ha modificado.
El esquema sigue en la versión 12; las migraciones existentes se aplican solamente
a la base entrante aislada, nunca a la base original durante la preparación.

## Qué se protege

- `gestor_herramientas.db`: artículos, listas, asociaciones de iconos, conjuntos,
  piezas, préstamos e historial, mantenimiento, documentos, ubicaciones, papelera,
  preferencias del inventario y otros ajustes SQLite.
- `tool_images/`: todas las fotografías, iconos personalizados, originales y
  metadatos SVG, alias, colores, categorías, favoritos y otros archivos existentes.
- `tool_documents/`: todos los archivos adjuntos, incluidos los no referenciados.

Estos son exactamente los destinos sustituidos por el formato de exportación
actual. Las credenciales de acceso, ChatGPT y otros datos del almacén seguro Android
no están en esos ZIP y permanecen intactos. Los avisos nativos se resincronizan
desde el inventario verificado, también después de recuperar el original.

## Operación y recuperación

El almacenamiento privado `app_flutter/.safe_restore_v122/` contiene el registro
`journal.json` y `operation/`, con la copia entrante y una recuperación independiente.
Cada cambio del registro usa escritura con flush, rename y sincronización del
directorio. El bloqueo del archivo `lock` evita dos operaciones a la vez.

1. `preparing`: se examinan las cabeceras ZIP y se extrae por streaming, con CRC
   real y límites de bytes reales, antes de verificar SQLite, esquema y relaciones.
   Se reubican las rutas de fotos e iconos solo en la base aislada.
2. `protecting`: se cierran las aperturas/escrituras SQLite pendientes y se hace
   checkpoint WAL. Se copia el estado original y se verifican SHA-256, tamaños,
   directorios, integridad SQLite y archivos relacionados.
3. `prepared`: la recuperación está completa; los destinos originales siguen intactos.
4. `applying`: se registra esta fase antes de cambiar el primer destino. Cada
   destino utiliza una copia verificada junto al destino, rename y sincronización
   del directorio. Se eliminan WAL/SHM/journal antiguos con SQLite cerrado.
5. `checking`: se comprueban SQLite, relaciones y referencias, y se abre el gestor
   restaurado. Solo después de verificarlo se escribe `confirmed` de forma persistente.
6. `confirmed`: se conserva el inventario nuevo. Si se interrumpe la limpieza,
   el arranque vuelve a intentarla sin recuperar el inventario anterior.

Una interrupción en `preparing`, `protecting` o `prepared` permite descartar solo
la preparación: el inventario original no ha sido sustituido. Una interrupción
en `applying` o `checking` obliga a recuperar el original antes de abrirlo.

La recuperación registra `recovering` y vuelve a verificar **toda** la copia original
antes de empezar. Instala copias de sus archivos sin consumir esa copia original.
Puede reiniciarse tras otra interrupción, incluso entre el rename de un destino y
su instalación. Tras comprobar archivos, SQLite y apertura se registra `recovered`.
El aviso de recuperación persiste hasta que el usuario lo reconoce.

`recovery_error`, un registro dañado o archivos de sustitución sin registro bloquean
el acceso normal. Se conservan los archivos y se ofrece «Reintentar recuperación».
El reintento no adivina un registro perdido ni utiliza una copia que no pase los
hashes. No se afirma que los datos estén recuperados si la comprobación falla.

La pantalla cubre el Navigator completo y bloquea las acciones y la navegación
atrás durante la operación. Las aperturas normales de SQLite también están
protegidas, independientemente de la pantalla. Si vuelve a crearse la pantalla
de acceso mientras hay una operación activa, espera su terminación.

## Límites y almacenamiento

- ZIP comprimido: 256 MiB; un archivo expandido: 256 MiB.
- Total expandido: 512 MiB; máximo 10.000 entradas.
- Se admiten los métodos ZIP store y deflate de las copias existentes.
  Se rechazan ZIP cifrados, multidisco, ZIP64, enlaces, tipos especiales,
  rutas inseguras, entradas duplicadas/conflictivas y carpetas desconocidas.
- Se exige espacio para preparación, punto original, instalación, otra copia
  completa para recuperar y un margen de 32 MiB. Se comprueba cada filesystem
  implicado y se vuelve a comprobar antes de sustituir y al recuperar.
- El ZIP seleccionado nunca se elimina. Si está dentro de una carpeta que se
  sustituiría, se cancela para conservarlo.
- Los temporales solo se limpian antes de sustituir, después de confirmar el
  nuevo inventario o después de verificar la recuperación. Una limpieza pendiente
  se reintenta al iniciar; se prioriza conservar datos recuperables.
- El registro del fallo contiene fase y fecha, sin rutas, SQL, nombres, contenido
  de documentos ni credenciales.

Android usa `StatFs` y `Os.fsync` en un canal limitado a directorios privados.
Linux usa `df` y `sync -f` para las pruebas. En otras plataformas se cancela
la operación si no puede verificarse el almacenamiento seguro.

## Validación y APK

`flutter/test/backup_restore_test.dart` usa SQLite real y directorios temporales,
con fallos inyectados y reinicios del estado del motor. La interfaz bloqueada se
prueba con texto ampliado y pantalla estrecha. Las inyecciones no se usan en release.

```bash
bash scripts/v122.sh check
```

Se conservan las 226 pruebas anteriores y se añaden 57 pruebas de esta mejora.
Los preparativos de cinco archivos de pruebas existentes incluyen ahora el
almacenamiento privado simulado y la comprobación previa fuera del reloj simulado;
sus casos y sus comprobaciones originales permanecen intactos.
No hay cambios de identificador, firma, `lib/main.dart`, Quill, autenticación ni menú.
La generación de APK continúa mediante **Build Integrated Quill APK**, con
`-t lib/main.dart` y `--no-tree-shake-icons`. Cuando se autorice publicar esta rama,
se podrá elegirla en la ejecución manual del workflow; no hace falta modificar main.

Antes de dar por validada la implementación nativa, comprobar en Android real:
espacio libre y fsync, restauración de un ZIP antiguo, cierre forzado en cada fase,
segundo cierre durante la recuperación, bloqueo de acceso y aviso posterior.
No se afirma que una simulación de interrupción equivalga a una prueba de pérdida
de alimentación física. Si otro proceso llena el almacenamiento durante la operación,
se conservará la recuperación y se bloquearán nuevos guardados hasta poder reintentar.
