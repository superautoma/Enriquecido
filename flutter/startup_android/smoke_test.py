"""Check the Android startup overlay hands off to Flutter and back navigation works."""
import pathlib
import re
import subprocess
import struct
import sys
import time
import traceback as traceback_module
import zlib
import xml.etree.ElementTree as ET

package = "org.gestorherramientas.gestor_herramientas_quill_test"
output = pathlib.Path("startup-check")
output.mkdir(exist_ok=True)


def adb(*args):
    # Older Android package managers need longer to verify a release APK.
    timeout = 180 if args and args[0] == 'install' else 35
    return subprocess.check_output(["adb", *args], timeout=timeout)


def screenshot(name):
    (output / name).write_bytes(adb("exec-out", "screencap", "-p"))


def save_failure_diagnostics(error_type, error, traceback):
    # Retain native startup errors when a screen never becomes accessible.
    for name, command in [
        ('failure-logcat.txt', ('logcat', '-d')),
        ('failure-activities.txt', ('shell', 'dumpsys', 'activity', 'activities')),
    ]:
        try:
            (output / name).write_bytes(adb(*command))
        except subprocess.SubprocessError:
            pass
    (output / 'failure-traceback.txt').write_text(''.join(traceback_module.format_exception(error_type, error, traceback)))
    message = f'{error_type.__name__}: {error}'.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print(f'::error title=Android smoke test::{message}', flush=True)
    sys.__excepthook__(error_type, error, traceback)


sys.excepthook = save_failure_diagnostics


def wait_for(label, exclude_class=None, timeout=120, prefer_exact=False):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            adb("shell", "uiautomator", "dump", "/sdcard/startup-window.xml")
            xml = adb("shell", "cat", "/sdcard/startup-window.xml").decode()
            (output / "window.xml").write_text(xml)
            root = ET.fromstring(xml)
            matches = [node for node in root.iter("node")
                       if label in node.get("text", "") + node.get("content-desc", "")
                       and node.get('class') != exclude_class]
            if matches:
                if prefer_exact:
                    exact = [node for node in matches
                             if node.get("text", "") + node.get("content-desc", "") == label]
                    if exact:
                        return next((node for node in exact if node.get('clickable') == 'true'), exact[0])
                return matches[0]
        except (subprocess.SubprocessError, ET.ParseError):
            pass
        time.sleep(1)
    screenshot("startup-failed.png")
    raise AssertionError(f"Android did not display {label!r}")


def tap(label, exclude_class=None):
    node = wait_for(label, exclude_class=exclude_class, timeout=30, prefer_exact=True)
    tap_node(node)


def scroll_find(label, *, dialog=False):
    last_swipe = None
    for _ in range(6):
        adb('shell', 'uiautomator', 'dump', '/sdcard/startup-window.xml')
        xml = adb('shell', 'cat', '/sdcard/startup-window.xml').decode()
        (output / 'window.xml').write_text(xml)
        root = ET.fromstring(xml)
        for node in root.iter('node'):
            if label in node.get('text', '') + node.get('content-desc', ''):
                return node
        screen = next(root.iter('node'))
        left, top, right, bottom = map(int, re.findall(r'\d+', screen.attrib['bounds']))
        start_fraction, end_fraction = .8, .35
        if dialog:
            # Dialog actions are outside the scrolling content. A whole-screen
            # swipe starts on those fixed buttons and never scrolls the palette.
            viewports = []
            for node in root.iter('node'):
                if node.get('scrollable') != 'true':
                    continue
                bounds = list(map(int, re.findall(r'\d+', node.get('bounds', ''))))
                if len(bounds) == 4 and bounds[2] > bounds[0] and bounds[3] > bounds[1]:
                    viewports.append(bounds)
            if viewports:
                left, top, right, bottom = max(viewports, key=lambda b: (b[2]-b[0])*(b[3]-b[1]))
            else:
                start_fraction, end_fraction = .55, .25
        x = (left + right) // 2
        start_y = top + int((bottom - top) * start_fraction)
        end_y = top + int((bottom - top) * end_fraction)
        last_swipe = (x, start_y, x, end_y)
        adb('shell', 'input', 'swipe', str(x), str(start_y), str(x), str(end_y), '350')
    screenshot('scroll-failed.png')
    raise AssertionError(f'Could not scroll to {label}; dialog={dialog}, last swipe={last_swipe}')


