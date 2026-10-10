#!/usr/bin/env python3
"""Preparación Linux x64 de V122. Solo escribe SDK, cachés y artefactos locales."""

import ctypes
import ctypes.util
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile


FLUTTER = "3.44.0"
DART = "3.12.0"
REVISION = "559ffa3f75e7402d65a8def9c28389a9b2e6fe42"
SHA256 = "e1ec95e6c550458a34de93580cb85dac24da0e9bedb9bb42811f050ac5a0c7d5"
ARCHIVE = "stable/linux/flutter_linux_3.44.0-stable.tar.xz"
BASE = "https://storage.googleapis.com/flutter_infra_release/releases"
REPO = Path(__file__).resolve().parent.parent


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def output(*command):
    return subprocess.check_output(command, text=True).strip()


def download(url, destination):
    # curl conserva proxy y CA heredados. No lee un .curlrc que altere TLS.
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as file:
        temporary = Path(file.name)
    try:
        subprocess.run([
            "curl", "--disable", "--fail", "--location", "--show-error", "--silent",
            "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "30",
            url, "--output", str(temporary),
        ], check=True)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def validate_sdk(sdk):
    require((sdk / "bin/flutter").is_file(), f"SDK incompleto: {sdk}")
    require(output("git", "-C", str(sdk), "rev-parse", "HEAD") == REVISION,
            f"Revisión de Flutter incompatible en {sdk}; no se sobrescribe.")
    # El primer uso con un HOME nuevo añade un aviso de Flutter tras el JSON.
    versions, _ = json.JSONDecoder().raw_decode(
        output(str(sdk / "bin/flutter"), "--version", "--machine").lstrip())
    require(versions["frameworkVersion"] == FLUTTER and
            versions["dartSdkVersion"] == DART and versions["channel"] == "stable",
            f"Versiones incompatibles en {sdk}; no se sobrescribe.")
    dart = output(str(sdk / "bin/cache/dart-sdk/bin/dart"), "--version")
    require(f"Dart SDK version: {DART} " in dart and '"linux_x64"' in dart,
            "El Dart incluido no coincide con 3.12.0 Linux x64.")
    print(f"Flutter {FLUTTER}, Dart {DART}, Linux x64: {sdk}", flush=True)


def prepare_sdk(state):
    explicit = os.environ.get("V122_FLUTTER_ROOT")
    managed = state / "flutter"
    candidates = []
    if explicit:
        candidates.append(Path(explicit).resolve())
    elif managed.exists() or managed.is_symlink():
        candidates.append(managed)
    else:
        record = state / "sdk-path"
        if record.is_file():
            candidates.append(Path(record.read_text().strip()))
        executable = shutil.which("flutter")
        if executable:
            candidates.append(Path(executable).resolve().parent.parent)
    for sdk in candidates:
        if explicit or sdk == managed:
            validate_sdk(sdk)
            return sdk
        # Un SDK ajeno incompatible en PATH se conserva; se instala uno local.
        try:
            revision = subprocess.check_output(
                ["git", "-C", str(sdk), "rev-parse", "HEAD"], text=True,
                stderr=subprocess.DEVNULL).strip()
            if revision == REVISION:
                validate_sdk(sdk)
                return sdk
        except (OSError, subprocess.CalledProcessError):
            continue

    downloads = state / "downloads"
    downloads.mkdir(exist_ok=True)
    manifest = downloads / "releases_linux.json"
    download(f"{BASE}/releases_linux.json", manifest)
    releases = json.loads(manifest.read_text())["releases"]
    matches = [r for r in releases if r.get("version") == FLUTTER and
               r.get("channel") == "stable" and r.get("dart_sdk_arch") == "x64"]
    require(len(matches) == 1, "El manifiesto no contiene una única versión esperada.")
    release = matches[0]
    require(release.get("dart_sdk_version") == DART and release.get("hash") == REVISION
            and release.get("archive") == ARCHIVE and release.get("sha256") == SHA256,
            "El manifiesto oficial difiere de las versiones o del SHA256 fijados.")
    archive = downloads / Path(ARCHIVE).name
    if not archive.exists():
        download(f"{BASE}/{ARCHIVE}", archive)
    require(digest(archive) == SHA256,
            f"SHA256 incorrecto: {archive}. Se conserva para diagnóstico; no se extrae.")
    print(f"SHA256 oficial comprobado: {SHA256}", flush=True)
    # Extraer en staging; no dejar una instalación parcial ni reemplazar otro SDK.
    with tempfile.TemporaryDirectory(prefix="extract-", dir=state) as staging:
        with tarfile.open(archive, "r:xz") as tar:
            tar.extractall(staging, filter="data")
        sdk = Path(staging) / "flutter"
        validate_sdk(sdk)
        require(not managed.exists() and not managed.is_symlink(),
                "Ya existe un SDK local; no se reemplaza.")
        sdk.rename(managed)
    return managed


