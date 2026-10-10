# Entorno de desarrollo del Gestor de Herramientas V122

Esta guía prepara el entorno de desarrollo sin cambiar el código de la aplicación,
Flutter Quill, datos de usuario ni referencias estables. Está dirigida a Linux
x86-64. Las rutas son configurables: no se necesita un directorio temporal ni
una ubicación concreta de Codex para desarrollar.

## Referencia y versiones

- Repositorio: `https://github.com/superautoma/Enriquecido.git`.
- Rama: `codex-desarrollo-v122`.
- Commit de recuperación: `e49dd4af326c60e64d64450e73cc20fa0d0984a0`.
- Flutter: **3.44.0 stable**, revisión
  `559ffa3f75e7402d65a8def9c28389a9b2e6fe42`.
- Dart incluido: **3.12.0**, arquitectura x64. No instalar otro Dart aparte.
- SQLite validado en esta recuperación: **3.46.1**, biblioteca compartida x86-64.
- `flutter/pubspec.lock`: resolución generada y validada durante esta sesión, con 147
  paquetes. No se encontró el lockfile anterior; no se puede asegurar que sus
  versiones fueran iguales. Conservar este lockfile para futuras sesiones.

Trabajar en una copia independiente si existe otra versión del proyecto:

```bash
git clone --single-branch --branch codex-desarrollo-v122 \
  https://github.com/superautoma/Enriquecido.git Enriquecido-v122
git -C Enriquecido-v122 rev-parse HEAD
```

Comparar el SHA con la referencia de recuperación. En sesiones posteriores la
rama puede haber avanzado legítimamente; verificar el commit previsto sin
restablecer, limpiar ni reemplazar trabajo existente.

## Descargar y verificar el SDK

Desde la raíz de la copia, elegir una carpeta escribible **fuera del repositorio**.
Se necesitan Bash, curl, tar con soporte xz, Python 3 y las herramientas Linux
usadas más abajo (`realpath`, `sha256sum`, `ldconfig`, `file`, `ldd` y `rg`).
El siguiente ejemplo utiliza una carpeta hermana; puede elegirse otra ubicación:

```bash
export V122_TOOLCHAINS="$(realpath -m ../toolchains-v122)"
mkdir -p "$V122_TOOLCHAINS"
uname -m  # Esta descarga requiere x86_64.
curl --fail --location --show-error \
  https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json \
  -o "$V122_TOOLCHAINS/releases_linux.json"
```

Seleccionar en el manifiesto `version: 3.44.0`, `channel: stable`,
`dart_sdk_arch: x64` y comprobar `dart_sdk_version: 3.12.0`.
El archivo oficial es `stable/linux/flutter_linux_3.44.0-stable.tar.xz`.
Su SHA256 publicado y verificado en esta recuperación es:

```text
e1ec95e6c550458a34de93580cb85dac24da0e9bedb9bb42811f050ac5a0c7d5
```

```bash
curl --fail --location --show-error \
  https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.44.0-stable.tar.xz \
  -o "$V122_TOOLCHAINS/flutter_linux_3.44.0-stable.tar.xz"
printf '%s  %s\n' \
  e1ec95e6c550458a34de93580cb85dac24da0e9bedb9bb42811f050ac5a0c7d5 \
  "$V122_TOOLCHAINS/flutter_linux_3.44.0-stable.tar.xz" | sha256sum --check
```

Extraer solamente después de comprobar la integridad. Si ya existe `flutter`,
verificar su versión y reutilizarlo; no sobrescribir una instalación existente.

```bash
if [ ! -e "$V122_TOOLCHAINS/flutter" ]; then
  tar -xJf "$V122_TOOLCHAINS/flutter_linux_3.44.0-stable.tar.xz" \
    -C "$V122_TOOLCHAINS"
fi
```

## Usuario, configuración y cachés

Dart usa `HOME` en Linux para inicializar `.dart-tool` y la configuración de su
servidor de análisis. Si el directorio de usuario del ejecutor es de solo lectura,
`XDG_CONFIG_HOME` por sí solo no evita el error. Crear un directorio de usuario
de desarrollo escribible, sin cambiar permisos ni configuraciones del sistema.

