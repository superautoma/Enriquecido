#!/usr/bin/env python3
"""Kill real Flutter workers and verify cold-start recovery on synthetic data.

Uses the already installed V122 Flutter SDK; no setup, APK or network operation.
Load the existing SDK environment with source scripts/v122-env.sh, then run:
python3 scripts/validate_restore_processes.py
Only test/support files are executed. All inventory files live in a fresh /tmp
directory guarded by a marker; failures retain that directory for inspection.
"""
import argparse
import hashlib
import json
import os
import signal
from pathlib import Path
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenario', action='append', help='Run only named scenarios')
    args = parser.parse_args()
    sdk = Path((REPO / '.codex-v122/sdk-path').read_text().strip())
    assert (sdk / 'bin/flutter').is_file(), 'An existing Flutter SDK is required'
    lab = Path(tempfile.mkdtemp(prefix='v122_restore_lab_'))
    state = REPO / '.codex-v122'
    env = os.environ.copy()
    env.update(PUB_CACHE=str(state / 'pub-cache'),
               LD_LIBRARY_PATH=str(state / 'lib') + ':' + env.get('LD_LIBRARY_PATH', ''))
    worker_runs = []
    results = []

    def worker(root, action, fault='', expect='old', killed=False):
        sequence = len(worker_runs) + 1
        output = root / f'{sequence:02d}-{action}.json'
        log = root / f'{sequence:02d}-{action}.log'
        worker_env = dict(env, V122_RESTORE_LAB_ROOT=str(root),
                          V122_RESTORE_LAB_ACTION=action, V122_RESTORE_LAB_FAULT=fault,
                          V122_RESTORE_LAB_RESULT=str(output), V122_RESTORE_LAB_EXPECT=expect)
        with log.open('w') as stream:
            run = subprocess.Popen([str(sdk / 'bin/flutter'), 'test', '--no-pub',
                                    '--reporter', 'json', 'test/support/restore_process_worker.dart'],
                                   cwd=REPO / 'flutter', env=worker_env,
                                   stdout=stream, stderr=subprocess.STDOUT)
            death = Path(str(output) + '.killed')
            sent = False
            deadline = time.monotonic() + 180
            while run.poll() is None:
                if killed and death.is_file() and not sent:
                    requested = json.loads(death.read_text())
                    child = requested['pid']
                    proc = Path(f'/proc/{child}')
                    assert b'flutter_tester' in (proc / 'cmdline').read_bytes()
                    status = (proc / 'status').read_text().splitlines()
                    parent = next(x for x in status if x.startswith('PPid:'))
                    assert int(parent.split()[1]) == run.pid, 'Only kill our own Flutter child'
                    os.kill(child, signal.SIGKILL)
                    sent = True
                if time.monotonic() > deadline:
                    run.kill()
                    run.wait()
                    raise TimeoutError(f'Worker timed out: {log}')
                time.sleep(0.05)
        info = {'action': action, 'fault': fault, 'exit': run.returncode, 'log': str(log)}
        worker_runs.append(info)
        death = Path(str(output) + '.killed')
        if killed:
            assert death.is_file(), f'SIGKILL point not reached: {log}'
            assert run.returncode != 0, f'SIGKILL unexpectedly succeeded: {log}'
            assert not output.exists(), f'Worker finished after SIGKILL: {log}'
            info.update(json.loads(death.read_text()))
            assert info['signal'] == 'SIGKILL'
            assert sent, f'Parent must send actual SIGKILL: {log}'
            info['signal_sent_by_parent'] = True
            print(f"  SIGKILL pid={info['pid']} at {info['point']}, journal={info['phase']}", flush=True)
            return info
        assert run.returncode == 0, f'Worker failed: {log}'
        assert output.is_file(), f'Worker result missing: {log}'
        info.update(json.loads(output.read_text()))
        return info

    def journal(root):
        return json.loads((root / 'target/.safe_restore_v122/journal.json').read_text())

    def rescue_hashes(root):
        rescue = root / 'target/.safe_restore_v122/operation/recovery'
        assert rescue.is_dir()
        files = {str(p.relative_to(rescue)): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in rescue.rglob('*') if p.is_file()}
        assert {'database', 'tool_images/photo.jpg', 'tool_documents/manual.pdf',
                'tool_images/custom_icons/icon.svg'}.issubset(files)
        return files

    def restart(root, expect='old', recovered=True):
        info = worker(root, 'restart', expect=expect)
        assert info['verified'] == expect
        if recovered:
            assert info['notice']['recovered'] is True
            assert info['notice']['needs_notice'] is True
        return info

    def simple(root, fault):
        worker(root, 'restore', fault=fault)
        restart(root, 'new' if not fault else 'old', recovered=False)

    def crash(root, point, phase='applying', expected='old'):
        death = worker(root, 'restore', fault=point, killed=True)
        assert death['phase'] == phase
        assert journal(root)['phase'] == phase
        if phase == 'applying':
            rescue_hashes(root)
        restart(root, expected, recovered=phase == 'applying')
        # A second clean boot must not duplicate compensation or change files.
        restart(root, expected, recovered=phase == 'applying')

    def twice(root, point):
        worker(root, 'restore', fault='removed_database', killed=True)
        hashes = rescue_hashes(root)
        death = worker(root, 'restart', fault=point, killed=True)
        assert death['phase'] == 'recovering'
        assert journal(root)['phase'] == 'recovering'
        assert rescue_hashes(root) == hashes, 'Recovery consumed its immutable rescue'
        restart(root)
        restart(root)

    def blocked(root, fault):
        worker(root, 'restore', fault='removed_database', killed=True)
        hashes = rescue_hashes(root)
        result = worker(root, 'recover_blocked', fault=fault)
        assert result['blocked'] is True
        assert journal(root)['phase'] == 'recovery_error'
        assert rescue_hashes(root) == hashes, 'Blocked recovery modified rescue files'
        # The whole application process restarts, including native SQLite state.
        restart(root)

    scenarios = {
        'valid_zip': lambda r: simple(r, ''),
        'corrupt_zip': lambda r: simple(r, 'corrupt'),
        'insufficient_space': lambda r: simple(r, 'space'),
        'death_sqlite_removed': lambda r: crash(r, 'removed_database'),
        'death_during_photo_copy': lambda r: crash(r, 'copy_photo'),
        'death_during_document_copy': lambda r: crash(r, 'copy_document'),
        'death_during_svg_copy': lambda r: crash(r, 'copy_icon'),
        'unexpected_death_after_sqlite': lambda r: crash(r, 'applied_database'),
        'second_death_recovery_sqlite': lambda r: twice(r, 'recovered_database'),
        'second_death_recovery_photos': lambda r: twice(r, 'removed_tool_images'),
        'second_death_recovery_documents': lambda r: twice(r, 'removed_tool_documents'),
        'blocked_recovery_preserves_rescue': lambda r: blocked(r, 'recovery_error'),
        'space_failure_during_recovery': lambda r: blocked(r, 'space'),
        'death_before_application': lambda r: crash(r, 'prepared_incoming', 'preparing'),
        'death_after_confirmation': lambda r: crash(r, 'confirmed', 'confirmed', 'new'),
    }
    if args.scenario:
        assert set(args.scenario).issubset(scenarios), 'Unknown scenario'
        scenarios = {name: scenarios[name] for name in args.scenario}
    print(f'Synthetic isolated lab: {lab}', flush=True)
    for name, scenario in scenarios.items():
        root = lab / name
        root.mkdir()
        (root / 'isolated-lab.json').write_text('synthetic-inventory-only')
        print(f'RUN {name}', flush=True)
        started = time.monotonic()
        try:
            worker(root, 'seed')
            scenario(root)
            results.append({'scenario': name, 'result': 'passed',
                            'seconds': round(time.monotonic() - started, 2)})
            print(f'PASS {name}', flush=True)
        except Exception as error:
            results.append({'scenario': name, 'result': 'failed', 'error': str(error)})
            print(f'FAIL {name}: {error}', flush=True)
            # Stop at a genuine discrepancy; never change production or mask it.
            break
    report = {'lab': str(lab), 'commit': subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
        'scenarios': results, 'worker_runs': worker_runs,
        'passed': sum(r['result'] == 'passed' for r in results),
        'failed': sum(r['result'] == 'failed' for r in results),
        'android': 'not available locally; Android integration not executed',
        'production_files_modified': False}
    report_path = lab / 'report.json'
    report_path.write_text(json.dumps(report, indent=2))
    print(f"RESULT passed={report['passed']} failed={report['failed']} workers={len(worker_runs)} report={report_path}", flush=True)
    return 1 if report['failed'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
