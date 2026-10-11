part of 'main_quill_integrated_test.dart';

enum RestorePhase {
  idle,
  verifying,
  protecting,
  applying,
  checking,
  recovering,
  blocked,
}

class RestoreStatus {
  const RestoreStatus(this.phase);
  final RestorePhase phase;
  bool get busy => phase != RestorePhase.idle && phase != RestorePhase.blocked;
  String get label => switch (phase) {
    RestorePhase.idle => '',
    RestorePhase.verifying => 'Verificando copia',
    RestorePhase.protecting => 'Protegiendo datos actuales',
    RestorePhase.applying => 'Restaurando inventario',
    RestorePhase.checking => 'Comprobando integridad',
    RestorePhase.recovering => 'Recuperando tus datos anteriores',
    RestorePhase.blocked => 'No se pudo recuperar el inventario',
  };
}

class RestoreFailure implements Exception {
  const RestoreFailure(
    this.message, {
    this.recovered = false,
    this.blocked = false,
  });
  final String message;
  final bool recovered, blocked;
  @override
  String toString() => message;
}

/// Used only by injected test faults to model process death (no catch/rollback).
class RestoreInterruption implements Exception {}

class _RestorePaths {
  _RestorePaths(
    this.root,
    this.database,
    this.images,
    this.documents,
    this.databaseIdentity,
  );
  final Directory root;
  final String database, images, documents;
  final String databaseIdentity;
  Directory get operation => Directory(p.join(root.path, 'operation'));
  File get journal => File(p.join(root.path, 'journal.json'));
  Map<String, String> get destinations => {
    'database': database,
    'tool_images': images,
    'tool_documents': documents,
  };
  String area(String area, String key) => p.join(operation.path, area, key);
}

/// Durable compensation transaction. The recovery snapshot is never consumed:
/// each attempt installs verified copies, so recovery can itself be interrupted.
class SafeRestore {
  SafeRestore._();
  static final status = ValueNotifier(const RestoreStatus(RestorePhase.idle));
  static const recoveredMessage =
      'No se pudo completar la restauración. Hemos recuperado tus datos anteriores.';
  static const storageChannel = MethodChannel(
    'gestor_herramientas/restore_storage',
  );
  static const _access = 'safe_restore_internal_access';
  static bool _running = false;
  static Completer<void>? _completion;
  static Future<bool>? _startup;
  static String? _readyDatabase;
  static bool _recoveryNotice = false;

  // A root rebuilt in the same process need not start disk I/O again. Cold
  // startup, a restore, a blocked recovery and an unread notice still use the gate.
  static bool get readyWithoutNotice =>
      _readyDatabase != null && !_running && !blocked && !_recoveryNotice;

  // Production limits apply before decompression and also to actual stream bytes.
  static const maxZipBytes = 256 * 1024 * 1024;
  static const maxFileBytes = 256 * 1024 * 1024;
  static const maxExpandedBytes = 512 * 1024 * 1024;
  static const maxEntries = 10000;
  static const reserveBytes = 32 * 1024 * 1024;

  /// Test seams; ignored in release builds. Never used on user directories in tests.
  static Future<void> Function(String point)? testFault;
  static Future<int> Function(String path)? testFreeBytes;
  static void resetRuntimeForTest() {
    assert(!_running);
    if (kReleaseMode) return;
    _readyDatabase = null;
    _startup = null;
    _recoveryNotice = false;
    testFault = null;
    testFreeBytes = null;
    status.value = const RestoreStatus(RestorePhase.idle);
  }

  static bool get internal => Zone.current[_access] == true;
  static bool get blocked => status.value.phase == RestorePhase.blocked;
  static Future<void> _fault(String point) async {
    if (!kReleaseMode) await testFault?.call(point);
  }

  static Future<_RestorePaths> _paths() async {
    final docs = await getApplicationDocumentsDirectory();
    // Resolve OS aliases (/data/data vs /data/user/0) only at trusted roots.
    // Links inside inventory and recovery folders remain forbidden.
    final documentsRoot = await docs.resolveSymbolicLinks();
    final identity = await ToolsDatabase.instance.databasePath;
    var parent = p.dirname(identity);
    while (!await Directory(parent).exists()) {
      parent = p.dirname(parent);
    }
    final databaseRoot = p.join(
      await Directory(parent).resolveSymbolicLinks(),
      p.relative(p.dirname(identity), from: parent),
    );
    // app_flutter is private on Android and persists across process death.
    return _RestorePaths(
      Directory(p.join(documentsRoot, '.safe_restore_v122')),
      p.join(databaseRoot, p.basename(identity)),
      p.join(documentsRoot, 'tool_images'),
      p.join(documentsRoot, 'tool_documents'),
      identity,
    );
  }

  static Future<void> beforeDatabaseOpen() async {
    if (internal) return;
    if (_running || blocked)
      throw const RestoreFailure(
        'El inventario está protegido durante la recuperación.',
        blocked: true,
      );
    final path = await ToolsDatabase.instance.databasePath;
    if (_readyDatabase == path) return;
    await ensureReady();
  }

  static Future<bool> ensureReady() {
    if (_startup != null) return _startup!;
    // A security/lifecycle gate can be rebuilt while a restore is still active.
    // Wait for that operation instead of starting a second recovery or clearing it.
    final future = _running
        ? _completion!.future.then((_) => recoverPending())
        : recoverPending();
    _startup = future;
    return future.whenComplete(() {
      if (identical(_startup, future)) _startup = null;
    });
  }

