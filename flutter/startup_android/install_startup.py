"""Install the native first-frame loader into a generated Flutter Android project."""
from pathlib import Path
import shutil
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent
android = root.parent / 'android/app/src/main'
package = 'org.gestorherramientas.gestor_herramientas_quill_test'
sources = android / 'kotlin' / Path(package.replace('.', '/'))
sources.mkdir(parents=True, exist_ok=True)
shutil.copy2(root / 'MainActivity.kt', sources / 'MainActivity.kt')
shutil.copy2(root / 'ToolManagement.kt', sources / 'ToolManagement.kt')
java = android / 'java' / Path(package.replace('.', '/'))
java.mkdir(parents=True, exist_ok=True)
shutil.copy2(root / 'StartupActivity.java', java / 'StartupActivity.java')
shutil.copytree(root / 'res', android / 'res', dirs_exist_ok=True)

ns = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', ns)
attr = lambda key: f'{{{ns}}}{key}'
path = android / 'AndroidManifest.xml'
tree = ET.parse(path)
manifest = tree.getroot()
if not any(p.get(attr('name')) == 'android.permission.INTERNET' for p in manifest.findall('uses-permission')):
    ET.SubElement(manifest, 'uses-permission', {attr('name'): 'android.permission.INTERNET'})
for permission in ['android.permission.POST_NOTIFICATIONS', 'android.permission.RECEIVE_BOOT_COMPLETED',
                   'android.permission.CAMERA']:
    if not any(p.get(attr('name')) == permission for p in manifest.findall('uses-permission')):
        ET.SubElement(manifest, 'uses-permission', {attr('name'): permission})
feature = next((f for f in manifest.findall('uses-feature')
                if f.get(attr('name')) == 'android.hardware.camera'), None)
if feature is None:
    feature = ET.SubElement(manifest, 'uses-feature', {attr('name'): 'android.hardware.camera'})
feature.set(attr('required'), 'false')
application = manifest.find('application')
if not any(p.get(attr('name')) == '.ToolDocumentProvider' for p in application.findall('provider')):
    ET.SubElement(application, 'provider', {
        attr('name'): '.ToolDocumentProvider', attr('authorities'): package + '.documents',
        attr('exported'): 'false', attr('grantUriPermissions'): 'true',
    })
if not any(r.get(attr('name')) == '.ReminderReceiver' for r in application.findall('receiver')):
    receiver = ET.SubElement(application, 'receiver', {
        attr('name'): '.ReminderReceiver', attr('exported'): 'false',
    })
    intent = ET.SubElement(receiver, 'intent-filter')
    for action in ['android.intent.action.BOOT_COMPLETED', 'android.intent.action.MY_PACKAGE_REPLACED',
                   'android.intent.action.TIME_SET', 'android.intent.action.TIMEZONE_CHANGED']:
        ET.SubElement(intent, 'action', {attr('name'): action})
main = next(a for a in application.findall('activity') if a.get(attr('name')) == '.MainActivity')
for intent in list(main.findall('intent-filter')):
    if any(a.get(attr('name')) == 'android.intent.action.MAIN' for a in intent.findall('action')):
        main.remove(intent)
if not any(a.get(attr('name')) == '.StartupActivity' for a in application.findall('activity')):
    startup = ET.SubElement(application, 'activity', {
        attr('name'): '.StartupActivity', attr('exported'): 'true',
        attr('theme'): '@style/StartupTheme', attr('taskAffinity'): '',
        attr('configChanges'): main.get(attr('configChanges')),
        attr('hardwareAccelerated'): 'true',
    })
    intent = ET.SubElement(startup, 'intent-filter')
    ET.SubElement(intent, 'action', {attr('name'): 'android.intent.action.MAIN'})
    ET.SubElement(intent, 'category', {attr('name'): 'android.intent.category.LAUNCHER'})
ET.indent(tree)
tree.write(path, encoding='utf-8', xml_declaration=True)

# Flutter's AGP 9 migration opts out of built-in Kotlin. Ensure the existing
# Kotlin Flutter activity is still compiled when generated templates omit KGP.
properties = android.parents[2] / 'gradle.properties'
gradle = android.parents[1] / 'build.gradle.kts'
if properties.exists() and gradle.exists() and 'android.builtInKotlin=false' in properties.read_text():
    text = gradle.read_text()
    if 'id("org.jetbrains.kotlin.android")' not in text and 'id("kotlin-android")' not in text:
        text = text.replace('id("com.android.application")',
                            'id("com.android.application")\n    id("org.jetbrains.kotlin.android")', 1)
        gradle.write_text(text)

# JNI-backed plugins can access classes by name, outside R8's reachability
# analysis. Preserve Android classes/resources while keeping Dart release AOT.
if not gradle.exists():
    raise SystemExit('No se encontró android/app/build.gradle.kts')
text = gradle.read_text()
marker = 'release {'
if text.count(marker) != 1:
    raise SystemExit('No se encontró un único bloque release en build.gradle.kts')
text = re.sub(r'^[ \t]*(?:isMinifyEnabled|isShrinkResources)[ \t]*=.*\n?', '', text, flags=re.MULTILINE)
text = text.replace(marker, marker + '\n            isMinifyEnabled = false\n            isShrinkResources = false', 1)
gradle.write_text(text)