def scroll_tap(label, *, dialog=False):
    tap_node(scroll_find(label, dialog=dialog))


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



def tap_first_empty_field():
    # Flutter's empty input labels are not exposed by Android 29's XML dump.
    # In this seeded editor all base fields already have values; the expanded
    # optional section is therefore the only source of empty editable fields.
    for _ in range(8):
        adb('shell', 'uiautomator', 'dump', '/sdcard/startup-window.xml')
        xml = adb('shell', 'cat', '/sdcard/startup-window.xml').decode()
        (output / 'window.xml').write_text(xml)
        root = ET.fromstring(xml)
        screen = next(root.iter('node'))
        left, top, right, bottom = map(int, re.findall(r'\d+', screen.attrib['bounds']))
        fields = []
        for node in root.iter('node'):
            if node.get('class') != 'android.widget.EditText' or node.get('text', ''):
                continue
            bounds = list(map(int, re.findall(r'\d+', node.attrib['bounds'])))
            if bounds[1] >= 80 and bounds[3] - bounds[1] >= 40 and bounds[3] <= bottom - 24:
                fields.append((bounds[1], node))
        if fields:
            tap_node(min(fields, key=lambda pair: pair[0])[1])
            return
        x = (left + right) // 2
        adb('shell', 'input', 'swipe', str(x), str(int(bottom * .8)),
            str(x), str(int(bottom * .55)), '350')
    screenshot('empty-field-failed.png')
    raise AssertionError('The expanded section did not expose an empty editable field')

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



adb("install", "--no-streaming", "-r", "build/app/outputs/flutter-apk/app-release.apk")
adb('logcat', '-c')
adb("shell", "am", "force-stop", package)
adb("shell", "am", "start", "-n", f"{package}/.StartupActivity")
screenshot("startup-first-frame.png")
if '--svg-only' in sys.argv:
    wait_for('Mis herramientas')
    tap('Gestor de iconos')
    wait_for('Gestor de iconos')
    tap_field(0)
    adb('shell', 'input', 'text', 'Alicates')
    adb('shell', 'input', 'keyevent', '4')
    tap('Opciones del icono')
    tap('Editar SVG')
    wait_for('Editor SVG')
    wait_for('24 px')
    screenshot('svg-editor-open.png')
    # Edit the new copy's name; no storage permission is required for private icons.
    tap_field(0)
    adb('shell', 'input', 'keyevent', 'KEYCODE_MOVE_END')
    adb('shell', 'input', 'text', '%sSVGQA')
    adb('shell', 'input', 'keyevent', '4')
    # Exercise the integrated dialog, not the legacy quick swatches.
    scroll_tap('Elegir color: Relleno')
    wait_for('Color: Relleno')
    screenshot('svg-color-selector.png')
    tap('Color #e91e63')
    scroll_find('Tonalidades', dialog=True)
    screenshot('svg-color-tonalities.png')
    tap('Seleccionar')
    wait_for('#e91e63')
    scroll_tap('Elegir color: Relleno')
    tap('Color #f44336')
    tap('Cancelar')
    wait_for('#e91e63')
    screenshot('svg-color-cancel-preserved.png')
    scroll_tap('Elegir color: Color de línea')
    tap('Color #2196f3')
    tap('Seleccionar')
    wait_for('#2196f3')
    scroll_tap('Elegir color: Fondo SVG (círculo)')
    scroll_tap('Color #ffffff', dialog=True)
    tap('Seleccionar')
    scroll_tap('Centrar y ajustar')
    tap('Deshacer')
    tap('Rehacer')
    screenshot('svg-editor-adjusted.png')
    scroll_tap('Guardar como nuevo SVG')
    wait_for('Gestor de iconos')
    wait_for('SVGQA')
    screenshot('svg-library-saved.png')
    adb('shell', 'am', 'force-stop', package)
    adb('shell', 'am', 'start', '-n', f'{package}/.StartupActivity')
    wait_for('Mis herramientas')
    tap('Gestor de iconos')
    tap_field(0)
    adb('shell', 'input', 'text', 'SVGQA')
    adb('shell', 'input', 'keyevent', '4')
    wait_for('1 iconos')
    tap('Opciones del icono')
    tap('Editar SVG')
    wait_for('Editor SVG')
    wait_for('24 px')
    # Reopening preserves the saved SVG as its original document; color fields
    # correctly start in 'Conservar original', not as new recoloring overrides.
    screenshot('svg-editor-reopened.png')
    adb('shell', 'input', 'keyevent', '4')
    wait_for('Gestor de iconos')
    adb('shell', 'input', 'keyevent', '4')
    wait_for('Mis herramientas')
    errors = adb('logcat', '-d', '-s', 'AndroidRuntime:E').decode()
    assert 'FATAL EXCEPTION' not in errors, errors
    print('SVG editor: light color dialog, palette selection, cancellation preserving previous color, paint/background edits, centering, undo/redo, save new icon, restart, reopen saved SVG and back navigation passed without storage permissions.')
    sys.exit(0)
