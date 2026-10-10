#!/usr/bin/env python3
"""Generate V122's native project without replacing its Dart entry points."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


PACKAGE = "org.gestorherramientas.gestor_herramientas_quill_test"
RECEIPT = ".v122-prepared.json"
NATIVE_FILES = ("MainActivity.kt", "ToolManagement.kt", "ButtonFeedback.kt",
                "ToolAi.kt", "StartupActivity.java")
RUNTIME_DIRS = {".gradle", ".kotlin", "build", "app/build", "app/.cxx",
                "app/.externalNativeBuild"}
WRAPPERS = ("gradlew", "gradlew.bat", "gradle/wrapper/gradle-wrapper.jar")
REQUIRED = ("settings.gradle.kts", "build.gradle.kts", "gradle.properties",
            "gradle/wrapper/gradle-wrapper.properties", "app/build.gradle.kts",
            "app/src/main/AndroidManifest.xml", "app/src/debug/AndroidManifest.xml",
            "app/src/profile/AndroidManifest.xml")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def native_sources(project):
    root = project / "startup_android"
    sources = {name: root / name for name in NATIVE_FILES}
    for path in (root / "res").rglob("*"):
        if path.is_file():
            sources[path.relative_to(root).as_posix()] = path
    return sources


def inputs(project):
    paths = {"install_startup.py": project / "startup_android/install_startup.py",
             "pubspec.yaml": project / "pubspec.yaml",
             "pubspec.lock": project / "pubspec.lock", **native_sources(project)}
    return {name: digest(path) for name, path in paths.items()}


def wrapper_hashes():
    executable = shutil.which("flutter")
    if not executable:
        return {}
    cache = Path(executable).resolve().parents[1] / "bin/cache/artifacts/gradle_wrapper"
    return {name: digest(cache / name) for name in WRAPPERS if (cache / name).is_file()}


def android_files(android):
    result = {}
    for directory, directories, files in os.walk(android):
        base = Path(directory)
        for name in list(directories):
            path = base / name
            relative = path.relative_to(android).as_posix()
            if path.is_symlink():
                raise RuntimeError(f"Enlace inesperado en Android: {relative}")
            if relative in RUNTIME_DIRS:
                directories.remove(name)
            elif not any(path.iterdir()):
                # Empty directories may be evidence of an incomplete/manual generation.
                raise RuntimeError(f"Directorio vacío inesperado en Android: {relative}")
        for name in files:
            path = base / name
            relative = path.relative_to(android).as_posix()
            if path.is_symlink() or not path.is_file():
                raise RuntimeError(f"Archivo inesperado en Android: {relative}")
            if relative == RECEIPT:
                continue
            if relative == "local.properties":
                allowed = {"sdk.dir", "flutter.sdk", "flutter.buildMode",
                           "flutter.versionName", "flutter.versionCode"}
                for line in path.read_text().splitlines():
                    if line.strip() and not line.lstrip().startswith(("#", "!")):
                        if line.partition("=")[0].strip() not in allowed:
                            raise RuntimeError("local.properties contiene claves inesperadas.")
                continue
            result[relative] = digest(path)
    return result


def verify_native(project, files):
    android = project / "android"
    for name in REQUIRED:
        if name not in files:
            raise RuntimeError(f"Generación Android incompleta: falta {name}")
    gradle = (android / "app/build.gradle.kts").read_text()
    if any(f'{key} = "{PACKAGE}"' not in gradle for key in ("namespace", "applicationId")):
        raise RuntimeError("Identificador Android incompatible con V122.")
    for name, source in native_sources(project).items():
        if name.startswith("res/"):
            target = "app/src/main/" + name
        else:
            language = "java" if name.endswith(".java") else "kotlin"
            target = f"app/src/main/{language}/{PACKAGE.replace('.', '/')}/{name}"
        if files.get(target) != digest(source):
            raise RuntimeError(f"Canal o recurso nativo incompleto o distinto: {target}")
    manifest = ET.parse(android / "app/src/main/AndroidManifest.xml").getroot()
    ns = "{http://schemas.android.com/apk/res/android}"
    application = manifest.find("application")
    launchers = []
    if application is not None:
        for activity in application.findall("activity"):
            for intent in activity.findall("intent-filter"):
                if any(item.get(ns + "name") == "android.intent.category.LAUNCHER"
                       for item in intent.findall("category")):
                    launchers.append(activity.get(ns + "name"))
    if launchers != [".StartupActivity"]:
        raise RuntimeError("El arranque nativo Android no corresponde a V122.")


def reuse(project):
    android = project / "android"
    receipt = android / RECEIPT
    if android.is_symlink() or not android.is_dir() or receipt.is_symlink() or not receipt.is_file():
        raise RuntimeError("android/ existe sin registro V122 verificable; requiere revisión manual.")
    try:
        saved = json.loads(receipt.read_text())
    except (ValueError, OSError) as error:
        raise RuntimeError("Registro Android V122 ilegible o incompleto.") from error
    if (not isinstance(saved, dict) or saved.get("version") != 1 or
            saved.get("application_id") != PACKAGE or not isinstance(saved.get("files"), dict)):
        raise RuntimeError("Registro Android incompatible con V122.")
    if saved.get("inputs") != inputs(project):
        raise RuntimeError("Dependencias o instalador nativo cambiaron; revisar Android manualmente.")
    actual = android_files(android)
    expected = saved["files"]
    wrappers = wrapper_hashes()
    # Flutter may add its wrapper on the first build, after flutter create --no-pub.
    for name in WRAPPERS:
        if name not in expected and name in actual and actual[name] == wrappers.get(name):
            actual.pop(name)
    if actual != expected:
        changed = sorted(name for name in set(actual) | set(expected)
                         if actual.get(name) != expected.get(name))
        raise RuntimeError("Android incompleto, modificado o con archivos inesperados: " + ", ".join(changed))
    verify_native(project, actual)
    print("Android V122 compatible: se reutiliza sin escribir ni regenerar archivos.")


def prepare(project):
    project = Path(project).resolve()
    preserved = ("pubspec.yaml", "pubspec.lock", "lib/main.dart",
                 "lib/main_quill_integrated_test.dart")
    for name in preserved:
        if not (project / name).is_file():
            raise RuntimeError(f"Falta {name}; no se generará Android.")
    installer = project / "startup_android/install_startup.py"
    if not installer.is_file():
        raise RuntimeError("Falta el instalador nativo V122.")
    inputs(project)  # Validate native inputs before creating or touching Android.
    if (project / "android").exists() or (project / "android").is_symlink():
        reuse(project)
        return
    template_test = project / "test/widget_test.dart"
    with tempfile.TemporaryDirectory(prefix="v122-android-") as temporary:
        backup = Path(temporary)
        originals = list(preserved)
        if template_test.exists():
            originals.append("test/widget_test.dart")
        for name in originals:
            target = backup / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(project / name, target)
        try:
            subprocess.run(["flutter", "create", ".", "--no-pub",
                            "--platforms=android",
                            "--project-name", "gestor_herramientas_quill_test",
                            "--org", "org.gestorherramientas"],
                           cwd=project, check=True)
        finally:
            for name in originals:
                shutil.copy2(backup / name, project / name)
            if "test/widget_test.dart" not in originals:
                template_test.unlink(missing_ok=True)
    manifest = project / "android/app/src/main/AndroidManifest.xml"
    manifest.write_text(manifest.read_text().replace(
        'android:label="gestor_herramientas_quill_test"',
        'android:label="Gestor Quill Integrado"'))
    # Existing native channels, package ID and startup behavior stay unchanged.
    subprocess.run([sys.executable, str(installer)], cwd=project, check=True)
    files = android_files(project / "android")
    verify_native(project, files)
    # Created only after generation and installation finish successfully. A partial
    # project has no receipt and is never automatically repaired or overwritten.
    with (project / "android" / RECEIPT).open("x") as receipt:
        json.dump({"version": 1, "application_id": PACKAGE,
                   "inputs": inputs(project), "files": files}, receipt, indent=2)
        receipt.write("\n")


if __name__ == "__main__":
    try:
        prepare(Path(__file__).resolve().parent.parent / "flutter")
    except (RuntimeError, OSError, ET.ParseError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Preparación Android detenida: {error}")
