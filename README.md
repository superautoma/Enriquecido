# Gestor de Herramientas V122

La aplicación oficial Flutter arranca desde `flutter/lib/main.dart`. Ese archivo
solo delega en `main_quill_integrated_test.dart`, que conserva la aplicación
completa: Quill, SQLite, fotos, documentos, IA, préstamos, mantenimiento,
conjuntos, QR y protección local. El nombre histórico del archivo integrado se
conserva para no romper sus bibliotecas `part`, pruebas y referencias.

## Preparar y validar

Desde la raíz de la copia V122, con Flutter 3.44.0 y Dart 3.12.0:

```bash
bash scripts/v122.sh setup
bash scripts/v122.sh check
source scripts/v122-env.sh
```

`check` ejecuta las 221 pruebas originales y una regresión que invoca el `main()`
oficial y verifica la aplicación integrada con protección de acceso activa.
También comprueba que la generación Android no sustituye las fuentes ni el
lockfile. Los datos de prueba están aislados del inventario del usuario.

## Ejecutar y compilar Android

Este repositorio genera `flutter/android/`; no contiene un proyecto Android
versionado. En la primera preparación, con el entorno anterior activado:

```bash
python3 scripts/prepare_v122_android.py
cd flutter
flutter run --no-pub
# APK de prueba con la firma debug local, sin instalar ni modificar la clave estable:
flutter build apk --debug --no-pub
```

Se necesita SDK Android y Java compatibles para compilar o ejecutar. El script
conserva ambos puntos de entrada, pubspec y lockfile frente a `flutter create`,
quita solo la prueba de plantilla que acaba de generar e instala los canales
nativos existentes mediante `startup_android/install_startup.py`. Usa el mismo
identificador Android que el workflow integrado. Al terminar guarda en Android
un registro de integridad. En ejecuciones repetidas verifica ese registro,
identificador, arranque, canales, recursos y dependencias antes de reutilizar
el proyecto **sin escribir en él**. Permite cachés y salidas de compilación,
propiedades locales conocidas y wrappers que coincidan con el SDK Flutter activo.
Si faltan archivos, hay cambios o archivos inesperados, o no existe el registro,
se detiene sin reparar ni sobrescribir nada. Los proyectos generados anteriormente
y las modificaciones manuales de configuración o firma requieren revisión manual;
no se adoptan automáticamente.
Una generación fallida conserva las fuentes; revisa cualquier `android/` parcial
antes de reintentar, sin borrar una configuración anterior.

Para release local se necesita `--no-tree-shake-icons`, por los iconos dinámicos.
No utilices la firma debug local para sustituir una APK estable instalada.

## APK con firma estable en GitHub Actions

El workflow vigente es **Build Integrated Quill APK**
(`.github/workflows/build-integrated-quill-apk.yml`). Tras publicar cambios
revisados, selecciona en Actions **Run workflow** sobre `codex-desarrollo-v122`.
Compila `lib/main.dart`, valida pruebas, conserva la firma existente y comprueba
su certificado. El artefacto sigue siendo `gestor-quill-integrado-apk`.
Ejecutarlo o descargar un artefacto no modifica ni fusiona `main`.

## Flujos históricos

**Build Flutter APK** conserva su generación histórica con otro identificador
Android y sin los canales nativos de V122: no es el flujo de distribución V122.
Ahora rechaza explícitamente checkouts con `scripts/v122.sh` antes de preparar
Flutter o producir artefactos; las revisiones históricas sin ese marcador siguen
su procedimiento original.
Los workflows Kivy y Fleather siguen siendo históricos y no se modifican.
El código básico anterior de main.dart puede consultarse en Git en el commit
base `8baf7967041bb335e4ddbcb5ccb81f4de079c650`; no se duplica en otra aplicación.
V101, etiquetas, keystore, migraciones y esquema SQLite permanecen intactos.

La aplicación completa usa `dart:io` y canales Android. No se ofrece como una
aplicación Web compatible. Consulta [FLUTTER_WEB_MOVIL.md](FLUTTER_WEB_MOVIL.md)
y la [guía del entorno V122](docs/ENTORNO_V122.md).