if '--ai-only' in sys.argv:
    wait_for('Destornillador aislado')
    wait_for('3 artículos')
    tap('Opciones')
    tap('Conexión con ChatGPT')
    wait_for('Continuar con ChatGPT')
    wait_for('ChatGPT todavía no está conectado.')
    screenshot('ai-connection.png')
    # This creates and reads the encrypted Keystore credential container without signing in.
    adb('shell', 'input', 'keyevent', '4')
    wait_for('Mis herramientas')
    tap('Opciones')
    tap('Crear ficha con IA')
    wait_for('Tomar foto')
    wait_for('Elegir foto')
    wait_for('Conectar ChatGPT')
    screenshot('ai-photo.png')
    tap('Conectar ChatGPT')
    wait_for('Continuar con ChatGPT')
    adb('shell', 'input', 'keyevent', '4')
    wait_for('Crear ficha con IA')
    adb('shell', 'input', 'keyevent', '4')
    wait_for('3 artículos')
    adb('shell', 'am', 'force-stop', package)
    adb('shell', 'am', 'start', '-n', f'{package}/.StartupActivity')
    wait_for('3 artículos')
    tap('Opciones')
    tap('Conexión con ChatGPT')
    wait_for('ChatGPT todavía no está conectado.')
    screenshot('ai-connection-reopened.png')
    errors = adb('logcat', '-d', '-s', 'AndroidRuntime:E').decode()
    assert 'FATAL EXCEPTION' not in errors, errors
    print('AI photo and ChatGPT connection screens, encrypted device storage, restart and unchanged inventory verified. Real authorization and inference require the phone owner.')
    sys.exit(0)
