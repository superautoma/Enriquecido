"""Verify the APK launcher reaches the native loader before Flutter's activity."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
ANDROID = '{http://schemas.android.com/apk/res/android}'


class StartupInstallTest(unittest.TestCase):
    def test_launcher_handoff_is_idempotent_and_preserves_flutter_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            flutter = Path(directory) / 'flutter'
            startup = flutter / 'startup_android'
            shutil.copytree(ROOT, startup)
            main = flutter / 'android/app/src/main'
            main.mkdir(parents=True)
            manifest = main / 'AndroidManifest.xml'
            manifest.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
              <application android:name="android.app.Application">
                <activity android:name=".MainActivity" android:exported="true"
                  android:configChanges="orientation|screenSize" android:launchMode="singleTop">
                  <meta-data android:name="io.flutter.embedding.android.NormalTheme" android:resource="@style/NormalTheme"/>
                  <intent-filter><action android:name="android.intent.action.MAIN"/>
                    <category android:name="android.intent.category.LAUNCHER"/></intent-filter>
                </activity>
                <meta-data android:name="flutterEmbedding" android:value="2"/>
              </application></manifest>''')
            gradle = flutter / 'android/app/build.gradle.kts'
            gradle.write_text('''plugins {
                id("com.android.application")
            }
            android {
                buildTypes {
                    release {
                        isMinifyEnabled = true
                        isShrinkResources = true
                        signingConfig = signingConfigs.getByName("debug")
                    }
                }
            }
            ''')
            (flutter / 'android/gradle.properties').write_text(
                'android.builtInKotlin=false\n')
            command = [sys.executable, str(startup / 'install_startup.py')]
            subprocess.run(command, check=True)
            first = hashlib.sha256(manifest.read_bytes()).digest()
            first_gradle = gradle.read_text()
            subprocess.run(command, check=True)
            self.assertEqual(hashlib.sha256(manifest.read_bytes()).digest(), first)
            self.assertEqual(gradle.read_text(), first_gradle)
            self.assertEqual(first_gradle.count('isMinifyEnabled = false'), 1)
            self.assertEqual(first_gradle.count('isShrinkResources = false'), 1)
            self.assertNotIn('isMinifyEnabled = true', first_gradle)
            self.assertNotIn('isShrinkResources = true', first_gradle)
            self.assertIn('signingConfig = signingConfigs.getByName("debug")', first_gradle)
            self.assertEqual(first_gradle.count('id("org.jetbrains.kotlin.android")'), 1)
            app = ET.parse(manifest).getroot().find('application')
            activities = {a.get(ANDROID + 'name'): a for a in app.findall('activity')}
            self.assertEqual(len(activities), 2)
            native = activities['.StartupActivity']
            self.assertEqual(native.get(ANDROID + 'theme'), '@style/StartupTheme')
            self.assertEqual(native.get(ANDROID + 'configChanges'), 'orientation|screenSize')
            launchers = [a.get(ANDROID + 'name') for a in app.findall('activity')
                         if any(c.get(ANDROID + 'name') == 'android.intent.category.LAUNCHER'
                                for i in a.findall('intent-filter') for c in i.findall('category'))]
            self.assertEqual(launchers, ['.StartupActivity'])
            self.assertEqual(activities['.MainActivity'].get(ANDROID + 'launchMode'), 'singleTop')
            self.assertIsNotNone(activities['.MainActivity'].find('meta-data'))
            package = 'org/gestorherramientas/gestor_herramientas_quill_test'
            self.assertTrue((main / 'java' / package / 'StartupActivity.java').exists())
            self.assertTrue((main / 'kotlin' / package / 'MainActivity.kt').exists())
            self.assertTrue((main / 'res/values-v31/startup_styles.xml').exists())
            self.assertTrue((main / 'res/drawable-v21/launch_background.xml').exists())
            styles = ET.parse(main / 'res/values-v31/startup_styles.xml').getroot()
            restored = next(s for s in styles.findall('style') if s.get('name') == 'LaunchTheme')
            self.assertEqual(restored.get('parent'), 'StartupTheme')
            self.assertTrue(any(p.get(ANDROID + 'name') == 'android.permission.INTERNET'
                                for p in ET.parse(manifest).getroot().findall('uses-permission')))


if __name__ == '__main__':
    unittest.main()