  static Future<T> _exclusive<T>(
    Future<T> Function(_RestorePaths) action,
  ) async {
    if (_running)
      throw const RestoreFailure('Ya hay una restauración en curso.');
    _running = true;
    final completion = Completer<void>();
    _completion = completion;
    RandomAccessFile? lock;
    try {
      final paths = await _paths();
      await _noLinks(paths.root.parent.path);
      await paths.root.create(recursive: true);
      await _noLinks(paths.root.path);
      await _syncDirectory(paths.root.parent.path);
      await _noLinks(paths.journal.path);
      lock = await File(
        p.join(paths.root.path, 'lock'),
      ).open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      return await runZoned(() => action(paths), zoneValues: {_access: true});
    } on RestoreFailure catch (error) {
      // Includes a pending journal or unknown scratch files detected before
      // the restore body: a fatal protection error must not unlock normal saves.
      if (error.blocked) {
        status.value = const RestoreStatus(RestorePhase.blocked);
      }
      rethrow;
    } finally {
      try {
        if (lock != null) {
          try {
            await lock.unlock();
          } finally {
            await lock.close();
          }
        }
      } finally {
        _running = false;
        completion.complete();
        if (identical(_completion, completion)) _completion = null;
        if (!blocked) status.value = const RestoreStatus(RestorePhase.idle);
      }
    }
  }

  static Future<void> restore(String zipPath) => _exclusive((paths) async {
    _readyDatabase = null;
    if (await paths.journal.exists() || await paths.operation.exists()) {
      throw const RestoreFailure(
        'Hay una recuperación pendiente. Reinicia la aplicación o reintenta la recuperación.',
        blocked: true,
      );
    }
    await _checkScratch(paths);
    var phase = 'preparing';
    Map<String, dynamic> journal = {'version': 1, 'phase': phase};
    try {
      status.value = const RestoreStatus(RestorePhase.verifying);
      final selectedPath = await File(zipPath).resolveSymbolicLinks();
      for (final destination in paths.destinations.values) {
        if (p.equals(selectedPath, p.absolute(destination)) ||
            p.isWithin(p.absolute(destination), selectedPath)) {
          throw const RestoreFailure(
            'Selecciona una copia fuera de las carpetas que se van a sustituir.',
          );
        }
      }
      await _writeJournal(paths, journal);
      await paths.operation.create();
      await _extract(
        zipPath,
        Directory(p.join(paths.operation.path, 'incoming')),
        paths,
      );
      final incoming = p.join(paths.operation.path, 'incoming');
      await _prepareDatabase(incoming, paths);
      await _fault('prepared_incoming');

      phase = 'protecting';
      journal['phase'] = phase;
      await _writeJournal(paths, journal);
      status.value = const RestoreStatus(RestorePhase.protecting);
      await ToolsDatabase.instance.closeForRestore();
      await _fault('closed_database');
      final originals = <String, dynamic>{};
      for (final entry in paths.destinations.entries) {
        await _noLinks(entry.value);
        originals[entry.key] = await _receipt(entry.value);
      }
      final originalBytes = _receiptBytes(originals);
      final incomingBytes = await _treeBytes(incoming);
      // Snapshot + installation copy + another complete rollback copy + margin.
      await _space(paths, originalBytes * 2 + incomingBytes + reserveBytes);
      for (final entry in paths.destinations.entries) {
        await _fault('snapshot_${entry.key}');
        await _copy(entry.value, paths.area('recovery', entry.key));
        await _verifyReceipt(
          paths.area('recovery', entry.key),
          originals[entry.key],
        );
      }
      await _validateDatabase(
        paths.area('recovery', 'database'),
        paths,
        assetRoot: p.join(paths.operation.path, 'recovery'),
      );
      journal['originals'] = originals;
      phase = 'prepared';
      journal['phase'] = phase;
      await _writeJournal(paths, journal);
      await _fault('snapshot_verified');
      await _space(paths, originalBytes + incomingBytes + reserveBytes);

      // No live destination may change until this phase is durably recorded.
      phase = 'applying';
      journal['phase'] = phase;
      await _writeJournal(paths, journal);
      status.value = const RestoreStatus(RestorePhase.applying);
      for (final entry in paths.destinations.entries) {
        await _install(
          entry.key == 'database'
              ? p.join(incoming, 'database', 'gestor_herramientas.db')
              : p.join(incoming, entry.key),
          entry.value,
          entry.key,
        );
        await _fault('applied_${entry.key}');
      }
      phase = 'checking';
      journal['phase'] = phase;
      await _writeJournal(paths, journal);
      status.value = const RestoreStatus(RestorePhase.checking);
      await _validateDatabase(paths.database, paths);
      await _fault('live_checked');
      await ToolsDatabase.instance.reopen();
      await ToolsDatabase.instance.loadTools(includeComponents: true);
      await loadInventoryPreferences();
      await ButtonFeedbackController.instance.load();
      await loadIconNames();
      await loadIconSettings();
      await syncManagementReminders();
      await ToolsDatabase.instance.closeForRestore();
      await _validateDatabase(paths.database, paths);
      // Point of confirmation: a crash after this record keeps the new inventory.
      journal['phase'] = 'confirmed';
      await _writeJournal(paths, journal);
      phase = 'confirmed';
      await _fault('confirmed');
      await _cleanup(paths);
      _readyDatabase = paths.databaseIdentity;
    } catch (error) {
      if (error is RestoreInterruption) rethrow;
      if (phase == 'confirmed') {
        // Cleanup may be retried at startup. A durable commit must never roll back.
        _readyDatabase = paths.databaseIdentity;
        return;
      }
      if (const ['applying', 'checking'].contains(phase)) {
        try {
          await _recover(paths, journal, failurePhase: phase);
        } catch (recoveryError) {
          if (recoveryError is RestoreInterruption) rethrow;
          status.value = const RestoreStatus(RestorePhase.blocked);
          throw const RestoreFailure(
            'No se pudo recuperar el inventario. Conserva los datos de la aplicación y reintenta la recuperación.',
            blocked: true,
          );
        }
        throw const RestoreFailure(recoveredMessage, recovered: true);
      }
      // Preparation and snapshot faults cannot have modified live destinations.
      if (journal['phase'] != 'confirmed') {
        await _recordResult(paths, phase, false);
        await _cleanup(paths);
      }
      throw error is RestoreFailure
          ? error
          : const RestoreFailure(
              'No se pudo verificar o proteger la copia. El inventario no se ha sustituido.',
            );
    }
  });