if '--feedback-only' in sys.argv:
    # Check the system service independently of the app's method channel.
    sdk = int(adb('shell', 'getprop', 'ro.build.version.sdk').decode().strip())
    service = 'vibrator_manager' if sdk >= 31 else 'vibrator'
    capability = adb('shell', 'service', 'call', service, '1').decode()
    (output / 'feedback-vibrator-hardware.txt').write_text(capability)
    reply = re.search(r'Parcel\(\s*(?:0x00000000:\s*)?00000000\s+([0-9a-fA-F]{8})\b', capability)
    assert reply, f'Could not query vibrator hardware: {capability}'
    available = int(reply[1], 16)
    assert 0 <= available < 100, f'Unexpected vibrator capability: {capability}'
    has_vibrator = available > 0
    permissions = adb('shell', 'dumpsys', 'package', package).decode()
    (output / 'feedback-permissions.txt').write_text(permissions)
    assert re.search(r'android\.permission\.VIBRATE:\s*granted=true', permissions), \
        'The installed APK must have the normal VIBRATE permission'
    installed_version = re.search(r'\bversionCode=(\d+)', permissions)
    assert installed_version, 'The installed APK version must be available'

    def direct_vibrations(name):
        dump = adb('shell', 'dumpsys', service).decode()
        (output / name).write_text(dump)
        return [row for row in dump.splitlines() if package in row
                and ('120' in row or '1000' in row)]

    def expect_preview_vibration(before, name):
        if not has_vibrator:
            assert direct_vibrations(name) == before
            print('Emulator has no vibrator hardware; physical pulse delivery needs a phone.')
            return
        for _ in range(10):
            after = direct_vibrations(name)
            if len(after) == len(before) + 1:
                return
            time.sleep(.1)
        raise AssertionError('Preview must request one compatible vibration')

    def switch_state(label):
        wait_for(label)
        adb('shell', 'uiautomator', 'dump', '/sdcard/startup-window.xml')
        root = ET.fromstring(adb('shell', 'cat', '/sdcard/startup-window.xml').decode())
        switches = [node for node in root.iter('node') if node.get('checkable') == 'true'
                    and label in node.get('text', '') + node.get('content-desc', '')]
        assert len(switches) == 1, f'Expected one accessible switch for {label}'
        return switches[0].get('checked') == 'true'

    def scroll_to_top():
        adb('shell', 'uiautomator', 'dump', '/sdcard/startup-window.xml')
        screen = next(ET.fromstring(adb('shell', 'cat', '/sdcard/startup-window.xml').decode()).iter('node'))
        left, top, right, bottom = map(int, re.findall(r'\d+', screen.attrib['bounds']))
        x = (left + right) // 2
        for _ in range(4):
            adb('shell', 'input', 'swipe', str(x), str(top + int((bottom - top) * .35)),
                str(x), str(top + int((bottom - top) * .8)), '250')

    wait_for('3 artículos')
    tap('Opciones')
    tap('Sonido y vibración')
    assert switch_state('Sonido al pulsar')
    assert switch_state('Vibración al pulsar')
    scroll_tap('Comprobar de nuevo')
    wait_for('Motor de vibración detectado.' if has_vibrator
             else 'Este dispositivo no tiene motor de vibración disponible.')
    wait_for(f'Versión instalada: {installed_version[1]}')
    screenshot('feedback-hardware-status.png')
    adb('logcat', '-c')
    scroll_tap('Probar vibración (1 segundo)')
    wait_for('Prueba de un segundo enviada' if has_vibrator
             else 'Este dispositivo no tiene motor de vibración disponible.')
    native = adb('logcat', '-d', '-s', 'ButtonFeedback:I').decode()
    assert f'Manual vibration test: {"requested" if has_vibrator else "no_motor"}' in native, \
        'The independent test must reach the installed native vibration handler'
    (output / 'feedback-native-test.txt').write_text(native)
    screenshot('feedback-independent-test.png')
    scroll_tap('Ajustes del móvil')
    time.sleep(1)
    adb('shell', 'input', 'keyevent', '4')
    wait_for('Sonido y vibración')
    scroll_to_top()
    before_preview = direct_vibrations('feedback-vibrator-before.txt')
    tap('Probar botón')
    expect_preview_vibration(before_preview, 'feedback-vibrator-on.txt')
    screenshot('feedback-settings-on.png')
    tap('Sonido al pulsar')
    assert not switch_state('Sonido al pulsar')
    tap('Vibración al pulsar')
    assert not switch_state('Vibración al pulsar')
    before_disabled = direct_vibrations('feedback-vibrator-disabled-before.txt')
    tap('Probar botón')
    assert direct_vibrations('feedback-vibrator-disabled-after.txt') == before_disabled, \
        'Disabled feedback must not request a vibration'
    adb('shell', 'am', 'force-stop', package)
    adb('shell', 'am', 'start', '-n', f'{package}/.StartupActivity')
    wait_for('3 artículos')
    tap('Opciones')
    tap('Sonido y vibración')
    assert not switch_state('Sonido al pulsar')
    assert not switch_state('Vibración al pulsar')
    screenshot('feedback-settings-persisted.png')
    tap('Vibración al pulsar')
    assert not switch_state('Sonido al pulsar')
    assert switch_state('Vibración al pulsar')
    before_vibration_only = direct_vibrations('feedback-vibrator-only-before.txt')
    tap('Probar botón')
    expect_preview_vibration(before_vibration_only, 'feedback-vibrator-only-after.txt')
    screenshot('feedback-vibration-only.png')
    tap('Sonido al pulsar')
    assert switch_state('Sonido al pulsar')
    # A changed system setting is refreshed explicitly without pretending that
    # the device can vibrate when the OS has disabled tactile feedback.
    adb('shell', 'settings', 'put', 'system', 'haptic_feedback_enabled', '0')
    scroll_tap('Comprobar de nuevo')
    wait_for('desactivada la respuesta táctil' if has_vibrator
             else 'Este dispositivo no tiene motor de vibración disponible.')
    screenshot('feedback-system-setting.png')
    adb('shell', 'settings', 'put', 'system', 'haptic_feedback_enabled', '1')
    adb('shell', 'input', 'keyevent', '4')
    wait_for('3 artículos')
    tap('Destornillador aislado', exclude_class='android.widget.EditText')
    wait_for('Editar artículo')
    adb('shell', 'input', 'keyevent', '4')
    wait_for('3 artículos')
    errors = adb('logcat', '-d', '-s', 'AndroidRuntime:E').decode()
    assert 'FATAL EXCEPTION' not in errors, errors
    print('Android feedback settings: VIBRATE permission, independent toggles, preview, restart persistence, '
          f'inventory navigation and absence of native crashes verified; vibrator hardware={has_vibrator}.')
    sys.exit(0)