Guardar el siguiente contenido en `enriquecido-env.sh` dentro de la carpeta de
toolchains elegida. Antes de cargarlo, definir `V122_TOOLCHAINS` con su ubicación
absoluta. Esta plantilla conserva proxy, certificados y rutas de bibliotecas
preexistentes; no contiene credenciales.

```bash
: "${V122_TOOLCHAINS:?Define la carpeta absoluta de toolchains}"
export ENRIQUECIDO_USER_HOME="$V122_TOOLCHAINS/home"
export HOME="$ENRIQUECIDO_USER_HOME"
export FLUTTER_ROOT="$V122_TOOLCHAINS/flutter"
export PUB_CACHE="$V122_TOOLCHAINS/pub-cache-v122"
export XDG_CONFIG_HOME="$V122_TOOLCHAINS/config-v122"
export XDG_CACHE_HOME="$ENRIQUECIDO_USER_HOME/.cache"
export ENRIQUECIDO_LIB_DIR="$V122_TOOLCHAINS/lib"
mkdir -p "$HOME" "$PUB_CACHE" "$XDG_CONFIG_HOME" \
  "$XDG_CACHE_HOME" "$ENRIQUECIDO_LIB_DIR"
case ":$PATH:" in
  *":$FLUTTER_ROOT/bin:"*) ;;
  *) export PATH="$FLUTTER_ROOT/bin:$PATH" ;;
esac
case ":${LD_LIBRARY_PATH:-}:" in
  *":$ENRIQUECIDO_LIB_DIR:"*) ;;
  *) export LD_LIBRARY_PATH="$ENRIQUECIDO_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
esac
```

Activar y verificar las versiones; repetir la activación en cada terminal:

```bash
source "$V122_TOOLCHAINS/enriquecido-env.sh"
flutter --version
dart --version
```

La activación configura el usuario para esa terminal y sus procesos hijos.
Debe hacerse antes de ejecutar Flutter; no requiere editar perfiles del sistema.

## SQLite local

`sqflite_common_ffi 2.3.7+1` usa `sqlite3 2.9.4`, que en Linux intenta abrir
`libsqlite3.so`. El entorno recuperado tenía `libsqlite3.so.0`, pero carecía del
alias sin versión. Esto produjo 69 fallos de pruebas.

Localizar la biblioteca existente y comprobar su arquitectura y dependencias:

```bash
ldconfig -p | rg 'libsqlite3\.so'
```

Asignar la ruta encontrada a `V122_SQLITE_LIBRARY`; no asumir que la ubicación
de esta máquina existe en otra. Comprobarla con `file` y `ldd`. Si falta una
biblioteca compatible, detener la preparación y proporcionar SQLite mediante
la imagen base o una instalación local verificada; no cambiar permisos del sistema.

```bash
: "${V122_SQLITE_LIBRARY:?Define la ruta de la biblioteca SQLite existente}"
file "$(readlink -f "$V122_SQLITE_LIBRARY")"
ldd "$(readlink -f "$V122_SQLITE_LIBRARY")"
mkdir -p "$V122_TOOLCHAINS/lib"
if [ ! -e "$V122_TOOLCHAINS/lib/libsqlite3.so" ] && \
   [ ! -L "$V122_TOOLCHAINS/lib/libsqlite3.so" ]; then
  ln -s "$(readlink -f "$V122_SQLITE_LIBRARY")" \
    "$V122_TOOLCHAINS/lib/libsqlite3.so"
fi
readlink -f "$V122_TOOLCHAINS/lib/libsqlite3.so"
python3 - <<'PY'
import ctypes
library = ctypes.CDLL('libsqlite3.so')
library.sqlite3_libversion.restype = ctypes.c_char_p
print(library.sqlite3_libversion().decode())
PY
```

El enlace es local y utiliza `LD_LIBRARY_PATH` de la activación. Si ya existe,
comprobar su destino antes de reutilizarlo; no reemplazarlo automáticamente.
La comprobación de carga no abre ni modifica bases de datos.

## Dependencias y validación

Guardar el hash del lockfile antes y después de preparar los paquetes:

```bash
cd flutter
sha256sum pubspec.lock
flutter pub get --enforce-lockfile
sha256sum pubspec.lock
flutter analyze --no-fatal-infos
flutter test
```

