"""Check the Android startup overlay hands off to Flutter and back navigation works."""
import pathlib
import re
import subprocess
import time
import xml.etree.ElementTree as ET

package = "org.gestorherramientas.gestor_herramientas_quill_test"
output = pathlib.Path("startup-check")
output.mkdir(exist_ok=True)


def adb(*args):
    return subprocess.check_output(["adb", *args], timeout=35)


def screenshot(name):
    (output / name).write_bytes(adb("exec-out", "screencap", "-p"))


def wait_for(label):
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        try:
            adb("shell", "uiautomator", "dump", "/sdcard/startup-window.xml")
            xml = adb("shell", "cat", "/sdcard/startup-window.xml").decode()
            (output / "window.xml").write_text(xml)
            root = ET.fromstring(xml)
            for node in root.iter("node"):
                text = node.get("text", "") + node.get("content-desc", "")
                if label in text:
                    return node
        except (subprocess.SubprocessError, ET.ParseError):
            pass
        time.sleep(1)
    screenshot("startup-failed.png")
    raise AssertionError(f"Android did not display {label!r}")


adb("install", "-r", "build/app/outputs/flutter-apk/app-debug.apk")
adb("shell", "am", "force-stop", package)
adb("shell", "am", "start", "-n", f"{package}/.MainActivity")
screenshot("startup-first-frame.png")
item = wait_for("Destornillador aislado")
screenshot("startup-ready.png")
coords = [int(value) for value in re.findall(r"\d+", item.attrib["bounds"])]
adb("shell", "input", "tap", str((coords[0] + coords[2]) // 2),
    str((coords[1] + coords[3]) // 2))
wait_for("Editar artículo")
adb("shell", "input", "keyevent", "4")
wait_for("Mis herramientas")
print("Android startup, Flutter handoff and editor back navigation passed.")