if '--trash-only' in sys.argv:
    wait_for('Destornillador aislado')
    wait_for('3 artículos')
    tap('Destornillador aislado', exclude_class='android.widget.EditText')
    tap('Selecciona el tipo')
    tap('Herramienta manual')
    tap('GUARDAR')
    tap('Destornillador aislado', exclude_class='android.widget.EditText')
    tap('Opciones del artículo')
    tap('Eliminar artículo')
    wait_for('Enviar a la papelera')
    screenshot('trash-confirmation.png')
    tap('Cancelar')
    wait_for('Editar artículo')
    adb('shell', 'input', 'keyevent', '4')
    wait_for('3 artículos')
    tap('Destornillador aislado', exclude_class='android.widget.EditText')
    tap('Opciones del artículo')
    tap('Eliminar artículo')
    tap('Enviar a la papelera')
    wait_for('Mis herramientas')
    wait_for('2 artículos')
    screenshot('trash-inventory.png')
    adb('shell', 'am', 'force-stop', package)
    adb('shell', 'am', 'start', '-n', f'{package}/.StartupActivity')
    wait_for('2 artículos')
    tap('Buscar por código')
    assert tap_any(['ALLOW', 'PERMITIR'], timeout=10), 'Camera permission prompt missing'
    tap('Introducir código')
    tap_field(0)
    adb('shell', 'input', 'text', '841000000001')
    tap('Usar código')
    wait_for('Artículo en la papelera')
    screenshot('trash-code-match.png')
    tap('Abrir papelera')
    wait_for('Destornillador aislado')
    screenshot('trash-page.png')
    tap('Recuperar artículo')
    wait_for('La papelera está vacía')
    screenshot('trash-restored.png')
    adb('shell', 'input', 'keyevent', '4')
    wait_for('3 artículos')
    tap('Destornillador aislado', exclude_class='android.widget.EditText')
    wait_for('841000000001')
    tap('Disponible: prestar herramienta')
    tap('Prestar')
    wait_for('Prestar herramienta')
    tap_field(0)
    adb('shell', 'input', 'text', 'Pedro')
    adb('shell', 'input', 'keyevent', '4')
    scroll_tap('Confirmar préstamo')
    wait_for('Mis herramientas')
    tap('Destornillador aislado', exclude_class='android.widget.EditText')
    tap('Opciones del artículo')
    tap('Eliminar artículo')
    wait_for('Devuelve primero los préstamos activos', timeout=10)
    screenshot('trash-loan-blocked.png')
    adb('shell', 'input', 'keyevent', '4')
    wait_for('3 artículos')
    print('Android trash: confirmation cancel, removal, persistence, barcode lookup, recovery and active-loan protection passed.')
    sys.exit(0)

