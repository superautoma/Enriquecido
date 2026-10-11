// Explicitly launched by scripts/validate_restore_processes.py, outside the
// normal *_test.dart suite. Faults and SIGKILL exist exclusively in this worker.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../lib/main_quill_integrated_test.dart';
import 'restore_process_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real restoration engine in an isolated process',
    () async {
      final env = Platform.environment;
      final root = Directory(env['V122_RESTORE_LAB_ROOT']!);
      final action = env['V122_RESTORE_LAB_ACTION']!;
      final fault = env['V122_RESTORE_LAB_FAULT'] ?? '';
      final resultPath = env['V122_RESTORE_LAB_RESULT']!;
      final canonical = await root.resolveSymbolicLinks();
      expect(
        canonical,
        startsWith('${Directory.systemTemp.path}/v122_restore_lab_'),
      );
      expect(
        await File('${root.path}/isolated-lab.json').readAsString(),
        'synthetic-inventory-only',
      );
      expect(resultPath, startsWith('${root.path}/'));
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final fixture = RestoreProcessFixture(root);
      final backup = File('${root.path}/selected.zip');
      final result = <String, Object?>{'action': action, 'pid': pid};

      Future<void> writeJson(String path, Object? value) =>
          File(path).writeAsString(jsonEncode(value), flush: true);

      Future<Map<String, Object?>> snapshot() async {
        final db = await ToolsDatabase.instance.database;
        expect(
          (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
          'ok',
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        );
        final state = <String, Object?>{};
        for (final row in tables) {
          final table = row['name']! as String;
          expect(table, matches(RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$')));
          final data = [...await db.query(table)];
          data.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
          state[table] = data;
        }
        state['schema'] = await db.rawQuery('PRAGMA user_version');
        final files = <String, String>{};
        for (final area in ['tool_images', 'tool_documents']) {
          await for (final entry in Directory(
            '${fixture.active.path}/$area',
          ).list(recursive: true, followLinks: false)) {
            expect(entry, isNot(isA<Link>()));
            if (entry is File) {
              files[entry.path.substring(fixture.active.path.length)] = sha256
                  .convert(await entry.readAsBytes())
                  .toString();
            }
          }
        }
        state['files'] = files;
        for (final row in await db.query('tool_images')) {
          final path = row['path']! as String;
          expect(path, startsWith('${fixture.active.path}/tool_images/'));
          expect(await File(path).exists(), true);
        }
        for (final row in await db.query('tool_documents')) {
          expect(
            await File(
              '${fixture.active.path}/tool_documents/${row['file_name']}',
            ).exists(),
            true,
          );
        }
        for (final row in await db.query('field_options')) {
          final icon = row['icon_key'];
          if (icon is String && icon.startsWith('custom:')) {
            expect(await File(icon.substring('custom:'.length)).exists(), true);
          }
        }
        // Paths legitimately change when the incoming inventory is relocated.
        return jsonDecode(
              jsonEncode(state).replaceAll(fixture.active.path, '<inventory>'),
            )
            as Map<String, Object?>;
      }

      Future<void> verify(String expected) async {
        final before = jsonDecode(
          await File('${root.path}/$expected.json').readAsString(),
        );
        expect(
          await snapshot(),
          before,
          reason: 'All SQLite tables and asset hashes',
        );
        final originalZip = await File(
          '${root.path}/zip.sha256',
        ).readAsString();
        expect(
          sha256.convert(await backup.readAsBytes()).toString(),
          originalZip,
        );
        expect(
          await Directory(
            '${fixture.active.path}/.safe_restore_v122/operation',
          ).exists(),
          false,
        );
        expect(
          await File(
            '${fixture.active.path}/.safe_restore_v122/journal.json',
          ).exists(),
          false,
        );
        for (final target in [
          'db/gestor_herramientas.db',
          'tool_images',
          'tool_documents',
        ]) {
          for (final suffix in ['.safe_restore_next', '.safe_restore_old']) {
            expect(
              await FileSystemEntity.type(
                '${fixture.active.path}/$target$suffix',
              ),
              FileSystemEntityType.notFound,
            );
          }
        }
        result['verified'] = expected;
      }

      Future<void> kill(String point) async {
        final journal = File(
          '${fixture.active.path}/.safe_restore_v122/journal.json',
        );
        await writeJson('$resultPath.killed', {
          'pid': pid,
          'point': point,
          'phase': jsonDecode(await journal.readAsString())['phase'],
          'signal': 'SIGKILL',
        });
        // The parent verifies this is its Flutter worker and sends SIGKILL.
        // Waiting keeps the exact fault point stable until the OS kills us.
        await Completer<void>().future; // No exception, rollback or teardown.
      }

      if (action == 'seed') {
        await fixture.location('source');
        await fixture.seed('nuevo');
        await writeJson('${root.path}/new.json', await snapshot());
        await (await BackupManager.createBackup()).copy(backup.path);
        await File('${root.path}/zip.sha256').writeAsString(
          sha256.convert(await backup.readAsBytes()).toString(),
          flush: true,
        );
        await fixture.location('target');
        await fixture.seed('anterior');
        await writeJson('${root.path}/old.json', await snapshot());
        result['seeded'] = true;
      } else {
        await fixture.location('target');
        if (fault == 'space') SafeRestore.testFreeBytes = (_) async => 0;
        SafeRestore.testFault = (point) async {
          if (fault == point) await kill(point);
          if (point == 'copy_chunk' &&
              SafeRestore.status.value.phase == RestorePhase.applying) {
            final relative = switch (fault) {
              'copy_photo' => 'tool_images/photo.jpg',
              'copy_icon' => 'tool_images/custom_icons/icon.svg',
              'copy_document' => 'tool_documents/manual.pdf',
              _ => '',
            };
            if (relative.isNotEmpty) {
              final parts = relative.split('/');
              final next = File(
                '${fixture.active.path}/${parts.first}.safe_restore_next/${parts.skip(1).join('/')}',
              );
              final incoming = File(
                '${fixture.active.path}/.safe_restore_v122/operation/incoming/$relative',
              );
              if (await next.exists() &&
                  await next.length() > 0 &&
                  await next.length() < await incoming.length()) {
                await kill('partial_$relative');
              }
            }
          }
          if (fault == 'recovery_error' &&
              point == 'recovery_install_tool_images') {
            throw const FileSystemException('Synthetic recovery write failure');
          }
        };
        if (action == 'restore') {
          if (fault == 'corrupt') {
            final invalid = File('${root.path}/corrupt.zip');
            await invalid.writeAsString('not-a-zip');
            await expectLater(
              BackupManager.restoreBackup(invalid.path),
              throwsA(isA<RestoreFailure>()),
            );
            await verify('old');
          } else if (fault == 'space') {
            await expectLater(
              BackupManager.restoreBackup(backup.path),
              throwsA(
                isA<RestoreFailure>().having(
                  (e) => e.message,
                  'space',
                  contains('espacio'),
                ),
              ),
            );
            SafeRestore.testFreeBytes = null;
            await verify('old');
          } else {
            await BackupManager.restoreBackup(backup.path);
            await verify('new');
            expect(
              fault,
              isEmpty,
              reason: 'The requested SIGKILL must have happened',
            );
          }
        } else if (action == 'recover_blocked') {
          await expectLater(
            SafeRestore.ensureReady(),
            throwsA(
              isA<RestoreFailure>().having((e) => e.blocked, 'blocked', true),
            ),
          );
          expect(SafeRestore.blocked, true);
          await expectLater(
            ToolsDatabase.instance.database,
            throwsA(isA<RestoreFailure>()),
          );
          final journal = jsonDecode(
            await File(
              '${fixture.active.path}/.safe_restore_v122/journal.json',
            ).readAsString(),
          );
          expect(journal['phase'], 'recovery_error');
          final rescue = Directory(
            '${fixture.active.path}/.safe_restore_v122/operation/recovery',
          );
          expect(await rescue.exists(), true);
          final hashes = <String, String>{};
          await for (final entry in rescue.list(recursive: true)) {
            if (entry is File)
              hashes[entry.path.substring(rescue.path.length)] = sha256
                  .convert(await entry.readAsBytes())
                  .toString();
          }
          result['rescue_hashes'] = hashes;
          result['blocked'] = true;
        } else if (action == 'restart') {
          // This is the production SQLite getter: it must recover before access,
          // without resetting runtime state after the fault in the previous process.
          await ToolsDatabase.instance.database;
          await verify(env['V122_RESTORE_LAB_EXPECT'] ?? 'old');
          final notice = File(
            '${fixture.active.path}/.safe_restore_v122/last_result.json',
          );
          if (await notice.exists())
            result['notice'] = jsonDecode(await notice.readAsString());
        } else {
          fail('Unknown isolated action: $action');
        }
      }
      await ToolsDatabase.instance.closeForBackup();
      await writeJson(resultPath, result);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