`--enforce-lockfile` permite detenerse si la resolución exige cambios al lockfile.
No ejecutar `pub upgrade`, sustituir dependencias ni aceptar un nuevo lockfile
sin revisar el motivo. `.gitignore` excluye los directorios `.dart_tool`, `build`
y el archivo `.flutter-plugins-dependencies`; no excluye `flutter/pubspec.lock`,
que se versiona para fijar las dependencias validadas.

`analysis_options.yaml` excluye solamente `lib/richtext_appflowy_test.dart` y
`lib/richtext_fleather_test.dart`: son prototipos históricos, conservados en el
repositorio, anteriores al editor actual con Flutter Quill. No se necesitan sus
paquetes para la aplicación actual. El workflow manual
`.github/workflows/build-richtext-test-apk.yml` conserva el experimento Fleather,
pero no puede compilarlo con las dependencias actuales. Se conserva sin cambios.

Referencia de validación: 0 errores, 0 advertencias y 13 avisos informativos de
imports innecesarios; 221 pruebas aprobadas, 0 fallidas y 0 omitidas. Las pruebas
usan sus propios datos de prueba; no apuntarlas a inventarios reales.

## Investigar el fallo intermitente de eliminación de grupos

La prueba `Create, rename and delete a group through its page` de
`test/icon_groups_favorites_test.dart` falló una vez al seguir encontrando
«Medición» tras borrarlo. Su helper `finish()` espera 100 ms y después ejecuta
`pumpAndSettle()`. El borrado persiste un archivo con `flush: true`, renombra el
archivo y actualiza el estado; una espera fija no garantiza que todo el trabajo
de E/S haya terminado. Es una hipótesis de temporización, no una causa demostrada.

Para repetir sin cambiar la lógica, ejecutar varias veces:

```bash
flutter test --no-pub test/icon_groups_favorites_test.dart \
  --plain-name 'Create, rename and delete a group through its page' \
  --reporter expanded
```

Durante la consolidación se ejecutó esta prueba en diez procesos independientes:
10 ejecuciones aprobadas, 0 fallidas y 0 omitidas. No se reprodujo el fallo; esto
no demuestra que se haya eliminado su posible causa. Su lógica permanece intacta.

Registrar cada ejecución, incluyendo los fallos. Comparar también la suite
completa y el archivo de grupos completo: un resultado aislado correcto no
descarta interferencias o sensibilidad a la carga. No aumentar esperas ni
modificar pruebas o funcionalidades como parte de la preparación del entorno.

## Propuesta de automatización en futuras sesiones de Codex Cloud

La automatización queda propuesta; esta recuperación no añade un instalador ni
cambia la configuración Cloud o workflows. Un script de preparación idempotente
podría implementar los pasos anteriores con estos parámetros:

- Carpeta de toolchains escribible y ruta del repositorio, ambas configurables.
- Flutter 3.44.0 y hash fijados; verificar el manifiesto, archivo, arquitectura y
  Dart incluido. Reutilizar instalaciones correctas sin sobrescribir otras.
- Usuario y cachés dentro de toolchains; generar la activación sin credenciales.
- Descubrir SQLite, validar su carga y crear el alias local solo si es necesario.
- Obtener paquetes con el lockfile obligatorio; comprobar que su hash no cambia.
- Ejecutar análisis y pruebas, guardar resultados y devolver estado de error ante
  cualquier fallo. Nunca restablecer código, mezclar ramas ni crear commits.

Configurar ese script, tras revisión, como preparación del entorno Cloud y
mantener una imagen Linux x86-64 con SQLite disponible. Las cachés de SDK y
paquetes se pueden conservar para reducir descargas; no confiar en que una ruta
o caché de una sesión anterior siga existiendo. Cada terminal debe activar el
entorno, pues las exportaciones del proceso de preparación pueden no heredarse.

En Codex Cloud los comandos de red necesitan el permiso de red del ejecutor.
Conservar el proxy y la validación TLS heredados. La política debe permitir los
hosts oficiales usados por GitHub, `storage.googleapis.com` y `pub.dev`, además
de los destinos concretos de los paquetes bloqueados. Si hay una denegación,
revisar la configuración y permisos del entorno; no quitar el proxy, alterar
certificados ni desactivar TLS. No incrustar tokens en scripts, documentación
ni archivos del repositorio.
