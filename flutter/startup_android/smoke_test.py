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


def wait_for(label, exclude_class=None):
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        try:
            adb("shell", "uiautomator", "dump", "/sdcard/startup-window.xml")
            xml = adb("shell", "cat", "/sdcard/startup-window.xml").decode()
            (output / "window.xml").write_text(xml)
            root = ET.fromstring(xml)
            for node in root.iter("node"):
                text = node.get("text", "") + node.get("content-desc", "")
                if label in text and node.get('class') != exclude_class:
                    return node
        except (subprocess.SubprocessError, ET.ParseError):
            pass
        time.sleep(1)
    screenshot("startup-failed.png")
    raise AssertionError(f"Android did not display {label!r}")


def tap(label, exclude_class=None):
    node = wait_for(label, exclude_class=exclude_class)
    tap_node(node)


def scroll_tap(label):
    for _ in range(6):
        adb('shell', 'uiautomator', 'dump', '/sdcard/startup-window.xml')
        root = ET.fromstring(adb('shell', 'cat', '/sdcard/startup-window.xml').decode())
        for node in root.iter('node'):
            if label in node.get('text', '') + node.get('content-desc', ''):
                tap_node(node)
                return
        adb('shell', 'input', 'swipe', '450', '850', '450', '300', '350')
    raise AssertionError(f'Could not scroll to {label}')


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
scroll_tap("Confirmar préstamo")
wait_for("Mis herramientas")
tap("Destornillador aislado")
tap("Prestada: ver préstamo")
tap("Editar préstamo")
wait_for("Con cargador")
tap_field(1)
adb("shell", "input", "keyevent", "KEYCODE_MOVE_END")
adb("shell", "input", "text", "%sy%sbateria")
adb("shell", "input", "keyevent", "4")
scroll_tap("Guardar cambios")
wait_for("Editar artículo")
tap("Prestada: ver préstamo")
wait_for("Con cargador y bateria")
screenshot("loan-edited.png")
adb("shell", "input", "keyevent", "4")
wait_for("Editar artículo")
tap('Documentos')
wait_for('Documentos ·')
tap('Añadir documento')
tap_field(0)
adb('shell','input','text','Manual')
adb('shell','input','keyevent','4')
tap('Guardar un enlace')
tap_field(1)
adb('shell','input','text','https://example.com/manual.pdf')
adb('shell','input','keyevent','4')
scroll_tap('Guardar documento')
wait_for('Manual')
screenshot('documents.png')
adb('shell','input','keyevent','4')
wait_for('Editar artículo')
tap('Mantenimiento')
wait_for('Fuera de servicio')
tap('Añadir mantenimiento')
tap_field(0)
adb('shell','input','text','Revision')
adb('shell','input','keyevent','4')
tap_field(1)
adb('shell','input','keyevent','KEYCODE_MOVE_END')
adb('shell','input','keyevent','KEYCODE_DEL')
adb('shell','input','text','6')
adb('shell','input','keyevent','4')
scroll_tap('Guardar mantenimiento')
tap('Revision')
wait_for('Registrar intervención')
tap('Registrar intervención')
tap_field(0)
adb('shell','input','text','Limpieza')
adb('shell','input','keyevent','4')
scroll_tap('Guardar intervención')
wait_for('Limpieza')
screenshot('maintenance-recorded.png')
adb('shell','input','keyevent','4')
adb('shell','input','keyevent','4')
wait_for('Editar artículo')
adb('shell','input','keyevent','4')
wait_for('Mis herramientas')
tap('Opciones')
tap('Gestión de herramientas')
wait_for('Avisos en el teléfono')
tap('Avisos en el teléfono')
alarms=adb('shell','dumpsys','alarm').decode()
assert 'ReminderReceiver' in alarms, 'No Android reminder was scheduled'
screenshot('management-overview.png')
adb('shell','input','keyevent','4')
wait_for('Mis herramientas')
tap('Cambiar vista')
tap('Lista compacta')
wait_for('Destornillador aislado')
screenshot('inventory-compact.png')
tap('Cambiar vista')
tap('Cuadrícula')
wait_for('Destornillador aislado')
screenshot('inventory-grid.png')
tap('Filtrar')
wait_for('Filtrar y ordenar')
tap('Con préstamos')
tap('Ver 1 resultados')
wait_for('Filtrar (1)')
wait_for('1 artículos')
screenshot('inventory-filtered.png')
adb('shell', 'am', 'force-stop', package)
adb('shell', 'am', 'start', '-n', f'{package}/.StartupActivity')
wait_for('Filtrar (1)')
wait_for('1 artículos')
tap('Limpiar filtros')
wait_for('3 artículos')
tap('Actualizar herramientas')
wait_for('Destornillador aislado')
def tap_any(labels, timeout=20):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        adb('shell','uiautomator','dump','/sdcard/startup-window.xml')
        root=ET.fromstring(adb('shell','cat','/sdcard/startup-window.xml').decode())
        for node in root.iter('node'):
            text=node.get('text','')+node.get('content-desc','')
            if any(label in text for label in labels):
                tap_node(node)
                return True
        time.sleep(.5)
    return False


def select_import_zip():
    tap('Seleccionar archivo ZIP')
    if tap_any(['demo_100_v9.zip'], timeout=5):
        return
    assert tap_any(['Show roots','Mostrar raíces','Mostrar raices']), 'Document picker navigation missing'
    assert tap_any(['Downloads','Descargas']), 'Downloads folder missing'
    tap('demo_100_v9.zip')


adb('shell','mkdir','-p','/sdcard/Download')
adb('push','test/fixtures/demo_100_v9.zip','/sdcard/Download/demo_100_v9.zip')
adb('shell','am','broadcast','-a','android.intent.action.MEDIA_SCANNER_SCAN_FILE',
    '-d','file:///sdcard/Download/demo_100_v9.zip')
tap('Opciones')
tap('Importar y añadir')
select_import_zip()
wait_for('Para añadir: 100 herramientas y 40 piezas')
screenshot('import-preview.png')
scroll_tap('Añadir a mi inventario')
wait_for('Añadidas 100 herramientas y 40 piezas')
screenshot('import-result.png')
tap('Volver al listado')
wait_for('103 artículos')
tap_field(0)
adb('shell','input','text','Destornillador%saislado')
adb('shell','input','keyevent','4')
tap('Destornillador aislado', exclude_class='android.widget.EditText')
tap('Prestada: ver préstamo')
wait_for('Con cargador y bateria')
adb('shell','input','keyevent','4')
wait_for('Editar artículo')
tap('Documentos')
wait_for('Manual')
screenshot('import-preserved-document.png')
adb('shell','input','keyevent','4')
adb('shell','input','keyevent','4')
wait_for('Mis herramientas')
tap('Limpiar búsqueda')
wait_for('103 artículos')
tap('Opciones')
tap('Importar y añadir')
select_import_zip()
wait_for('Este ZIP ya se ha importado')
screenshot('import-duplicate.png')
adb('shell','input','keyevent','4')
wait_for('103 artículos')
print('Android views, filters, additive import, original loans/documents and repeated import checks passed.')
