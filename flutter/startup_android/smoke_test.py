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


def tap(label):
    node = wait_for(label)
    tap_node(node)


def tap_node(node):
    coords = [int(value) for value in re.findall(r"\d+", node.attrib["bounds"])]
    adb("shell", "input", "tap", str((coords[0] + coords[2]) // 2),
        str((coords[1] + coords[3]) // 2))


def tap_field(index):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        adb('shell', 'uiautomator', 'dump', '/sdcard/startup-window.xml')
        root = ET.fromstring(adb('shell', 'cat', '/sdcard/startup-window.xml').decode())
        fields = [node for node in root.iter('node')
                  if node.get('class') == 'android.widget.EditText'
                  and node.get('package') == package]
        if len(fields) > index:
            tap_node(fields[index])
            return
        time.sleep(0.5)
    raise AssertionError(f'Loan field {index} not found')


adb("install", "-r", "build/app/outputs/flutter-apk/app-release.apk")
adb("shell", "am", "force-stop", package)
adb("shell", "am", "start", "-n", f"{package}/.StartupActivity")
screenshot("startup-first-frame.png")
item = wait_for("Destornillador aislado")
screenshot("startup-ready.png")
coords = [int(value) for value in re.findall(r"\d+", item.attrib["bounds"])]
adb("shell", "input", "tap", str((coords[0] + coords[2]) // 2),
    str((coords[1] + coords[3]) // 2))
wait_for("Editar artículo")
tap('Selecciona el tipo')
tap('Herramienta manual')
loan_icon = wait_for("Disponible: prestar herramienta")
screenshot("editor-loan-icon.png")
coords = [int(value) for value in re.findall(r"\d+", loan_icon.attrib["bounds"])]
adb("shell", "input", "tap", str((coords[0] + coords[2]) // 2),
    str((coords[1] + coords[3]) // 2))
wait_for("Disponible para préstamo")
screenshot("loan-options-open.png")
tap("Prestar")
wait_for('Prestar herramienta')
tap_field(0)
adb("shell", "input", "text", "Pedro")
adb("shell", "input", "keyevent", "4")
tap_field(1)
adb("shell", "input", "text", "Con%scargador")
adb("shell", "input", "keyevent", "4")
tap("Confirmar préstamo")
wait_for("Mis herramientas")
tap("Destornillador aislado")
tap("Prestada: ver préstamo")
tap("Editar préstamo")
wait_for("Con cargador")
tap_field(1)
adb("shell", "input", "keyevent", "KEYCODE_MOVE_END")
adb("shell", "input", "text", "%sy%sbateria")
adb("shell", "input", "keyevent", "4")
tap("Guardar cambios")
wait_for("Editar artículo")
tap("Prestada: ver préstamo")
wait_for("Con cargador y bateria")
screenshot("loan-edited.png")
adb("shell", "input", "keyevent", "4")
wait_for("Editar artículo")
adb("shell", "input", "keyevent", "4")
wait_for("Mis herramientas")
print("Android startup, loan creation, editing persistence and back navigation passed.")