  /// Called before the first normal SQLite open, and by the startup/retry UI.
  /// Returns true only after the old inventory has been restored and verified.
  static Future<bool> recoverPending() => _exclusive((paths) async {
    status.value = const RestoreStatus(RestorePhase.verifying);
    try {
      if (!await paths.journal.exists()) {
        if (await paths.operation.exists())
          throw const FormatException('Missing journal');
        await _checkScratch(paths);
        _readyDatabase = paths.databaseIdentity;
        final notice = File(p.join(paths.root.path, 'last_result.json'));
        if (await notice.exists()) {
          final value = jsonDecode(await notice.readAsString());
          _recoveryNotice =
              value is Map &&
              value['recovered'] == true &&
              value['needs_notice'] == true;
          return _recoveryNotice;
        }
        _recoveryNotice = false;
        return false;
      }
      final raw = jsonDecode(await paths.journal.readAsString());
      if (raw is! Map<String, dynamic> || raw['version'] != 1)
        throw const FormatException('Invalid journal');
      final phase = raw['phase'];
      if (const ['preparing', 'protecting', 'prepared'].contains(phase)) {
        // Live data has never been touched, even if the snapshot is incomplete.
        await _recordResult(paths, phase as String, false);
        await _cleanup(paths);
        _readyDatabase = paths.databaseIdentity;
        return false;
      }
      if (phase == 'confirmed' || phase == 'recovered') {
        await _validateDatabase(paths.database, paths);
        if (phase == 'recovered')
          await _recordResult(
            paths,
            raw['failure_phase'] as String? ?? 'recovering',
            true,
          );
        await _cleanup(paths);
        _readyDatabase = paths.databaseIdentity;
        return phase == 'recovered';
      }
      if (!const [
        'applying',
        'checking',
        'recovering',
        'recovery_error',
      ].contains(phase)) {
        throw const FormatException('Unknown journal phase');
      }
      await _recover(
        paths,
        raw,
        failurePhase: raw['failure_phase'] as String? ?? phase as String,
      );
      return true;
    } catch (error) {
      if (error is RestoreInterruption) rethrow;
      status.value = const RestoreStatus(RestorePhase.blocked);
      throw const RestoreFailure(
        'No se pudo recuperar el inventario. Conserva los datos de la aplicación y reintenta la recuperación.',
        blocked: true,
      );
    }
  });

  static Future<void> _recover(
    _RestorePaths paths,
    Map<String, dynamic> journal, {
    required String failurePhase,
  }) async {
    status.value = const RestoreStatus(RestorePhase.recovering);
    await ToolsDatabase.instance.closeForRestore();
    var verified = false;
    try {
      final originals = journal['originals'];
      if (originals is! Map ||
          originals.keys
              .toSet()
              .difference(paths.destinations.keys.toSet())
              .isNotEmpty ||
          originals.length != paths.destinations.length)
        throw const FormatException('Invalid recovery manifest');
      // Verify the entire immutable recovery point before changing anything.
      for (final key in paths.destinations.keys) {
        await _verifyReceipt(paths.area('recovery', key), originals[key]);
      }
      await _validateDatabase(
        paths.area('recovery', 'database'),
        paths,
        assetRoot: p.join(paths.operation.path, 'recovery'),
      );
      await _space(
        paths,
        _receiptBytes(Map<String, dynamic>.from(originals)) + reserveBytes,
      );
      journal['phase'] = 'recovering';
      journal['failure_phase'] = failurePhase;
      await _writeJournal(paths, journal);
      await _fault('recovering');
      for (final entry in paths.destinations.entries) {
        await _install(
          paths.area('recovery', entry.key),
          entry.value,
          entry.key,
        );
        await _fault('recovered_${entry.key}');
      }
      for (final entry in paths.destinations.entries) {
        await _verifyReceipt(entry.value, originals[entry.key]);
      }
      await _validateDatabase(paths.database, paths);
      await ToolsDatabase.instance.reopen();
      await ToolsDatabase.instance.loadTools(includeComponents: true);
      await loadInventoryPreferences();
      await ButtonFeedbackController.instance.load();
      await loadIconNames();
      await loadIconSettings();
      await syncManagementReminders();
      await ToolsDatabase.instance.closeForRestore();
      await _validateDatabase(paths.database, paths);
      await _fault('recovery_checked');
      journal['phase'] = 'recovered';
      await _writeJournal(paths, journal);
      verified = true;
      await _fault('recovery_confirmed');
      await _recordResult(paths, failurePhase, true);
      await _cleanup(paths);
      _readyDatabase = paths.databaseIdentity;
    } catch (error) {
      if (error is RestoreInterruption) rethrow;
      if (verified) {
        _readyDatabase = paths.databaseIdentity;
        return; // Terminal cleanup can be retried; never consume recovery twice.
      }
      journal['phase'] = 'recovery_error';
      journal['failure_phase'] = failurePhase;
      // Best effort only: never discard an existing journal if storage is full.
      try {
        await _writeJournal(paths, journal);
      } catch (_) {}
      status.value = const RestoreStatus(RestorePhase.blocked);
      rethrow;
    }
  }

