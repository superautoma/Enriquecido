# Guardar versiones estables del Gestor de Herramientas

Cuando Pedro confirme que una APK funciona en su movil, ejecutar el workflow
**Guardar version estable de Herramientas**. No basta con que la compilacion
termine: la confirmacion corresponde a la APK probada y a su numero concreto.

1. Abrir https://github.com/superautoma/Enriquecido/actions/workflows/save-stable-tools.yml
2. Pulsar **Run workflow**, dejando la rama **main**.
3. Indicar el numero de la APK probada: por ejemplo, **101** para Build Integrated
   Quill APK #101. El numero del workflow de comprobacion es diferente.
4. Marcar **He probado esta APK en mi movil y funciona correctamente**.
5. Desmarcar **Solo comprobar, sin guardar ni publicar** y ejecutar.

El resto es automatico: selecciona la compilacion exacta, comprueba las pruebas,
descarga la APK original y verifica que conserva el certificado de V101 y el
identificador Android. Crea una etiqueta anotada `gestor-herramientas-vNNN` en el
commit que genero esa APK y una publicacion con la APK, `SHA256SUMS.txt` y
`version-estable.json`. GitHub ofrece el codigo fuente asociado a la etiqueta.

No modifica codigo Flutter, SQLite, fotografias, claves de firma o identificador
Android. No genera ni instala APK. Las etiquetas existentes nunca se mueven;
la V101 se mantiene en `4c3be14d0cc411c3fd2598dcd88c8ddc2e426264`.
Las publicaciones iguales se reconocen y no se sobrescriben. Una transferencia
interrumpida deja un borrador que puede completarse repitiendo la ejecucion.

Las APK de Actions caducan a los 14 dias en el workflow actual. Guardar la
version antes de que caduque su artefacto. Si ya ha caducado, el proceso se
detiene: una nueva compilacion no sustituye el binario que se probo.
Las publicaciones conservan los archivos hasta que alguien los elimine.

## Verificar sin guardar

Dejar marcada **Solo comprobar, sin guardar ni publicar**. Se ejecutan las
verificaciones y la descarga, sin crear etiquetas ni publicaciones. Cada cambio
en este sistema ejecuta ademas sus pruebas, sin recompilar la aplicacion.

## Permisos de GitHub

El workflow usa `GITHUB_TOKEN` con `contents: write` y `actions: read`. Si GitHub
rechaza crear una etiqueta/publicacion porque el commit de la APK tiene workflows
diferentes a los de main, el token automatico puede no ser suficiente. En ese
caso configurar el secreto de Actions **STABLE_RELEASE_TOKEN**, restringido a
este repositorio, con Contents y Workflows de escritura y Actions de lectura
(o un token clasico con el alcance workflow y acceso al repositorio). Se usa
automaticamente si existe. No guardar ni enviar el token por el chat ni en el
codigo. Los errores de permisos detienen el proceso; no se ignoran.

Referencia: https://docs.github.com/en/rest/releases/releases#create-a-release

## Datos del movil

Este sistema conserva codigo y APK. Para conservar las herramientas reales y
sus fotografias, usar **Gestion de base de datos → Crear copia** en la app y
guardar esa copia externamente. Nunca subir inventario personal a una Release.
