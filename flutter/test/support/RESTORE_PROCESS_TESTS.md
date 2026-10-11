# V122: isolated process recovery checks

These files are test infrastructure, not application code. The base is
`e2cb20cc12f63fbfa84fa1754c85e7ee33e8591a` (APK #126).

The completed run is preserved in the [Linux validation summary](../../../docs/VALIDACION_LINUX_RESTAURACION_V122.md)
and its sanitized JSON report. [Android validation](../../../docs/VALIDACION_ANDROID_RESTAURACION_V122.md)
is documented separately and remains pending. Preserving this evidence does not
rerun these tests or modify APK #126.

From the repository root, reuse the installed SDK environment:

```sh
source scripts/v122-env.sh
python3 scripts/validate_restore_processes.py
```

To run one scenario:

```sh
python3 scripts/validate_restore_processes.py --scenario death_sqlite_removed
```

The script executes only `restore_process_worker.dart`, not the 283 existing
tests. Each scenario seeds a new marked `/tmp/v122_restore_lab_*` directory.
The worker refuses an unmarked location outside that prefix. Path-provider is
redirected to that synthetic inventory, and SQLite uses the real FFI database.
`BackupManager.createBackup`, `BackupManager.restoreBackup`, and the production
database startup gate and recovery engine are used without rewriting them.
Linux directory synchronization and normal space checks are real; only the
insufficient-space cases inject a zero free-byte result. Recovery write errors
use the existing debug-only test seam. No production hooks are added.

At a fault checkpoint, the worker writes its PID and durable journal phase,
then waits. The controller verifies that it is its own `flutter_tester` child
and sends the operating system's SIGKILL. The worker cannot run catch, finally,
SQLite shutdown or test teardown. A separate Flutter invocation then attempts
recovery using only the files left on disk. Double interruptions also occur
in separate processes, while the controller verifies that rescue hashes remain
unchanged. Successful recoveries are followed by a second clean cold start.

Synthetic data include a set and component, a trashed article, locations,
loans and their contents/events, maintenance/interventions, custom types/icons,
icon names/favorites/groups, preferences, simulated photo/PDF payloads, and SVG.
Files are large enough for actual partial streamed copies. Final verification
compares every noninternal SQLite table and every inventory file's SHA-256 to
the expected snapshot. It checks SQLite integrity and foreign keys, relocated
asset references, preservation of the selected synthetic ZIP, and cleanup of
the transaction and installation scratch paths. File paths are normalized
only for comparison between the synthetic source and destination.

The JSON report and per-process logs remain in the reported temporary lab.
Logs for intentional SIGKILL workers have nonzero exits by design; the
controller treats them as passing checkpoints only when it sent SIGKILL and
the subsequent recovery verifies the expected inventory. Any other failure
stops the matrix and preserves the lab for inspection. These directories
contain only synthetic data and can be removed after reviewing the report.

## Limits

This is real Linux process-death validation, not an Android instrumentation
test and not a power-loss test. It does not exercise Android's selector,
content URIs, the native StatFs/fsync channel, Android permissions, or low
storage on an actual device. There is no installed-phone access, APK build,
workflow dispatch, commit, or publication in this procedure. An isolated
Android emulator/device check is still needed for those integration paths.