  static Future<void> _recordResult(
    _RestorePaths paths,
    String phase,
    bool recovered,
  ) async {
    await _atomicJson(
      File(p.join(paths.root.path, 'last_result.json')),
      {
        'phase': phase,
        'recovered': recovered,
        'time': DateTime.now().toUtc().toIso8601String(),
        'needs_notice': recovered,
      },
    ); // No paths, filenames, SQL, credentials, borrower names or exception text.
    _recoveryNotice = recovered;
  }

  static Future<void> acknowledgeRecovery() async {
    final paths = await _paths();
    final file = File(p.join(paths.root.path, 'last_result.json'));
    if (!await file.exists()) return;
    final result = jsonDecode(await file.readAsString());
    if (result is Map<String, dynamic>) {
      result['needs_notice'] = false;
      await _atomicJson(file, result);
      _recoveryNotice = false;
    }
  }

  static Future<void> _writeJournal(
    _RestorePaths paths,
    Map<String, dynamic> journal,
  ) => _atomicJson(paths.journal, journal);

  static Future<void> _atomicJson(File file, Object value) async {
    final next = File('${file.path}.next');
    await next.writeAsString(jsonEncode(value), flush: true);
    await next.rename(file.path);
    await _syncDirectory(file.parent.path);
  }

  static Future<void> _syncDirectory(String path) async {
    if (Platform.isAndroid) {
      await storageChannel.invokeMethod<void>('syncDirectory', {'path': path});
    } else if (Platform.isLinux) {
      final result = await Process.run('sync', ['-f', path]);
      if (result.exitCode != 0)
        throw const RestoreFailure(
          'No se pudo confirmar la escritura en almacenamiento.',
        );
    } else {
      throw const RestoreFailure(
        'La restauración segura requiere Android o Linux.',
      );
    }
  }

  static Future<int> _freeBytes(String path) async {
    if (!kReleaseMode && testFreeBytes != null) return testFreeBytes!(path);
    if (Platform.isAndroid) {
      final bytes = await storageChannel.invokeMethod<int>('freeBytes', {
        'path': path,
      });
      if (bytes != null && bytes >= 0) return bytes;
    } else if (Platform.isLinux) {
      final result = await Process.run('df', ['-Pk', path]);
      if (result.exitCode == 0) {
        final columns = result.stdout
            .toString()
            .trim()
            .split('\n')
            .last
            .trim()
            .split(RegExp(r'\s+'));
        if (columns.length >= 6) return int.parse(columns[3]) * 1024;
      }
    }
    throw const RestoreFailure(
      'No se pudo verificar el espacio libre. No se ha sustituido el inventario.',
    );
  }

  static Future<void> _space(_RestorePaths paths, int bytes) async {
    // Conservatively require the full budget on each involved filesystem.
    for (final path in {
      paths.root.path,
      p.dirname(paths.database),
      p.dirname(paths.images),
      p.dirname(paths.documents),
    }) {
      await Directory(path).create(recursive: true);
      if (await _freeBytes(path) < bytes)
        throw const RestoreFailure(
          'No hay espacio libre suficiente para restaurar y recuperar los datos.',
        );
    }
  }

  static Future<void> _noLinks(String path) async {
    var current = p.absolute(path);
    while (true) {
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FormatException('Unsafe filesystem link');
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
  }

  static Future<Map<String, dynamic>> _receipt(String path) async {
    await _noLinks(path);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return {'kind': 'absent'};
    if (type == FileSystemEntityType.file)
      return {
        'kind': 'file',
        'bytes': await File(path).length(),
        'sha256': (await crypto.sha256.bind(File(path).openRead()).first)
            .toString(),
      };
    if (type != FileSystemEntityType.directory)
      throw const FormatException('Unexpected file type');
    final files = <String, dynamic>{};
    final dirs = <String>[];
    await for (final entity in Directory(
      path,
    ).list(recursive: true, followLinks: false)) {
      final name = p.relative(entity.path, from: path);
      if (entity is Link) throw const FormatException('Unsafe filesystem link');
      if (entity is Directory) {
        dirs.add(name);
      } else if (entity is File) {
        files[name] = await _receipt(entity.path);
      } else {
        throw const FormatException('Unexpected file type');
      }
    }
    dirs.sort();
    return {'kind': 'directory', 'files': files, 'directories': dirs};
  }

  static int _receiptBytes(Map<String, dynamic> receipt) {
    var bytes = 0;
    for (final value in receipt.values) {
      if (value is Map) {
        if (value['kind'] == 'file') bytes += value['bytes'] as int;
        if (value['kind'] == 'directory')
          bytes += _receiptBytes(
            Map<String, dynamic>.from(value['files'] as Map),
          );
      }
    }
    return bytes;
  }

  static Future<int> _treeBytes(String path) async {
    final receipt = await _receipt(path);
    return _receiptBytes({'tree': receipt});
  }

  static Future<void> _verifyReceipt(String path, Object? expected) async {
    if (expected is! Map) throw const FormatException('Invalid file manifest');
    final actual = await _receipt(path);
    // JSON key ordering is not significant; directory ordering is canonical.
    bool equal(Object? a, Object? b) {
      if (a is Map && b is Map)
        return a.length == b.length &&
            a.keys.every((k) => b.containsKey(k) && equal(a[k], b[k]));
      if (a is List && b is List)
        return a.length == b.length &&
            List.generate(a.length, (i) => equal(a[i], b[i])).every((e) => e);
      return a == b;
    }

    if (!equal(actual, expected))
      throw const FormatException('File verification failed');
  }

  static Future<void> _copy(String source, String target) async {
    await _noLinks(source);
    await _noLinks(target);
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.file) {
      await Directory(p.dirname(target)).create(recursive: true);
      final output = await File(target).open(mode: FileMode.writeOnly);
      try {
        await for (final chunk in File(source).openRead()) {
          await output.writeFrom(chunk);
          await _fault('copy_chunk');
        }
        await output.flush();
      } finally {
        await output.close();
      }
    } else if (type == FileSystemEntityType.directory) {
      await Directory(target).create(recursive: true);
      await for (final entity in Directory(source).list(followLinks: false)) {
        await _copy(entity.path, p.join(target, p.basename(entity.path)));
      }
      await _syncDirectory(target);
    } else {
      throw const FormatException('Unsafe filesystem entry');
    }
    await _syncDirectory(p.dirname(target));
  }

