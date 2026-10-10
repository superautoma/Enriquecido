# Gestor de Herramientas — Seguridad local con un único propietario

## Alcance

La protección de acceso es **local** y es independiente del proyecto de nube/sincronización, que permanece aplazado.

- Primera activación voluntaria desde «⋮ → Seguridad y acceso» para no bloquear instalaciones existentes al actualizar.
- Nombre de usuario + contraseña (mínimo 10 caracteres) como acceso principal y alternativa permanente.
- PIN local de al menos seis cifras, patrón de al menos cuatro nodos en una cuadrícula 3×3, huella nativa Android opcional.
- Bloqueo manual e inactividad en segundo plano configurable (0, 1, 5 o 15 minutos).
- Verificación mediante PBKDF2-HMAC-SHA256 con sales aleatorias y almacenamiento de verificadores dentro de Android Keystore / almacenamiento seguro del complemento.
- Limitación de intentos fallidos de acceso; no borrar herramientas al fallar.
- Los cambios de contraseñas, métodos y biometría requieren verificar la contraseña actual.
- No requiere Internet ni modifica el archivo SQLite, las fotografías ni los préstamos.

## Límites importantes

La pantalla de bloqueo no cifra la base SQLite ni las copias externas. El propietario debe proteger el teléfono a nivel Android. Sin servidor ni correo no hay recuperación remota de la contraseña. Se debe conservar una copia externa del inventario antes de probar modificaciones.

## Comprobaciones pendientes

1. Ejecutar `flutter pub get`, `flutter analyze` y `flutter test` en CI.
2. Compilar y verificar firma estable de la APK.
3. Probar PIN, patrón, cancelación de la huella, reanudar desde segundo plano, contraseña errónea, desinstalación/reinstalación y actualización con SQLite real.
4. No unir a rama estable hasta validar los puntos anteriores.
