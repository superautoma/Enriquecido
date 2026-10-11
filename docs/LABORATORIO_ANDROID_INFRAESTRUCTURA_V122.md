# Laboratorio Android V122: primera fase de infraestructura

Base: `ebff9eed7c9093dfc64a95e6adb9f18e1f7a3b86`.
Rama exclusiva: `codex-v122-laboratorio-android`.
Workflow: [Android Restore Laboratory](../.github/workflows/android-restore-lab.yml).

Solo admite `workflow_dispatch`. El job comprueba además la rama exacta; no tiene
triggers push/PR, checkout, Flutter, firma, secretos, APK, instalación de apps,
inventarios, restauraciones, inyección de errores ni subidas de artefactos.
Permisos del token: `contents: read`; no hay escrituras en el repositorio.
El actor que solicita una ejecución necesita su propia autorización Actions.

## Qué comprobará una única ejecución autorizada

Runner hospedado `ubuntu-24.04`, CPU/RAM/disco, Java, disponibilidad de `/dev/kvm`
y permiso de lectura/escritura. Solo si es necesario se cambia el propietario
de ese único dispositivo al usuario del runner desechable usando sudo. No se
amplían los permisos para todos los usuarios ni se modifican reglas udev.
La prueba de aceleración `emulator -accel-check` se ejecuta antes del arranque.
No hay fallback a emulación lenta sin KVM; su ausencia es un fallo diagnosticado.

Imagen oficial Android 10 / API 29 `google_apis;x86_64`, canal estable, sin Play
Store, AVD con nombre único por run/attempt, dos cores y RAM de 2048 MB. El renderer
software de gráficos no implica desactivar la aceleración KVM de CPU. La acción
descarga componentes oficiales desde el SDK Android, incluidas sus dependencias
de plataforma/build-tools, pero no compila ni instala aplicaciones.

Se registran versiones de Java, SDK command-line tools, paquetes SDK instalados,
ADB y emulator. Después del arranque headless se comprueban `adb devices`, estado
device, `sys.boot_completed=1`, API 29, versión release y un echo no destructivo.
El tiempo aproximado se mide desde la sonda previa al lanzamiento hasta la sonda
ADB; incluye el trabajo auxiliar de la acción. No es un benchmark de rendimiento.

La acción solicita apagado en éxito/fallo. Un paso always verifica desaparición
de ADB, reintenta únicamente apagar ese serial si sigue presente y elimina solo
el AVD de esta ejecución. Se usan límites de 20 minutos por job, 12 para preparación
y emulator, 300 segundos de arranque y 15 segundos por comando ADB. Si el job se
cancela o agota su tiempo antes de la limpieza, la destrucción del runner hospedado
es la última barrera; no se afirma que el paso de limpieza haya terminado.

## Acción fijada y origen

`ReactiveCircus/android-emulator-runner` se fija al commit
`a421e43855164a8197daf9d8d40fe71c6996bb0d`, resuelto desde el tag anotado `v2`
(`4c44018e59b437e86cdfc41da381398f93ed8808`). Se revisaron `action.yml`,
`src/main.ts`, `src/sdk-installer.ts` y `src/emulator-manager.ts` de esa revisión.

- [Código e inputs de la revisión fijada](https://github.com/ReactiveCircus/android-emulator-runner/tree/a421e43855164a8197daf9d8d40fe71c6996bb0d)
- [Manual oficial de Android Emulator](https://developer.android.com/studio/run/emulator-commandline)
- [Ejecución manual de workflows](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/manually-running-a-workflow)
- [API workflow_dispatch](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event)

El SHA de la acción es inmutable; las herramientas/imágenes descargadas del canal
estable pueden actualizarse. Las versiones reales quedarán en los logs de cada
ejecución. No se utiliza una referencia móvil de la acción.

## Lanzamiento y posible bloqueo de registro

No usar el workflow oficial de APK como sustituto, ni añadir triggers automáticos.
GitHub documenta que workflow_dispatch necesita presencia del workflow en la
rama predeterminada para habilitar su ejecución manual. Este archivo se conserva
solo en la rama de laboratorio: no se añade a main para sortear esa condición.

Si GitHub reconoce el archivo y acepta el ref, la solicitud soportada es una sola:

```sh
gh workflow run android-restore-lab.yml \
  --repo superautoma/Enriquecido \
  --ref codex-v122-laboratorio-android
```

No repetir una solicitud aceptada ni reintentar una respuesta de red ambigua sin
consultar primero las ejecuciones. Si el workflow no está registrado/no es
despachable, detenerse y pedir autorización antes de cambiar rama predeterminada,
configuración de repositorio o ubicación del workflow. No crear PR ni merges.
La política de red del entorno Codex también debe permitir el endpoint de Actions
y la identidad usada debe tener Actions write; el workflow conserva contents read.
Una denegación de red previa a GitHub no demuestra que GitHub haya rechazado el ref.

## Criterios y evidencias

Aprobado requiere aceleración comprobada, boot completo, API correcta, ADB y echo
operativos, apagado verificado y limpieza sin errores. Registrar URL/run ID,
conclusión, runner, KVM, versiones, tiempo y mensajes LAB_* de los logs/summary.
Fallo requiere conservar el error concreto y detener esta fase; no hacer una
cadena de correcciones o ejecuciones adicionales. Bloqueado significa que no
se pudo solicitar una ejecución; KVM, boot, ADB y tiempos remotos quedan sin medir.

Solo tras revisar un resultado aprobado se podrá autorizar la siguiente fase.
La [campaña de restauración Android](VALIDACION_ANDROID_RESTAURACION_V122.md)
sigue pendiente; no está incluida en este workflow. La APK #126, su firma,
identificador, ramas de producción y pruebas Linux permanecen intactos.