  static Future<void> _delete(String path) async {
    await _noLinks(path);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.file)
      await File(path).delete();
    else if (type == FileSystemEntityType.directory)
      await Directory(path).delete(recursive: true);
    else if (type != FileSystemEntityType.notFound)
      throw const FormatException('Unsafe filesystem entry');
  }

  static Future<void> _install(String source, String target, String key) async {
    await _noLinks(target);
    final next = '$target.safe_restore_next';
    final old = '$target.safe_restore_old';
    await _delete(next);
    final receipt = await _receipt(source);
    await _copy(source, next);
    await _verifyReceipt(next, receipt);
    await _fault(
      status.value.phase == RestorePhase.recovering
          ? 'recovery_install_$key'
          : 'install_$key',
    );
    // SQLite is closed and checkpointed; sidecars must never attach to a new DB.
    if (key == 'database') {
      for (final suffix in ['-wal', '-shm', '-journal']) {
        await _delete('$target$suffix');
      }
    }
    await _delete(old);
    final type = await FileSystemEntity.type(target, followLinks: false);
    if (type == FileSystemEntityType.file)
      await File(target).rename(old);
    else if (type == FileSystemEntityType.directory)
      await Directory(target).rename(old);
    await _syncDirectory(p.dirname(target));
    await _fault('removed_$key');
    if (receipt['kind'] == 'file')
      await File(next).rename(target);
    else if (receipt['kind'] == 'directory')
      await Directory(next).rename(target);
    await _syncDirectory(p.dirname(target));
    await _verifyReceipt(target, receipt);
  }

  static Future<void> _cleanup(_RestorePaths paths) async {
    await _fault('cleanup');
    // Called only before application, or after a durable verified terminal state.
    for (final target in paths.destinations.values) {
      await _delete('$target.safe_restore_next');
      await _delete('$target.safe_restore_old');
      await _syncDirectory(p.dirname(target));
    }
    await _delete(paths.operation.path);
    await _syncDirectory(paths.root.path);
    if (await paths.journal.exists()) await paths.journal.delete();
    await _delete('${paths.journal.path}.next');
    await _syncDirectory(paths.root.path);
  }

  static Future<void> _checkScratch(_RestorePaths paths) async {
    for (final target in paths.destinations.values) {
      for (final suffix in ['.safe_restore_next', '.safe_restore_old']) {
        if (await FileSystemEntity.type('$target$suffix', followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw const RestoreFailure(
            'Hay archivos de recuperación sin registro. Se conservan para su revisión.',
            blocked: true,
          );
        }
      }
    }
  }

  static String _safeName(String name, {bool directory = false}) {
    if (directory && name.endsWith('/'))
      name = name.substring(0, name.length - 1);
    if (name.isEmpty ||
        name.length > 1024 ||
        name.contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
        p.posix.isAbsolute(name) ||
        RegExp(r'^[a-zA-Z]:').hasMatch(name) ||
        name
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..') ||
        p.posix.normalize(name) != name)
      throw const FormatException('Unsafe ZIP path');
    return name;
  }

  static Future<void> _extract(
    String zipPath,
    Directory destination,
    _RestorePaths paths,
  ) async {
    final source = File(zipPath);
    final length = await source.length();
    if (length < 22 || length > maxZipBytes)
      throw const RestoreFailure(
        'El tamaño del ZIP no es compatible con la restauración segura.',
      );
    final input = await source.open();
    final entries = <_RestoreZipEntry>[];
    var total = 0;
    try {
      final tailStart = math.max(0, length - 65557);
      await input.setPosition(tailStart);
      final tail = ByteData.sublistView(await input.read(length - tailStart));
      var end = -1;
      for (var i = tail.lengthInBytes - 22; i >= 0; i--) {
        if (tail.getUint32(i, Endian.little) == 0x06054b50 &&
            i + 22 + tail.getUint16(i + 20, Endian.little) ==
                tail.lengthInBytes) {
          end = i;
          break;
        }
      }
      if (end < 0 ||
          tail.getUint16(end + 4, Endian.little) != 0 ||
          tail.getUint16(end + 6, Endian.little) != 0)
        throw const FormatException('Invalid ZIP directory');
      final count = tail.getUint16(end + 10, Endian.little);
      final centralSize = tail.getUint32(end + 12, Endian.little);
      final central = tail.getUint32(end + 16, Endian.little);
      if (count == 0 ||
          count > maxEntries ||
          count != tail.getUint16(end + 8, Endian.little) ||
          centralSize > 8 * 1024 * 1024 ||
          central + centralSize != tailStart + end)
        throw const FormatException('ZIP limits or directory invalid');
      await input.setPosition(central);
      final names = <String, bool>{};
      for (var i = 0; i < count; i++) {
        final header = await input.read(46);
        if (header.length != 46) throw const FormatException('Truncated ZIP');
        final h = ByteData.sublistView(header);
        if (h.getUint32(0, Endian.little) != 0x02014b50)
          throw const FormatException('Invalid ZIP header');
        final flags = h.getUint16(8, Endian.little);
        final method = h.getUint16(10, Endian.little);
        final crc = h.getUint32(16, Endian.little);
        final compressed = h.getUint32(20, Endian.little);
        final size = h.getUint32(24, Endian.little);
        final nameSize = h.getUint16(28, Endian.little);
        final extra = h.getUint16(30, Endian.little),
            comment = h.getUint16(32, Endian.little);
        final mode = h.getUint32(38, Endian.little) >> 16;
        final offset = h.getUint32(42, Endian.little);
        if ((flags & 0x41) != 0 ||
            ![0, 8].contains(method) ||
            size > maxFileBytes ||
            compressed > maxZipBytes ||
            nameSize == 0 ||
            nameSize > 1024 ||
            extra + comment > 4096 ||
            offset + 30 + compressed > central ||
            (mode & 0xf000) != 0 && ![0x8000, 0x4000].contains(mode & 0xf000))
          throw const FormatException('Unsafe or unsupported ZIP entry');
        final nameBytes = await input.read(nameSize);
        final rawName = utf8.decode(nameBytes);
        final directory = rawName.endsWith('/');
        final name = _safeName(rawName, directory: directory);
        if (names.containsKey(name) ||
            (directory && (size != 0 || compressed != 0)))
          throw const FormatException('Duplicate or conflicting ZIP entry');
        names[name] = directory;
        if (!(name == 'manifest.json' ||
            name == 'database' ||
            name == 'database/gestor_herramientas.db' ||
            name == 'tool_images' ||
            name.startsWith('tool_images/') ||
            name == 'tool_documents' ||
            name.startsWith('tool_documents/')))
          throw const FormatException('Unexpected backup entry');
        total += size;
        if (total > maxExpandedBytes)
          throw const FormatException('Expanded ZIP limit exceeded');
        entries.add(
          _RestoreZipEntry(
            name,
            nameBytes,
            directory,
            method,
            flags,
            crc,
            size,
            compressed,
            offset,
          ),
        );
        await input.setPosition(await input.position() + extra + comment);
      }
      if (await input.position() != central + centralSize)
        throw const FormatException('Invalid central directory length');
      for (final name in names.keys) {
        var parent = p.posix.dirname(name);
        while (parent != '.') {
          if (names[parent] == false)
            throw const FormatException('Conflicting ZIP paths');
          parent = p.posix.dirname(parent);
        }
      }
      await _space(paths, total * 2 + reserveBytes);
      await destination.create();
      for (final entry in entries) {
        await input.setPosition(entry.offset);
        final header = await input.read(30);
        if (header.length != 30)
          throw const FormatException('Truncated local header');
        final h = ByteData.sublistView(header);
        // Older archive encoders set UTF-8 only in the central header, and
        // streaming writers differ on the descriptor bit. Raw names must match.
        if (h.getUint32(0, Endian.little) != 0x04034b50 ||
            (h.getUint16(6, Endian.little) & ~0x808) !=
                (entry.flags & ~0x808) ||
            h.getUint16(8, Endian.little) != entry.method ||
            h.getUint16(26, Endian.little) != entry.nameBytes.length)
          throw const FormatException('Local ZIP header mismatch');
        final localName = await input.read(entry.nameBytes.length);
        if (base64Encode(localName) != base64Encode(entry.nameBytes))
          throw const FormatException('Local ZIP path mismatch');
        final start =
            entry.offset +
            30 +
            entry.nameBytes.length +
            h.getUint16(28, Endian.little);
        if (start + entry.compressed > central)
          throw const FormatException('ZIP content outside archive');
        final target = p.join(destination.path, entry.name);
        if (entry.directory) {
          await Directory(target).create(recursive: true);
          continue;
        }
        await Directory(p.dirname(target)).create(recursive: true);
        final output = await File(target).open(mode: FileMode.writeOnly);
        var expanded = 0, crc = 0;
        try {
          Stream<List<int>> stream = source.openRead(
            start,
            start + entry.compressed,
          );
          if (entry.method == 8)
            stream = restore_io.ZLibDecoder(raw: true).bind(stream);
          await for (final chunk in stream) {
            expanded += chunk.length;
            if (expanded > entry.size || expanded > maxFileBytes)
              throw const FormatException('Decompression size exceeded');
            crc = getCrc32(chunk, crc);
            await output.writeFrom(chunk);
          }
          await output.flush();
        } finally {
          await output.close();
        }
        if (expanded != entry.size || crc != entry.crc)
          throw const FormatException('ZIP checksum mismatch');
      }
    } finally {
      await input.close();
    }
  }

  static Future<void> _prepareDatabase(
    String incoming,
    _RestorePaths paths,
  ) async {
    final manifestFile = File(p.join(incoming, 'manifest.json'));
    if (!await manifestFile.exists() || await manifestFile.length() > 65536)
      throw const FormatException('Missing manifest');
    final manifest = jsonDecode(await manifestFile.readAsString());
    if (manifest is! Map ||
        manifest['format'] != 'gestor_herramientas_backup' ||
        !const [1, 2].contains(manifest['format_version']) ||
        manifest['database'] != 'database/gestor_herramientas.db' ||
        manifest['images'] != 'tool_images' ||
        manifest['documents'] != null &&
            manifest['documents'] != 'tool_documents')
      throw const FormatException('Unsupported backup manifest');
    final path = p.join(incoming, 'database', 'gestor_herramientas.db');
    await _validateSqlite(path, migrate: true);
    for (final key in ['tool_images', 'tool_documents']) {
      await Directory(p.join(incoming, key)).create(recursive: true);
    }
    await _validateDatabase(path, paths, assetRoot: incoming, rewrite: true);
  }

  static Future<void> _validateSqlite(
    String path, {
    bool migrate = false,
  }) async {
    if (!await File(path).exists())
      throw const FormatException('Missing SQLite database');
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true, singleInstance: false);
      final version = await db.getVersion();
      if (version < 1 ||
          version > toolsDatabaseVersion ||
          (await db.rawQuery(
            'PRAGMA integrity_check',
          )).any((r) => r.values.first != 'ok'))
        throw const FormatException('Incompatible or damaged SQLite');
      if ((await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type IN ('trigger','view') OR sql LIKE '%CREATE VIRTUAL TABLE%'",
      )).isNotEmpty) {
        throw const FormatException('Unexpected executable database objects');
      }
      await db.close();
      db = null;
      if (migrate && version < toolsDatabaseVersion) {
        db = await openDatabase(
          path,
          version: toolsDatabaseVersion,
          singleInstance: false,
          onUpgrade: ToolsDatabase._upgradeSchema,
        );
      }
    } finally {
      if (db != null) await db.close();
    }
  }

  static Future<void> _validateDatabase(
    String path,
    _RestorePaths paths, {
    String? assetRoot,
    bool rewrite = false,
  }) async {
    await _validateSqlite(path);
    final db = await openDatabase(
      path,
      readOnly: !rewrite,
      singleInstance: false,
    );
    try {
      if (await db.getVersion() != toolsDatabaseVersion ||
          (await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty)
        throw const FormatException('Invalid database relations');
      // Compare every required table/column against the current schema, created
      // in memory. This does not introduce or change a schema version.
      final schema = await openDatabase(
        inMemoryDatabasePath,
        version: toolsDatabaseVersion,
        singleInstance: false,
        onCreate: ToolsDatabase._createSchema,
      );
      try {
        final tables = await schema.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name!='android_metadata'",
        );
        for (final table in tables) {
          final name = table['name'] as String;
          final actual = await db.rawQuery('PRAGMA table_info($name)');
          final required = await schema.rawQuery('PRAGMA table_info($name)');
          for (final column in required) {
            if (!actual.any(
              (row) =>
                  row['name'] == column['name'] &&
                  row['type'].toString().toUpperCase() ==
                      column['type'].toString().toUpperCase() &&
                  row['pk'] == column['pk'],
            )) {
              throw const FormatException('Incompatible database schema');
            }
          }
          // Valid current rows alone cannot replace the constraints relied on
          // by future saves/deletions. Keep the existing declared relationships.
          final actualKeys = await db.rawQuery(
            'PRAGMA foreign_key_list($name)',
          );
          for (final key in await schema.rawQuery(
            'PRAGMA foreign_key_list($name)',
          )) {
            if (!actualKeys.any(
              (row) => const [
                'table',
                'from',
                'to',
                'on_update',
                'on_delete',
              ].every((field) => row[field] == key[field]),
            )) {
              throw const FormatException(
                'Missing database relationship constraint',
              );
            }
          }
        }
        if ((await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type IN ('trigger','view') OR sql LIKE '%CREATE VIRTUAL TABLE%'",
        )).isNotEmpty) {
          throw const FormatException('Unexpected executable database objects');
        }
      } finally {
        await schema.close();
      }
      // Parent relationships are not declared as SQLite foreign keys.
      if ((await db.rawQuery(
            '''SELECT t.id FROM tools t LEFT JOIN tools p ON t.parent_id=p.id
        WHERE t.parent_id IS NOT NULL AND (p.id IS NULL OR p.is_set!=1 OR p.parent_id IS NOT NULL
        OR t.is_set=1 OR t.id=p.id OR (p.deleted_at!='' AND t.deleted_at='')) LIMIT 1''',
          )).isNotEmpty ||
          (await db.rawQuery(
            '''SELECT c.id FROM loan_contents c JOIN tool_loans l ON c.loan_id=l.id
            JOIN tools t ON c.component_id=t.id WHERE t.parent_id!=l.tool_id OR t.parent_id IS NULL LIMIT 1''',
          )).isNotEmpty)
        throw const FormatException('Invalid set or loan relationship');
      // Check relationships explicitly as a malformed source can omit FK clauses.
      for (final relation in const [
        ['tool_images', 'tool_id', 'tools'],
        ['tool_loans', 'tool_id', 'tools'],
        ['loan_contents', 'loan_id', 'tool_loans'],
        ['loan_contents', 'component_id', 'tools'],
        ['loan_events', 'loan_id', 'tool_loans'],
        ['maintenance_tasks', 'tool_id', 'tools'],
        ['maintenance_records', 'task_id', 'maintenance_tasks'],
        ['tool_documents', 'tool_id', 'tools'],
        ['tool_documents', 'loan_id', 'tool_loans'],
        ['tool_documents', 'task_id', 'maintenance_tasks'],
      ]) {
        if ((await db.rawQuery(
          'SELECT a.id FROM ${relation[0]} a LEFT JOIN ${relation[2]} b ON a.${relation[1]}=b.id WHERE a.${relation[1]} IS NOT NULL AND b.id IS NULL LIMIT 1',
        )).isNotEmpty)
          throw const FormatException('Orphan related record');
      }
      for (final row in await db.query('tools')) {
        final tool = ToolItem.fromMap(row);
        if (tool.name.trim().isEmpty ||
            !tool.quantity.isFinite ||
            tool.quantity < 0 ||
            (tool.deletedAt.isEmpty != tool.trashGroup.isEmpty) ||
            (tool.deletedAt.isNotEmpty &&
                DateTime.tryParse(tool.deletedAt) == null)) {
          throw const FormatException('Invalid tool or trash state');
        }
      }
      for (final row in await db.query('tool_loans')) {
        ToolLoan.fromMap(row);
        final quantity = row['quantity'] as num,
            returned = row['returned_quantity'] as num;
        if (!quantity.isFinite ||
            !returned.isFinite ||
            quantity < 0 ||
            returned < 0 ||
            returned > quantity)
          throw const FormatException('Invalid loan quantities');
      }
      for (final row in await db.query('maintenance_tasks')) {
        MaintenanceTask.fromMap(row);
      }
      for (final row in await db.query('maintenance_records')) {
        MaintenanceRecord.fromMap(row);
      }
      for (final row in await db.query(
        'management_settings',
        where: 'key IN (?,?)',
        whereArgs: [inventoryPreferencesKey, buttonFeedbackSettingsKey],
      )) {
        if (jsonDecode(row['value'] as String) is! Map)
          throw const FormatException('Invalid inventory preferences');
      }
      final imageRoot = assetRoot == null
          ? paths.images
          : p.join(assetRoot, 'tool_images');
      final documentRoot = assetRoot == null
          ? paths.documents
          : p.join(assetRoot, 'tool_documents');
      Future<String> image(String original, {bool icon = false}) async {
        final normalized = original.replaceAll('\\', '/');
        final marker = normalized.lastIndexOf('/tool_images/');
        var relative = marker >= 0
            ? normalized.substring(marker + 13)
            : p.posix.basename(normalized);
        if (icon) relative = 'custom_icons/${p.posix.basename(normalized)}';
        relative = _safeName(relative);
        final file = File(p.join(imageRoot, relative));
        await _noLinks(file.path);
        if (!await file.exists())
          throw const FormatException('Missing referenced image or icon');
        return p.join(paths.images, relative);
      }

      for (final row in await db.query('tool_images')) {
        final resolved = await image(row['path'] as String);
        if (rewrite)
          await db.update(
            'tool_images',
            {'path': resolved},
            where: 'id=?',
            whereArgs: [row['id']],
          );
      }
      for (final row in await db.query('tools')) {
        final original = row['image_path'] as String;
        if (original.isNotEmpty) {
          final resolved = await image(original);
          if (rewrite)
            await db.update(
              'tools',
              {'image_path': resolved},
              where: 'id=?',
              whereArgs: [row['id']],
            );
        }
      }
      for (final row in await db.query('tool_documents')) {
        final name = row['file_name'] as String;
        if (name.isNotEmpty) {
          if (_safeName(name) != p.posix.basename(name))
            throw const FormatException('Invalid document filename');
          final file = File(p.join(documentRoot, name));
          await _noLinks(file.path);
          if (!await file.exists())
            throw const FormatException('Missing referenced document');
        }
      }
      for (final row in await db.query('field_options')) {
        final key = row['icon_key'] as String;
        if (isCustomIconKey(key)) {
          final resolved = await image(customIconPathFromKey(key), icon: true);
          if (rewrite)
            await db.update(
              'field_options',
              {'icon_key': 'custom:$resolved'},
              where: 'id=?',
              whereArgs: [row['id']],
            );
        }
      }
      // Settings/aliases and SVG metadata stay byte-identical; validate JSON now,
      // rather than silently falling back to defaults after a damaged restore.
      if (await Directory(imageRoot).exists()) {
        await for (final file in Directory(
          imageRoot,
        ).list(recursive: true, followLinks: false)) {
          if (file is Link) throw const FormatException('Unsafe asset link');
          if (file is File && file.path.endsWith('.json')) {
            if (await file.length() > 4 * 1024 * 1024 ||
                jsonDecode(await file.readAsString()) is! Map)
              throw const FormatException('Invalid icon metadata');
          }
        }
      }
      if ((await db.rawQuery(
        'PRAGMA integrity_check',
      )).any((r) => r.values.first != 'ok'))
        throw const FormatException('SQLite integrity failed');
    } finally {
      await db.close();
    }
  }
}

class _RestoreZipEntry {
  _RestoreZipEntry(
    this.name,
    this.nameBytes,
    this.directory,
    this.method,
    this.flags,
    this.crc,
    this.size,
    this.compressed,
    this.offset,
  );
  final String name;
  final List<int> nameBytes;
  final bool directory;
  final int method, flags, crc, size, compressed, offset;
}
