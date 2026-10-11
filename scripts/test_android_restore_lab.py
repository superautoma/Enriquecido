"""Local regression checks for embedded lab scripts (Python + PyYAML).

Run: python scripts/test_android_restore_lab.py
Uses command doubles and temporary files; never starts Android or calls GitHub.
"""
import os, pathlib, subprocess, tempfile, unittest
import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
W = yaml.safe_load((ROOT/'.github/workflows/android-restore-lab.yml').read_text())
STEPS = W['jobs']['infrastructure']['steps']

class LabChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='android-lab-check-')
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.env = dict(os.environ, RUNNER_TEMP=str(self.root), ANDROID_HOME=str(self.root),
                        GITHUB_STEP_SUMMARY=str(self.root/'summary'), LAB_SERIAL='emulator-5554',
                        ANDROID_SERIAL='emulator-5554', LAB_AVD='v122-infra-1-1')
        self.env['PATH'] = str(self.root)+':'+self.env['PATH']
        subprocess.run(['bash','-eu','-c',STEPS[1]['run']],env=self.env,check=True)
        self.command('java','exit 0'); self.command('sdkmanager','exit 0')
        self.command('sleep','exit 0')
        self.command('avdmanager', '''if [[ "$1" = list ]]; then printf '    Name: v122-infra-1-1\n    Name: v122-infra-1-10\n'; else printf '%s\n' "$*" >> "$RUNNER_TEMP/deleted"; fi''')
        self.command('adb', '''
case "$*" in
  version) echo "ADB test double";;
  devices*)
    n=0; [[ ! -f "$RUNNER_TEMP/count" ]] || n=$(cat "$RUNNER_TEMP/count")
    echo $((n+1)) > "$RUNNER_TEMP/count"
    [[ "${MODE:-}" != adb_error ]] || exit 1
    echo 'List of devices attached'
    if [[ "${MODE:-}" = stubborn || "${MODE:-}" = probe || ( "${MODE:-}" = stale && "$n" = 0 ) ]]; then printf 'emulator-5554\tdevice\n'; fi;;
  *'emu kill') echo 'Connection refused' >&2; exit 1;;
  *get-state) echo device;;
  *sys.boot_completed) echo 1;;
  *ro.build.version.sdk) echo 29;;
  *ro.build.version.release) echo 10;;
  *'echo android-lab-ok') echo android-lab-ok;;
  *) exit 2;;
esac''')
        (self.root/'emulator').mkdir()
        self.command('emulator/emulator', '''
if [[ "$*" = *-version* && "$*" != '-no-window -noaudio -version' ]]; then exit 127; fi
exit "${EMU_EXIT:-0}"''')
    def command(self,name,body):
        p=self.root/name; p.write_text('#!/usr/bin/env bash\nset -eu\n'+body+'\n'); p.chmod(0o755)
    def run_script(self,name,**env):
        return subprocess.run(['bash',str(self.root/name)],env=dict(self.env,**env),capture_output=True,text=True)
    def cleanup_run(self,mode):
        return subprocess.run(['bash','-eu','-o','pipefail','-c',STEPS[-1]['run']],env=dict(self.env,MODE=mode),capture_output=True,text=True)
    def test_manual_isolation_and_syntax(self):
        self.assertEqual(W.get('on',W.get(True)), {'workflow_dispatch':None})
        self.assertEqual(W['permissions'],{'contents':'read'})
        self.assertEqual(W['jobs']['infrastructure']['if'], "github.ref == 'refs/heads/codex-v122-laboratorio-android'")
        for s in STEPS:
            if 'run' in s: subprocess.run(['bash','-n'],input=s['run'],text=True,check=True)
        for p in self.root.glob('*.sh'): subprocess.run(['bash','-n',str(p)],check=True)
    def test_headless_prelaunch_and_valid_probe(self):
        self.assertEqual(self.run_script('android-lab-prelaunch.sh').returncode,0)
        r=self.run_script('android-lab-probe.sh',MODE='probe')
        self.assertEqual(r.returncode,0,r.stderr); self.assertIn('LAB_BOOT_SECONDS=',r.stdout)
    def test_prelaunch_failure_does_not_create_timestamp(self):
        self.assertNotEqual(self.run_script('android-lab-prelaunch.sh',EMU_EXIT='127').returncode,0)
        self.assertFalse((self.root/'android-lab-start.txt').exists())
    def test_missing_timestamp(self):
        r=self.run_script('android-lab-probe.sh',MODE='probe')
        self.assertNotEqual(r.returncode,0); self.assertIn('falta el registro',r.stderr)
        self.assertNotIn('operand expected',r.stderr); self.assertNotIn('unbound variable',r.stderr)
    def test_invalid_timestamp(self):
        (self.root/'android-lab-start.txt').write_text('invalid')
        r=self.run_script('android-lab-probe.sh',MODE='probe')
        self.assertNotEqual(r.returncode,0); self.assertIn('tiempo inválido',r.stderr)
    def test_future_timestamp(self):
        (self.root/'android-lab-start.txt').write_text('999999999999')
        self.assertNotEqual(self.run_script('android-lab-probe.sh',MODE='probe').returncode,0)
    def test_already_stopped_cleanup_exact_avd(self):
        r=self.cleanup_run('absent'); self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual((self.root/'deleted').read_text(),'delete avd -n v122-infra-1-1\n')
    def test_closed_console_stale_serial(self):
        r=self.cleanup_run('stale'); self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('LAB_SHUTDOWN=verified',r.stdout)
    def test_still_running_preserves_avd(self):
        r=self.cleanup_run('stubborn'); self.assertNotEqual(r.returncode,0)
        self.assertFalse((self.root/'deleted').exists())
    def test_adb_failure_preserves_avd(self):
        r=self.cleanup_run('adb_error'); self.assertNotEqual(r.returncode,0)
        self.assertFalse((self.root/'deleted').exists()); self.assertNotIn('LAB_SHUTDOWN=verified',r.stdout)

if __name__ == '__main__':
    unittest.main(verbosity=2)
