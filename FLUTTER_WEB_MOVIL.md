# Ejecución de V122 y antiguo flujo Web

Las instrucciones anteriores de `Flutter Web móvil`, el servidor en el puerto
3000 y `flutter create --platforms=web` correspondían a la aplicación básica
antigua de `lib/main.dart`. No ejecutaban el Gestor V122 completo.

Ahora `lib/main.dart` delega en la aplicación integrada. Esta usa `dart:io`,
SQLite y canales nativos Android; no se ha portado a Web. No utilices el servidor
Web como validación de V122 ni asumas que funciona en el navegador.

La configuración de desarrollo genera Android con
`scripts/prepare_v122_android.py` y la tarea de VS Code **Flutter V122 (dispositivo
Android)** ejecuta `flutter run --no-pub` desde `flutter/`. Requiere dispositivo
Android/emulador conectado y SDK disponible; Codespaces no aporta por sí mismo
un teléfono o emulador. Activa antes `source scripts/v122-env.sh` en esa terminal.

Para generar una APK, sigue el [README de V122](README.md). La compilación con
firma estable sigue en **Build Integrated Quill APK**, seleccionando la rama V122.
No hace falta modificar `main` de GitHub ni utilizar los workflows históricos.
