# Development Android signing key

This repository uses a fixed **development-only** Android debug signing key so APKs built by GitHub Actions can be installed as updates without changing the app signature.

It is intentionally not a production signing key and must never be used for a Play Store or production release.

Current test application id:
`org.gestorherramientas.gestor_herramientas_quill_test`
