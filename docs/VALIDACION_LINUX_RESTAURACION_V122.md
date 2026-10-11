# Validación Linux de la recuperación automática V122

Resultados ya obtenidos sobre `e2cb20cc12f63fbfa84fa1754c85e7ee33e8591a`,
base de la APK #126. Esta documentación conserva evidencia anterior; no constituye
una nueva ejecución ni una validación Android.

**15 escenarios aprobados, 0 fallidos; 60 ejecuciones de workers Flutter,
con 15 terminaciones reales mediante SIGKILL.** Los workers interrumpidos tienen
salidas no satisfactorias deliberadamente: sus escenarios solo pasan si el
controlador envía SIGKILL y la recuperación posterior supera las verificaciones.
Las 283 pruebas Flutter anteriores constan como aprobadas en la validación previa;
no se han repetido para conservar estas pruebas.

## Escenarios comprobados

| Escenario del informe | Resultado verificado | Estado |
| --- | --- | --- |
| `valid_zip` | Sustitución completa por el inventario nuevo; arranque posterior correcto | Aprobado |
| `corrupt_zip` | Rechazo del ZIP corrupto sin alterar el estado anterior | Aprobado |
| `insufficient_space` | Cancelación antes de sustituir datos | Aprobado |
| `death_sqlite_removed` | Recuperación tras retirar SQLite del destino | Aprobado |
| `death_during_photo_copy` | Recuperación tras copia parcial de la fotografía | Aprobado |
| `death_during_document_copy` | Recuperación tras copia parcial del documento | Aprobado |
| `death_during_svg_copy` | Recuperación tras copia parcial del icono SVG | Aprobado |
| `unexpected_death_after_sqlite` | Recuperación después de instalar SQLite entrante | Aprobado |
| `second_death_recovery_sqlite` | Reanudación tras otro cierre después de recuperar SQLite | Aprobado |
| `second_death_recovery_photos` | Reanudación tras otro cierre al sustituir fotografías | Aprobado |
| `second_death_recovery_documents` | Reanudación tras otro cierre al sustituir documentos | Aprobado |
| `blocked_recovery_preserves_rescue` | Escritura de recuperación fallida: bloqueo, rescate intacto y recuperación posterior | Aprobado |
| `space_failure_during_recovery` | Espacio insuficiente al recuperar: bloqueo, rescate intacto y recuperación posterior | Aprobado |
| `death_before_application` | Cierre en preparación: inventario original sin sustituir | Aprobado |
| `death_after_confirmation` | Cierre tras confirmación: conservación del inventario nuevo | Aprobado |

## Motor y datos utilizados

Se ejecutaron `BackupManager.createBackup`, `BackupManager.restoreBackup` y la
protección real del primer acceso a SQLite. No se sustituyó el motor por una
simulación. SQLite funcionó mediante FFI y la sincronización de directorios usó
el mecanismo Linux real. El proveedor de directorios se dirigió exclusivamente
a un laboratorio temporal nuevo, marcado como ficticio y separado por escenario.

El inventario incluía un conjunto y una pieza, un artículo en papelera, préstamos,
historial, mantenimiento e intervención, ubicaciones, tipo personalizado,
fotografía simulada, documento simulado, SVG, alias, grupos y favoritos de iconos,
y preferencias. Los archivos tenían tamaño suficiente para cortar copias por
streaming antes de terminarlas. No se utilizó el inventario móvil ni sus ZIP.

Se compararon las 11 tablas no internas: `tools`, `tool_images`, `tool_loans`,
`loan_contents`, `loan_events`, `borrowers`, `maintenance_tasks`,
`maintenance_records`, `tool_documents`, `field_options` y `management_settings`.
Se verificaron `PRAGMA integrity_check`, `PRAGMA foreign_key_check`, versión del
esquema, referencias reubicadas y SHA-256 de los seis archivos del inventario.
Las rutas de las fixtures se normalizaron solamente al comparar origen y destino.
También se comprobó la conservación del ZIP seleccionado y la limpieza de diario,
operación y destinos auxiliares tras una terminación confirmada.

## Condiciones de terminación y recuperación

El worker registraba el punto y la fase persistente y esperaba. El controlador
comprobaba que el PID correspondía a su propio hijo `flutter_tester`, mediante
`/proc`, y enviaba SIGKILL desde fuera del worker. No podían ejecutarse catch,
finally, teardown ni cierre ordenado de SQLite en ese proceso. Cada recuperación
arrancaba en una invocación Flutter distinta y utilizaba exclusivamente lo que
había quedado en disco. Se comprobaban las fases `applying` y `recovering`, los
hashes del rescate inmutable y, después de recuperar, un segundo arranque limpio.

La falta de espacio se inyectó como cero bytes disponibles en la costura de
pruebas existente: no se llenó físicamente un disco. El error de escritura de
recuperación se inyectó mediante esa misma infraestructura de depuración. Estos
controles y SIGKILL están en archivos de pruebas, sin botones ni hooks nuevos
en producción. Los archivos de prueba no coinciden con el patrón `*_test.dart`;
el controlador los ejecuta explícitamente, sin lanzar la suite habitual.

## Evidencia conservada y límites

El [informe JSON saneado](evidencias/RECUPERACION_V122_LINUX.json) procede del
informe original conservado. Incluye escenarios, tiempos medidos, resultados de
los 60 workers y hashes de rescate registrados. Se retiraron rutas temporales,
ubicaciones de logs y PID; no se añadieron resultados. El SHA-256 de procedencia
permite contrastarlo con el informe original si aún se conserva localmente.

No se detectaron fallos del motor en esta matriz. Los cuatro archivos de pruebas
se conservan en [support](../flutter/test/support/RESTORE_PROCESS_TESTS.md) y
[el controlador](../scripts/validate_restore_processes.py).

Linux no valida el selector Android, `content://`, los permisos, StatFs/fsync
nativo, almacenamiento Android realmente lleno ni particularidades de su ciclo
de vida. SIGKILL no equivale a un apagado o corte eléctrico: el kernel y sus
cachés siguen funcionando. La APK #126 permanece sin cambios.

La validación Android está **pendiente**, según el
[procedimiento aislado](VALIDACION_ANDROID_RESTAURACION_V122.md).