def sqlite_version(path):
    library = ctypes.CDLL(str(path))
    library.sqlite3_libversion.restype = ctypes.c_char_p
    # Símbolos requeridos por sqlite3 2.x. No abre bases de datos.
    for symbol in ("sqlite3_open_v2", "sqlite3_close_v2", "sqlite3_prepare_v2"):
        getattr(library, symbol)
    return library.sqlite3_libversion().decode()


def prepare_sqlite(state):
    alias = state / "lib/libsqlite3.so"
    explicit = os.environ.get("V122_SQLITE_LIBRARY")
    if alias.exists() or alias.is_symlink():
        require(not explicit or alias.resolve() == Path(explicit).resolve(),
                "El alias SQLite existente difiere del solicitado; no se reemplaza.")
        version = sqlite_version(alias)
    else:
        paths = [explicit] if explicit else []
        if not explicit:
            ldconfig = shutil.which("ldconfig")
            if ldconfig:
                paths.extend(line.split("=>", 1)[1].strip()
                             for line in output(ldconfig, "-p").splitlines()
                             if "libsqlite3.so" in line and "=>" in line)
            found = ctypes.util.find_library("sqlite3")
            if found and Path(found).is_absolute():
                paths.append(found)
        selected = None
        for candidate in paths:
            path = Path(candidate).resolve()
            if not path.is_file():
                continue
            try:
                version = sqlite_version(path)
                selected = path
                break
            except (OSError, AttributeError):
                continue
        require(selected is not None,
                "No hay SQLite compatible. Proporciona V122_SQLITE_LIBRARY o una imagen "
                "con SQLite; no se instalan bibliotecas del sistema.")
        alias.symlink_to(selected)
    print(f"SQLite {version}: {alias} -> {alias.resolve()}", flush=True)


def prepare(state):
    require(platform.system() == "Linux" and platform.machine() == "x86_64",
            "Este instalador fija Flutter para Linux x86_64 exclusivamente.")
    sdk = prepare_sdk(state)
    prepare_sqlite(state)
    (state / "sdk-path").write_text(str(sdk) + "\n")


def dependencies(project):
    lock = project / "pubspec.lock"
    require(lock.is_file(), "Falta pubspec.lock; no se resolverán dependencias nuevas.")
    before = digest(lock)
    result = subprocess.run(["flutter", "pub", "get", "--enforce-lockfile"], cwd=project)
    require(lock.is_file() and digest(lock) == before,
            "pubspec.lock cambió inesperadamente. Detenerse y revisar el diff; no restaurar trabajo.")
    require(result.returncode == 0, "pub get falló; no se ejecutará pub upgrade ni se sustituirá el lockfile.")
    print(f"pubspec.lock conservado: {before}", flush=True)


def check(project, state):
    logs = state / "logs"
    logs.mkdir(exist_ok=True)
    with (logs / "analyze.log").open("w") as log:
        analysis = subprocess.run(["flutter", "analyze", "--no-pub", "--no-fatal-infos"],
                                  cwd=project, stdout=log, stderr=subprocess.STDOUT)
    print((logs / "analyze.log").read_text(), end="", flush=True)
    with (logs / "test.jsonl").open("w") as log, (logs / "test.stderr.log").open("w") as err:
        tests = subprocess.run(["flutter", "test", "--no-pub", "--reporter", "json"],
                               cwd=project, stdout=log, stderr=err)
    counts = {"passed": 0, "failed": 0, "skipped": 0}
    done = False
    for line in (logs / "test.jsonl").read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get("type") == "testDone" and not event.get("hidden", False):
            key = "skipped" if event.get("skipped") else (
                "passed" if event.get("result") == "success" else "failed")
            counts[key] += 1
        elif event.get("type") == "done":
            done = event.get("success", False)
    summary = {"analysis_exit": analysis.returncode, "test_exit": tests.returncode, **counts}
    (logs / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    print(f"Resultados completos: {logs}", flush=True)
    require(analysis.returncode == 0 and tests.returncode == 0 and done and
            counts == {"passed": 221, "failed": 0, "skipped": 0},
            "La validación no coincide con 221 aprobadas, 0 fallidas y 0 omitidas; revisar logs.")


def main():
    require(sys.version_info >= (3, 12), "Se necesita Python 3.12 o posterior.")
    mode = sys.argv[1] if len(sys.argv) == 2 else ""
    require(mode in ("prepare", "setup", "check"), "Usar scripts/v122.sh setup|check.")
    state = Path(os.environ["V122_STATE_DIR"]).resolve()
    with (state / "setup.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if mode == "prepare":
            prepare(state)
        else:
            # Confirmar que el loader usado por las pruebas encuentra el alias local.
            print(f"SQLite cargado mediante LD_LIBRARY_PATH: {sqlite_version('libsqlite3.so')}",
                  flush=True)
            dependencies(REPO / "flutter")
            if mode == "check":
                check(REPO / "flutter", state)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.CalledProcessError,
            tarfile.TarError) as error:
        print(f"Preparación V122 detenida: {error}", file=sys.stderr)
        sys.exit(1)
