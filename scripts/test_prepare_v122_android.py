"""Regression coverage for Android preservation, reuse and the historical workflow."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch

from prepare_v122_android import PACKAGE, RECEIPT, REQUIRED, native_sources, prepare


REPO = Path(__file__).resolve().parent.parent
PRESERVED = ("pubspec.yaml", "pubspec.lock", "lib/main.dart",
             "lib/main_quill_integrated_test.dart")


def write(project, name, content):
    path = project / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def fixture(project, existing_test=True):
    for name in PRESERVED:
        write(project, name, f"original {name}\n")
    if existing_test:
        write(project, "test/widget_test.dart", "original widget test\n")
    shutil.copytree(REPO / "flutter/startup_android", project / "startup_android",
                    ignore=shutil.ignore_patterns("__pycache__"))


def generate(project):
    for name in PRESERVED:
        write(project, name, "template\n")
    write(project, "test/widget_test.dart", "template test\n")
    for name in REQUIRED:
        write(project, "android/" + name, "generated\n")
    write(project, "android/app/build.gradle.kts",
          f'namespace = "{PACKAGE}"\napplicationId = "{PACKAGE}"\n')
    write(project, "android/app/src/main/AndroidManifest.xml", '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application android:label="gestor_herramientas_quill_test">
    <activity android:name=".StartupActivity"><intent-filter>
      <action android:name="android.intent.action.MAIN"/>
      <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter></activity>
  </application>
</manifest>''')


def install(project):
    for name, source in native_sources(project).items():
        if name.startswith("res/"):
            target = "android/app/src/main/" + name
        else:
            language = "java" if name.endswith(".java") else "kotlin"
            target = f"android/app/src/main/{language}/{PACKAGE.replace('.', '/')}/{name}"
        destination = project / target
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def fake_run(project):
    def run(command, **kwargs):
        if command[0] == "flutter":
            generate(project)
        else:
            install(project)
    return run


def snapshot(project):
    return {path.relative_to(project).as_posix(): (path.read_bytes(), path.stat().st_mtime_ns)
            for path in project.rglob("*") if path.is_file()}


class AndroidPreparationTest(unittest.TestCase):
    def test_template_generation_preserves_sources_lockfile_and_existing_test(self):
        for fail in (False, True):
            for existing_test in (False, True):
                with self.subTest(fail=fail, existing_test=existing_test), tempfile.TemporaryDirectory() as directory:
                    project = Path(directory)
                    fixture(project, existing_test)
                    originals = {name: (project / name).read_bytes() for name in PRESERVED}

                    def run(command, **kwargs):
                        if command[0] != "flutter":
                            install(project)
                            return
                        self.assertEqual(kwargs["cwd"], project)
                        self.assertIn("--no-pub", command)
                        self.assertIn("gestor_herramientas_quill_test", command)
                        self.assertIn("org.gestorherramientas", command)
                        generate(project)
                        if fail:
                            raise subprocess.CalledProcessError(1, command)

                    with patch("prepare_v122_android.subprocess.run", side_effect=run) as calls:
                        if fail:
                            with self.assertRaises(subprocess.CalledProcessError):
                                prepare(project)
                            self.assertFalse((project / "android" / RECEIPT).exists())
                        else:
                            prepare(project)
                            self.assertEqual(calls.call_count, 2)
                            self.assertTrue((project / "android" / RECEIPT).is_file())
                        for name, content in originals.items():
                            self.assertEqual((project / name).read_bytes(), content)
                        if existing_test:
                            self.assertEqual((project / "test/widget_test.dart").read_text(), "original widget test\n")
                        else:
                            self.assertFalse((project / "test/widget_test.dart").exists())

    def test_compatible_project_is_reused_without_any_writes_or_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / "project"
            fixture(project)
            with patch("prepare_v122_android.subprocess.run", side_effect=fake_run(project)):
                prepare(project)
            write(project, "android/local.properties", "sdk.dir=/sdk\nflutter.sdk=/flutter\n")
            write(project, "android/.gradle/cache/file", "build cache")
            write(project, "android/app/build/output", "build output")
            sdk = Path(directory) / "sdk"
            write(sdk, "bin/flutter", "sdk launcher")
            write(sdk, "bin/cache/artifacts/gradle_wrapper/gradlew", "sdk wrapper")
            write(project, "android/gradlew", "sdk wrapper")
            before = snapshot(project)
            with patch("prepare_v122_android.shutil.which", return_value=str(sdk / "bin/flutter")), \
                    patch("prepare_v122_android.subprocess.run") as run:
                prepare(project)
                prepare(project)
                run.assert_not_called()
            self.assertEqual(snapshot(project), before)

    def test_incomplete_modified_or_unexpected_projects_are_rejected_without_writes(self):
        for fault in ("missing", "identifier", "native", "unexpected", "receipt", "inputs",
                      "local_properties", "wrapper", "symlink", "empty_directory"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                project = Path(directory)
                fixture(project)
                with patch("prepare_v122_android.subprocess.run", side_effect=fake_run(project)):
                    prepare(project)
                if fault == "missing":
                    (project / "android/settings.gradle.kts").unlink()
                elif fault == "identifier":
                    write(project, "android/app/build.gradle.kts", "another package and signing")
                elif fault == "native":
                    write(project, f"android/app/src/main/kotlin/{PACKAGE.replace('.', '/')}/MainActivity.kt", "other channels")
                elif fault == "unexpected":
                    write(project, "android/private-notes.txt", "do not erase")
                elif fault == "receipt":
                    write(project, "android/" + RECEIPT, "{incomplete")
                elif fault == "inputs":
                    write(project, "pubspec.lock", "changed dependencies")
                elif fault == "local_properties":
                    write(project, "android/local.properties", "unexpected.setting=yes")
                elif fault == "wrapper":
                    write(project, "android/gradlew", "unexpected executable")
                elif fault == "symlink":
                    (project / "android/linked").symlink_to(project / "pubspec.lock")
                else:
                    (project / "android/unexpected-empty").mkdir()
                before = snapshot(project)
                with patch("prepare_v122_android.subprocess.run") as run:
                    with self.assertRaises(RuntimeError):
                        prepare(project)
                    run.assert_not_called()
                self.assertEqual(snapshot(project), before)
                if fault == "symlink":
                    self.assertTrue((project / "android/linked").is_symlink())

    def test_unregistered_existing_android_is_never_adopted_or_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            fixture(project)
            write(project, "android/config", "existing identifiers and signing")
            before = snapshot(project)
            with patch("prepare_v122_android.subprocess.run") as run:
                with self.assertRaisesRegex(RuntimeError, "sin registro"):
                    prepare(project)
                run.assert_not_called()
            self.assertEqual(snapshot(project), before)

    def test_installer_failure_leaves_no_receipt_and_cannot_be_reused(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            fixture(project)

            def run(command, **kwargs):
                if command[0] == "flutter":
                    generate(project)
                else:
                    raise subprocess.CalledProcessError(1, command)

            with patch("prepare_v122_android.subprocess.run", side_effect=run):
                with self.assertRaises(subprocess.CalledProcessError):
                    prepare(project)
            self.assertFalse((project / "android" / RECEIPT).exists())
            before = snapshot(project)
            with patch("prepare_v122_android.subprocess.run") as calls:
                with self.assertRaisesRegex(RuntimeError, "sin registro"):
                    prepare(project)
                calls.assert_not_called()
            self.assertEqual(snapshot(project), before)


class HistoricalWorkflowGuardTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = (REPO / ".github/workflows/build-flutter-apk.yml").read_text()
        guard = cls.workflow.split("- name: Reject V122 in the historical APK workflow", 1)[1]
        cls.code = textwrap.dedent(guard.split("python3 - <<'PY'\n", 1)[1].split("          PY", 1)[0])

    def execute_guard(self, v122):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "flutter").mkdir()
            write(root, "flutter/lib/main.dart", "historical main")
            if v122:
                write(root, "scripts/v122.sh", "V122 marker")
            return subprocess.run([sys.executable, "-c", self.code], cwd=root / "flutter",
                                  capture_output=True, text=True)

    def test_v122_is_rejected_even_if_the_old_main_is_selected(self):
        result = self.execute_guard(True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Build Integrated Quill APK", result.stderr)

    def test_historical_checkout_without_v122_marker_is_allowed(self):
        self.assertEqual(self.execute_guard(False).returncode, 0)

    def test_guard_runs_before_flutter_setup_generation_and_upload(self):
        position = self.workflow.index("- name: Reject V122")
        for step in ("- name: Set up Flutter", "- name: Generate Android project", "- name: Upload APK"):
            self.assertLess(position, self.workflow.index(step))


if __name__ == "__main__":
    unittest.main()