if '--scanner-only' not in sys.argv:
    item = wait_for("Destornillador aislado")
    screenshot("startup-ready.png")
    coords = [int(value) for value in re.findall(r"\d+", item.attrib["bounds"])]
    adb("shell", "input", "tap", str((coords[0] + coords[2]) // 2),
        str((coords[1] + coords[3]) // 2))
    wait_for("Editar artículo")
    tap('Selecciona el tipo')
    tap('Herramienta manual')
    scroll_tap('Identificación')
    screenshot('identification-open.png')
    for label, value in [('Marca', 'Bosch%sQA'), ('Modelo', 'GSB%s18V'), ('Número de serie', 'SER-QA-001')]:
        tap_first_empty_field()
        adb('shell', 'input', 'text', value)
        adb('shell', 'input', 'keyevent', '4')
    scroll_tap('Ubicación')
    screenshot('location-open.png')
    for label, value in [('Lugar / taller', 'Taller%sQA'), ('Estantería', 'Estante%s2'),
                         ('Balda', 'Balda%s3'), ('Caja / maletín', 'Caja%sazul')]:
        tap_first_empty_field()
        adb('shell', 'input', 'text', value)
        adb('shell', 'input', 'keyevent', '4')
    screenshot('tool-location-editor.png')
    tap('GUARDAR')
    wait_for('Mis herramientas')
    wait_for('Taller QA')
    screenshot('inventory-location.png')
    tap('Destornillador aislado')
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
    tap('Destornillador aislado')
    scroll_tap('SER-QA-001')
    wait_for('SER-QA-001')
    adb('shell', 'input', 'keyevent', '4')
    scroll_tap('Caja azul')
    wait_for('Caja azul')
    screenshot('tool-details-reopened.png')
    adb('shell', 'input', 'keyevent', '4')
    adb('shell', 'input', 'keyevent', '4')
    wait_for('Mis herramientas')
    tap('Limpiar filtros')
    wait_for('3 artículos')
    tap('Actualizar herramientas')
    wait_for('Destornillador aislado')
    adb('shell','mkdir','-p','/sdcard/Download')
    adb('push','test/fixtures/demo_100_v9.zip','/sdcard/Download/demo_100_v9.zip')
    adb('shell','am','broadcast','-a','android.intent.action.MEDIA_SCANNER_SCAN_FILE',
        '-d','file:///sdcard/Download/demo_100_v9.zip')
    tap('Opciones')
    # The long options menu can put import below the emulator viewport.
    scroll_tap('Importar y añadir')
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
    # The long options menu can put import below the emulator viewport.
    scroll_tap('Importar y añadir')
    select_import_zip()
    wait_for('Este ZIP ya se ha importado')
    screenshot('import-duplicate.png')
    adb('shell','input','keyevent','4')
    wait_for('103 artículos')
    print('Android views, filters, additive import, original loans/documents and repeated import checks passed.')

    tap('Filtrar')
    scroll_tap('Taller QA')
    scroll_tap('Bosch QA')
    tap('Ver 1 resultados')
    wait_for('Filtrar (2)')
    wait_for('1 artículos')
    wait_for('Taller QA')
    screenshot('inventory-location-filter.png')
    print('Android location editing, persistence, import retention and brand/location filters passed.')

else:
    wait_for('Destornillador aislado')
    tap('Destornillador aislado', exclude_class='android.widget.EditText')
    tap('Selecciona el tipo')
    tap('Herramienta manual')
    tap('GUARDAR')
    wait_for('Mis herramientas')
    tap('Filtrar')
    scroll_tap('Herramienta manual')
    tap('Ver 1 resultados')
    wait_for('1 artículos')

# Exercise the production scanner UI, then the actual Android ML Kit decoder
# with a QR fixture. The emulator camera cannot verify handheld focus quality.
tap('Destornillador aislado', exclude_class='android.widget.EditText')
scroll_tap('Leer código con cámara')
# Android 29 displays the button in capitals; mixed-case "Allow" matches the
# explanatory, non-clickable sentence instead and leaves the dialog open.
assert tap_any(['ALLOW', 'PERMITIR'], timeout=10), 'Camera permission prompt missing'
wait_for('Leer código', timeout=30)
screenshot('scanner-camera.png')
tap('Introducir código')
tap_field(0)
adb('shell', 'input', 'text', '0012345678905')
tap('Usar código')
wait_for('Sustituir código')
tap('Sustituir')
wait_for('0012345678905')
tap('GUARDAR')
wait_for('Mis herramientas')

# Search is deliberately set to no matches: scanning must bypass it.
tap_field(0)
adb('shell', 'input', 'text', 'SIN-COINCIDENCIAS')
adb('shell', 'input', 'keyevent', '4')
wait_for('0 artículos')
matrix = pathlib.Path('test/fixtures/scanner_qr_matrix.txt').read_text().splitlines()[1:]
scale, border = 12, 4
size = (len(matrix) + border * 2) * scale
rows = []
for y in range(size):
    my = y // scale - border
    row = bytearray([0])
    for x in range(size):
        mx = x // scale - border
        dark = 0 <= my < len(matrix) and 0 <= mx < len(matrix) and matrix[my][mx] == '1'
        row.append(0 if dark else 255)
    rows.append(bytes(row))
def png_chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data) & 0xffffffff)
fixture = output / 'scanner_qa.png'
fixture.write_bytes(b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', struct.pack('!2I5B', size, size, 8, 0, 0, 0, 0))
                   + png_chunk(b'IDAT', zlib.compress(b''.join(rows))) + png_chunk(b'IEND', b''))
adb('push', str(fixture), '/sdcard/Download/scanner_qa.png')
adb('shell', 'am', 'broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
    '-d', 'file:///sdcard/Download/scanner_qa.png')
tap('Buscar por código')
tap('Leer imagen')
if not tap_any(['scanner_qa.png'], timeout=5):
    assert tap_any(['Show roots', 'Mostrar raíces', 'Mostrar raices']), 'Image picker navigation missing'
    assert tap_any(['Downloads', 'Descargas']), 'Downloads images missing'
    tap('scanner_qa.png')
wait_for('Editar artículo')
wait_for('Destornillador aislado')
screenshot('scanner-image-match.png')
scroll_tap('Etiqueta QR propia')
label_node = wait_for('GH1:')
label_text = label_node.get('text', '') + label_node.get('content-desc', '')
label_code = re.search(r'GH1:[0-9a-f]{32}', label_text).group(0)
screenshot('tool-own-qr.png')
adb('shell', 'input', 'keyevent', '4')
tap('GUARDAR')
tap('Buscar por código')
tap('Introducir código')
tap_field(0)
adb('shell', 'input', 'text', label_code)
tap('Usar código')
wait_for('Editar artículo')
wait_for('Destornillador aislado')
scroll_tap('Etiqueta QR propia')
wait_for(label_code)
adb('shell', 'input', 'keyevent', '4')
adb('shell', 'input', 'keyevent', '4')
wait_for('Mis herramientas')
tap('Buscar por código')
tap('Introducir código')
tap_field(0)
adb('shell', 'input', 'text', '000NEW-QA')
tap('Usar código')
wait_for('Código sin coincidencias')
tap('Crear herramienta')
scroll_find('000NEW-QA')
screenshot('scanner-new-prefill.png')
adb('shell', 'input', 'keyevent', '4')
wait_for('Mis herramientas')
tap('Limpiar búsqueda')
wait_for('1 artículos')
print('Android camera permission, barcode replacement, native QR image decoding, filtered lookup, stable own QR and unknown-code prefill checks passed.')
