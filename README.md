# Prueba Rich Text Kivy APK v2 — preparada para GitHub Actions

Este proyecto ya incluye un workflow de GitHub Actions que compila el APK por ti.

## Qué tienes que hacer

1. Crea un repositorio nuevo en GitHub.
2. Sube **todo el contenido de esta carpeta**, incluida la carpeta oculta:
   `.github/workflows/`
3. Abre la pestaña **Actions** del repositorio.
4. En la izquierda selecciona **Build Android APK**.
5. Pulsa **Run workflow**.
6. Espera a que termine la compilación.
   - La primera compilación puede tardar bastante porque descarga Android SDK/NDK.
7. Abre la ejecución terminada.
8. Al final de la página, en **Artifacts**, descarga:
   `richtext-kivy-apk`
9. Descomprime el ZIP descargado.
10. Dentro estará el archivo `.apk`.
11. Pásalo al teléfono e instálalo.

## Qué debes probar

En la app:

1. Escribe un nombre.
2. Pulsa **Editar formato**.
3. Comprueba que el editor se abre **dentro de la propia app**.
4. Prueba:
   - negrita;
   - cursiva;
   - subrayado;
   - tachado;
   - color de texto;
   - color de fondo/resaltado;
   - tamaño;
   - alineación;
   - listas.
5. Pulsa **GUARDAR**.
6. Debe cerrarse el editor y volver a la pantalla Kivy.
7. Pulsa **Guardar artículo**.

## Archivos importantes

- `main.py`: aplicación de prueba.
- `buildozer.spec`: configuración Android.
- `.github/workflows/build-apk.yml`: compilación automática.
- `README.md`: estas instrucciones.

## Si Actions falla

Abre la ejecución fallida y entra en el paso rojo **Build debug APK**.
Copia las últimas líneas del error y tráelas al chat. Con eso podremos corregir
el `buildozer.spec` o el workflow sin adivinar.
