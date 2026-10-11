import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/main_quill_integrated_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, active;
  late String backup;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> location(String name) async {
    await ToolsDatabase.instance.closeForBackup();
    active = Directory('${root.path}/$name');
    await active.create();
    await databaseFactory.setDatabasesPath('${active.path}/db');
  }

  Future<void> seed(String name) async {
    final images = Directory('${active.path}/tool_images/custom_icons');
    await images.create(recursive: true);
    await File(
      '${active.path}/tool_images/photo.jpg',
    ).writeAsString('photo-$name');
    await File(
      '${images.path}/icon.svg',
    ).writeAsString('<svg xmlns="http://www.w3.org/2000/svg"/>');
    await File(
      '${images.path}/icon.svg.group.json',
    ).writeAsString('{"group":"Mis iconos"}');
    await File(
      '${active.path}/tool_images/icon_names.json',
    ).writeAsString('{"custom:icon.svg":"Alias-$name"}');
    await File(
      '${active.path}/tool_images/icon_settings.json',
    ).writeAsString('{"favorites":["custom:icon.svg"],"appearances":{}}');
    await ToolsDatabase.instance.saveTool(
      ToolItem(
        id: 1,
        name: 'Conjunto-$name',
        description: '',
        descriptionDelta: '',
        barcode: '',
        quantity: 1,
        unit: 'ud',
        minimumStock: 0,
        purchasePrice: 0,
        condition: 'Bueno',
        isSet: true,
        locationSite: 'Taller-$name',
        images: [
          ToolImage(
            toolId: 1,
            path: '${active.path}/tool_images/photo.jpg',
            isPrimary: true,
          ),
        ],
      ),
    );
    await ToolsDatabase.instance.saveTool(
      ToolItem(
        id: 2,
        name: 'Pieza-$name',
        description: '',
        descriptionDelta: '',
        barcode: '',
        quantity: 3,
        unit: 'ud',
        minimumStock: 0,
        purchasePrice: 0,
        condition: 'Bueno',
        parentId: 1,
      ),
    );
    await ToolsDatabase.instance.saveTool(
      ToolItem(
        id: 3,
        name: 'Papelera-$name',
        description: '',
        descriptionDelta: '',
        barcode: '',
        quantity: 1,
        unit: 'ud',
        minimumStock: 0,
        purchasePrice: 0,
        condition: 'Bueno',
      ),
    );
    await ToolsDatabase.instance.trashTool(3);
    final kit = (await ToolsDatabase.instance.loadTool(1))!;
    kit.loanDraft = LoanDraft(
      borrower: 'Persona-$name',
      startedOn: DateTime(2026, 1, 1),
    );
    await ToolsDatabase.instance.saveTool(kit);
    final task = await ToolsDatabase.instance.saveMaintenance(
      MaintenanceTask(
        toolId: 1,
        title: 'Mantenimiento-$name',
        dueOn: DateTime(2026, 6, 1),
      ),
    );
    await ToolsDatabase.instance.saveMaintenanceRecord(
      MaintenanceRecord(
        taskId: task,
        date: DateTime(2026, 1, 2),
        notes: 'Intervención-$name',
        cost: 10,
      ),
    );
    final documents = await toolDocumentsDirectory();
    await File('${documents.path}/manual.pdf').writeAsString('document-$name');
    await ToolsDatabase.instance.saveDocument(
      ToolDocument(
        toolId: 1,
        taskId: task,
        name: 'Manual-$name',
        fileName: 'manual.pdf',
      ),
    );
    await (await ToolsDatabase.instance.database).insert('field_options', {
      'field_key': 'type',
      'label': 'Tipo-$name',
      'icon_key': 'custom:${images.path}/icon.svg',
      'color_value': 0xff123456,
      'position': 25,
    });
    await saveInventoryPreferences(
      const InventoryPreferences(view: InventoryView.grid),
    );
  }

  setUp(() async {
    SafeRestore.resetRuntimeForTest();
    SafeRestore.testFreeBytes = (_) async => 100 * 1024 * 1024 * 1024;
    root = await Directory.systemTemp.createTemp('safe_restore_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => active.path,
        );
    await location('source');
    await seed('nuevo');
    final file = await BackupManager.createBackup();
    backup = '${root.path}/selected.zip';
    await file.copy(backup);
    await location('target');
    await seed('anterior');
  });

  tearDown(() async {
    await ToolsDatabase.instance.closeForBackup();
    SafeRestore.resetRuntimeForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await root.delete(recursive: true);
  });

  Future<Map<String, Object?>> snapshot() async {
    final db = await ToolsDatabase.instance.database;
    final result = <String, Object?>{};
    for (final table in [
      'tools',
      'tool_images',
      'tool_loans',
      'loan_contents',
      'loan_events',
      'maintenance_tasks',
      'maintenance_records',
      'tool_documents',
      'borrowers',
      'field_options',
      'management_settings',
    ]) {
      result[table] = await db.query(
        table,
        orderBy: table == 'borrowers'
            ? 'name'
            : table == 'management_settings'
            ? 'key'
            : 'id',
      );
    }
    final files = <String, String>{};
    for (final dir in ['tool_images', 'tool_documents']) {
      await for (final file in Directory(
        '${active.path}/$dir',
      ).list(recursive: true)) {
        if (file is File)
          files[file.path.substring(active.path.length)] = base64Encode(
            await file.readAsBytes(),
          );
      }
    }
    result['files'] = files;
    return result;
  }

  Future<void> alterZip(void Function(Archive) edit) async {
    final archive = ZipDecoder().decodeBytes(await File(backup).readAsBytes());
    edit(archive);
    await File(backup).writeAsBytes(ZipEncoder().encode(archive));
  }

  Future<void> renameRawZipEntry(String from, String to) async {
    final source = utf8.encode(from), target = utf8.encode(to);
    expect(source.length, target.length);
    final bytes = await File(backup).readAsBytes();
    var changed = 0;
    for (var i = 0; i <= bytes.length - source.length; i++) {
      if (List.generate(
        source.length,
        (n) => bytes[i + n] == source[n],
      ).every((e) => e)) {
        bytes.setRange(i, i + target.length, target);
        changed++;
      }
    }
    expect(changed, 2); // local and central filenames, not compressed content.
    await File(backup).writeAsBytes(bytes);
  }

  Future<void> alterDatabase(Future<void> Function(Database) edit) async {
    final archive = ZipDecoder().decodeBytes(await File(backup).readAsBytes());
    final entry = archive.findFile('database/gestor_herramientas.db')!;
    final file = File('${root.path}/edit.db');
    await file.writeAsBytes(entry.content);
    final db = await databaseFactory.openDatabase(file.path);
    try {
      await edit(db);
    } finally {
      await db.close();
    }
    final bytes = await file.readAsBytes();
    archive.removeFile(entry);
    archive.addFile(
      ArchiveFile('database/gestor_herramientas.db', bytes.length, bytes),
    );
    await File(backup).writeAsBytes(ZipEncoder().encode(archive));
  }

  test(
    'Complete restore preserves all tables, assets, icons, preferences and the selected ZIP',
    () async {
      final originalZip = await File(backup).readAsBytes();
      final phases = <RestorePhase>[];
      void changed() => phases.add(SafeRestore.status.value.phase);
      SafeRestore.status.addListener(changed);
      try {
        await BackupManager.restoreBackup(backup);
      } finally {
        SafeRestore.status.removeListener(changed);
      }
      final db = await ToolsDatabase.instance.database;
      expect((await db.query('tools')).first['name'], 'Conjunto-nuevo');
      expect((await db.query('tools')).first['location_site'], 'Taller-nuevo');
      expect(await db.query('tools', where: "deleted_at!=''"), hasLength(1));
      for (final table in [
        'loan_contents',
        'loan_events',
        'maintenance_tasks',
        'maintenance_records',
        'tool_documents',
      ]) {
        expect(await db.query(table), isNotEmpty, reason: table);
      }
      expect(
        (await db.query('tool_loans')).single['borrower'],
        'Persona-nuevo',
      );
      expect(
        (await db.query(
          'field_options',
          where: "label='Tipo-nuevo'",
        )).single['icon_key'],
        'custom:${active.path}/tool_images/custom_icons/icon.svg',
      );
      expect(
        (await db.query('tool_images')).single['path'],
        '${active.path}/tool_images/photo.jpg',
      );
      expect(
        await File('${active.path}/tool_documents/manual.pdf').readAsString(),
        'document-nuevo',
      );
      expect(
        await File('${active.path}/tool_images/photo.jpg').readAsString(),
        'photo-nuevo',
      );
      expect((await loadInventoryPreferences()).view, InventoryView.grid);
      expect(await File(backup).readAsBytes(), originalZip);
      expect(
        await File('${active.path}/.safe_restore_v122/journal.json').exists(),
        false,
      );
      expect(
        await Directory('${active.path}/.safe_restore_v122/operation').exists(),
        false,
      );
      expect(
        phases,
        containsAllInOrder([
          RestorePhase.verifying,
          RestorePhase.protecting,
          RestorePhase.applying,
          RestorePhase.checking,
        ]),
      );
    },
  );

  test('Corrupt ZIP never modifies the original inventory', () async {
    final before = await snapshot();
    await File(backup).writeAsString('not a zip');
    await expectLater(
      BackupManager.restoreBackup(backup),
      throwsA(isA<RestoreFailure>()),
    );
    expect(await snapshot(), before);
  });

  test('Future SQLite version is rejected in isolation', () async {
    final before = await snapshot();
    await alterDatabase((db) => db.setVersion(999));
    await expectLater(
      BackupManager.restoreBackup(backup),
      throwsA(isA<RestoreFailure>()),
    );
    expect(await snapshot(), before);
  });

  for (final table in ['management_settings', 'tool_documents']) {
    test('SQLite required constraints on $table cannot be omitted', () async {
      final before = await snapshot();
      await alterDatabase((db) async {
        final sql =
            (await db.rawQuery("SELECT sql FROM sqlite_master WHERE name=?", [
                  table,
                ])).single['sql']
                as String;
        final incompatible = table == 'management_settings'
            ? sql.replaceAll('PRIMARY KEY', '')
            : sql.replaceAll(
                RegExp(r'\s+REFERENCES \w+\(id\) ON DELETE RESTRICT'),
                '',
              );
        expect(incompatible, isNot(sql));
        await db.execute('ALTER TABLE $table RENAME TO prior_table');
        await db.execute(incompatible);
        await db.execute('INSERT INTO $table SELECT * FROM prior_table');
        await db.execute('DROP TABLE prior_table');
      });
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreFailure>()),
      );
      expect(await snapshot(), before);
    });
  }

  test(
    'SQLite schema and orphan relationships are validated before application',
    () async {
      final before = await snapshot();
      await alterDatabase((db) async {
        await db.execute('PRAGMA foreign_keys=OFF');
        await db.update('tool_documents', {'tool_id': 9999});
      });
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreFailure>()),
      );
      expect(await snapshot(), before);
    },
  );

  for (final file in [
    'tool_images/photo.jpg',
    'tool_documents/manual.pdf',
    'tool_images/custom_icons/icon.svg',
  ]) {
    test('Missing related asset $file cancels without changes', () async {
      final before = await snapshot();
      await alterZip((archive) => archive.removeFile(archive.findFile(file)!));
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreFailure>()),
      );
      expect(await snapshot(), before);
    });
  }

  test(
    'Insufficient free space prevents extraction and leaves the source intact',
    () async {
      final before = await snapshot();
      SafeRestore.testFreeBytes = (_) async => 0;
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreFailure>()),
      );
      expect(await snapshot(), before);
      expect(await File(backup).exists(), true);
    },
  );

  for (final point in [
    'snapshot_database',
    'snapshot_tool_images',
    'snapshot_tool_documents',
  ]) {
    test(
      'Snapshot copy failure at $point never substitutes the original',
      () async {
        final before = await snapshot();
        SafeRestore.testFault = (p) async {
          if (p == point)
            throw const FileSystemException('injected copy fault');
        };
        await expectLater(
          BackupManager.restoreBackup(backup),
          throwsA(isA<RestoreFailure>()),
        );
        expect(await snapshot(), before);
      },
    );
  }

  for (final point in [
    'install_database',
    'removed_database',
    'applied_database',
    'install_tool_images',
    'removed_tool_images',
    'applied_tool_images',
    'install_tool_documents',
    'applied_tool_documents',
    'live_checked',
  ]) {
    test('Failure at $point recovers the complete verified original', () async {
      final before = await snapshot();
      var fired = false;
      SafeRestore.testFault = (p) async {
        if (!fired && p == point) {
          fired = true;
          throw const FileSystemException('injected application fault');
        }
      };
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(
          isA<RestoreFailure>().having((e) => e.recovered, 'recovered', true),
        ),
      );
      expect(fired, true);
      expect(await snapshot(), before);
      expect(await File(backup).exists(), true);
    });
  }

  for (final point in [
    'prepared_incoming',
    'snapshot_verified',
    'removed_database',
    'applied_database',
    'applied_tool_images',
    'applied_tool_documents',
    'live_checked',
  ]) {
    test(
      'Process interruption at $point recovers before normal SQLite access',
      () async {
        final before = await snapshot();
        SafeRestore.testFault = (p) async {
          if (p == point) throw RestoreInterruption();
        };
        await expectLater(
          BackupManager.restoreBackup(backup),
          throwsA(isA<RestoreInterruption>()),
        );
        // Android process death also discards a still-open original connection
        // when interruption precedes the protecting phase.
        await ToolsDatabase.instance.closeForBackup();
        SafeRestore.resetRuntimeForTest();
        SafeRestore.testFreeBytes = (_) async => 100 * 1024 * 1024 * 1024;
        expect(
          await snapshot(),
          before,
        ); // First getter performs startup recovery.
        final recorded =
            jsonDecode(
                  await File(
                    '${active.path}/.safe_restore_v122/last_result.json',
                  ).readAsString(),
                )
                as Map;
        expect(recorded['phase'], isA<String>());
        expect(recorded.keys.toSet(), {
          'phase',
          'recovered',
          'time',
          'needs_notice',
        });
        if (point == 'prepared_incoming' || point == 'snapshot_verified') {
          expect(recorded['recovered'], false); // Original never replaced.
          expect(recorded['needs_notice'], false);
        }
      },
    );
  }

  test(
    'A second interruption during recovery is resumable without consuming the snapshot',
    () async {
      final before = await snapshot();
      SafeRestore.testFault = (p) async {
        if (p == 'applied_tool_images') throw RestoreInterruption();
      };
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreInterruption>()),
      );
      SafeRestore.resetRuntimeForTest();
      SafeRestore.testFreeBytes = (_) async => 100 * 1024 * 1024 * 1024;
      SafeRestore.testFault = (p) async {
        if (p == 'recovered_database') throw RestoreInterruption();
      };
      await expectLater(
        SafeRestore.recoverPending(),
        throwsA(isA<RestoreInterruption>()),
      );
      expect(
        await File(
          '${active.path}/.safe_restore_v122/operation/recovery/database',
        ).exists(),
        true,
      );
      SafeRestore.resetRuntimeForTest();
      SafeRestore.testFreeBytes = (_) async => 100 * 1024 * 1024 * 1024;
      expect(await SafeRestore.recoverPending(), true);
      expect(await snapshot(), before);
      // A rebuilt gate must still show an unacknowledged verified recovery.
      expect(SafeRestore.readyWithoutNotice, false);
      await SafeRestore.acknowledgeRecovery();
      expect(await SafeRestore.recoverPending(), false);
      expect(SafeRestore.readyWithoutNotice, true);
    },
  );

  test(
    'Failed recovery blocks all normal writes, preserves recovery files and supports retry',
    () async {
      final before = await snapshot();
      SafeRestore.testFault = (p) async {
        if (p == 'applied_database' || p == 'recovery_install_tool_images')
          throw const FileSystemException('injected failure');
      };
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(
          isA<RestoreFailure>().having((e) => e.blocked, 'blocked', true),
        ),
      );
      expect(SafeRestore.blocked, true);
      await expectLater(
        ToolsDatabase.instance.nextToolId(),
        throwsA(isA<RestoreFailure>()),
      );
      expect(
        await Directory(
          '${active.path}/.safe_restore_v122/operation/recovery/tool_images',
        ).exists(),
        true,
      );
      SafeRestore.testFault = null;
      expect(await SafeRestore.recoverPending(), true);
      expect(await snapshot(), before);
    },
  );

  test(
    'Crash after durable confirmation keeps the verified new inventory',
    () async {
      SafeRestore.testFault = (p) async {
        if (p == 'confirmed') throw RestoreInterruption();
      };
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreInterruption>()),
      );
      SafeRestore.resetRuntimeForTest();
      expect(await SafeRestore.recoverPending(), false);
      expect(
        (await ToolsDatabase.instance.loadTool(1))!.name,
        'Conjunto-nuevo',
      );
    },
  );

  for (final name in [
    '../escape',
    '/absolute',
    'C:/windows',
    'tool_images/../escape',
    'tool_images\\escape',
  ]) {
    test(
      'Unsafe ZIP route $name is rejected without filesystem escape',
      () async {
        final before = await snapshot();
        await alterZip((a) => a.addFile(ArchiveFile(name, 1, [1])));
        if (name.contains('\\'))
          await renameRawZipEntry(name.replaceAll('\\', '/'), name);
        await expectLater(
          BackupManager.restoreBackup(backup),
          throwsA(isA<RestoreFailure>()),
        );
        expect(await snapshot(), before);
        expect(await File('${root.path}/escape').exists(), false);
      },
    );
  }

  test('ZIP symlinks and special filesystem entries are rejected', () async {
    final before = await snapshot();
    await alterZip((a) {
      final f = ArchiveFile('tool_images/link', 6, utf8.encode('../bad'));
      f.mode = 0xa1ff;
      f.symbolicLink = '../bad';
      a.addFile(f);
    });
    await expectLater(
      BackupManager.restoreBackup(backup),
      throwsA(isA<RestoreFailure>()),
    );
    expect(await snapshot(), before);
  });

  test('Conflicting file and nested ZIP paths are rejected', () async {
    final before = await snapshot();
    await alterZip((a) {
      a.addFile(ArchiveFile('tool_images/parent', 1, [1]));
      a.addFile(ArchiveFile('tool_images/parent/child', 1, [1]));
    });
    await expectLater(
      BackupManager.restoreBackup(backup),
      throwsA(isA<RestoreFailure>()),
    );
    expect(await snapshot(), before);
  });

  test(
    'Exact duplicate ZIP entries are detected before a decoder can merge them',
    () async {
      final before = await snapshot();
      await alterZip(
        (a) => a.addFile(ArchiveFile('tool_images/other.jpg', 1, [1])),
      );
      await renameRawZipEntry('tool_images/other.jpg', 'tool_images/photo.jpg');
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreFailure>()),
      );
      expect(await snapshot(), before);
    },
  );

  test(
    'CRC corruption is rejected even if the ZIP directory remains readable',
    () async {
      final before = await snapshot();
      final bytes = await File(backup).readAsBytes();
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i < bytes.length - 46; i++) {
        if (data.getUint32(i, Endian.little) == 0x02014b50) {
          data.setUint32(
            i + 16,
            data.getUint32(i + 16, Endian.little) ^ 1,
            Endian.little,
          );
          break;
        }
      }
      await File(backup).writeAsBytes(bytes);
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreFailure>()),
      );
      expect(await snapshot(), before);
    },
  );

  test(
    'A damaged SQLite payload is rejected without opening the original for writing',
    () async {
      final before = await snapshot();
      await alterZip((a) {
        a.removeFile(a.findFile('database/gestor_herramientas.db')!);
        a.addFile(
          ArchiveFile('database/gestor_herramientas.db', 4, [0, 1, 2, 3]),
        );
      });
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreFailure>()),
      );
      expect(await snapshot(), before);
    },
  );

  test(
    'A mid-copy failure leaves partial snapshots disposable and the original unchanged',
    () async {
      final before = await snapshot();
      SafeRestore.testFault = (point) async {
        if (point == 'copy_chunk' &&
            SafeRestore.status.value.phase == RestorePhase.protecting) {
          throw const FileSystemException('injected partial write');
        }
      };
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreFailure>()),
      );
      expect(await snapshot(), before);
      expect(
        await Directory('${active.path}/.safe_restore_v122/operation').exists(),
        false,
      );
    },
  );

  test(
    'Untracked replacement files are preserved and block automatic guessing',
    () async {
      final file = File('${active.path}/tool_images.safe_restore_old');
      await file.writeAsString('preserve this');
      await expectLater(
        SafeRestore.recoverPending(),
        throwsA(
          isA<RestoreFailure>().having((e) => e.blocked, 'blocked', true),
        ),
      );
      expect(await file.readAsString(), 'preserve this');
      expect(SafeRestore.blocked, true);
      SafeRestore.resetRuntimeForTest();
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(
          isA<RestoreFailure>().having((e) => e.blocked, 'blocked', true),
        ),
      );
      expect(SafeRestore.blocked, true);
      await expectLater(
        ToolsDatabase.instance.database,
        throwsA(isA<RestoreFailure>()),
      );
      expect(await file.readAsString(), 'preserve this');
    },
  );

  test(
    'The selected ZIP is never deleted if it resides in a replaced directory',
    () async {
      final selected = await File(
        backup,
      ).copy('${active.path}/tool_images/selected.zip');
      final before = await snapshot();
      await expectLater(
        BackupManager.restoreBackup(selected.path),
        throwsA(isA<RestoreFailure>()),
      );
      expect(await selected.exists(), true);
      expect(await snapshot(), before);
    },
  );

  test(
    'A damaged recovery snapshot is retained and never produces a recovered-success claim',
    () async {
      SafeRestore.testFault = (point) async {
        if (point == 'applied_database') throw RestoreInterruption();
      };
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreInterruption>()),
      );
      final snapshot = File(
        '${active.path}/.safe_restore_v122/operation/recovery/database',
      );
      await snapshot.writeAsString('damaged snapshot');
      SafeRestore.resetRuntimeForTest();
      await expectLater(
        SafeRestore.recoverPending(),
        throwsA(
          isA<RestoreFailure>().having((e) => e.blocked, 'blocked', true),
        ),
      );
      expect(await snapshot.readAsString(), 'damaged snapshot');
      expect(SafeRestore.blocked, true);
    },
  );

  test(
    'Cleanup failure after confirmation is retried without rolling back the new inventory',
    () async {
      SafeRestore.testFault = (point) async {
        if (point == 'cleanup')
          throw const FileSystemException('cleanup unavailable');
      };
      await BackupManager.restoreBackup(backup);
      expect(
        await File('${active.path}/.safe_restore_v122/journal.json').exists(),
        true,
      );
      SafeRestore.resetRuntimeForTest();
      expect(await SafeRestore.recoverPending(), false);
      expect(
        (await ToolsDatabase.instance.loadTool(1))!.name,
        'Conjunto-nuevo',
      );
      expect(
        await File('${active.path}/.safe_restore_v122/journal.json').exists(),
        false,
      );
    },
  );

  test(
    'Recovery completion survives a final interruption and acknowledges its notice once',
    () async {
      final before = await snapshot();
      SafeRestore.testFault = (point) async {
        if (point == 'applied_database') throw RestoreInterruption();
      };
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreInterruption>()),
      );
      SafeRestore.resetRuntimeForTest();
      SafeRestore.testFault = (point) async {
        if (point == 'recovery_confirmed') throw RestoreInterruption();
      };
      await expectLater(
        SafeRestore.recoverPending(),
        throwsA(isA<RestoreInterruption>()),
      );
      SafeRestore.resetRuntimeForTest();
      expect(await SafeRestore.recoverPending(), true);
      expect(await snapshot(), before);
      expect(
        await SafeRestore.recoverPending(),
        true,
      ); // notice survives another restart
      await SafeRestore.acknowledgeRecovery();
      expect(await SafeRestore.recoverPending(), false);
    },
  );

  test(
    'Trusted OS root aliases work while symlinks inside inventory remain rejected',
    () async {
      final alias = '${root.path}/app-data-alias';
      await Link(alias).create(active.path);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => alias,
          );
      await BackupManager.restoreBackup(backup);
      expect(
        (await ToolsDatabase.instance.loadTool(1))!.name,
        'Conjunto-nuevo',
      );
      await Link(
        '${active.path}/tool_images/unsafe',
      ).create('${root.path}/source/tool_images');
      final beforeDb = await (await ToolsDatabase.instance.database).query(
        'tools',
      );
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreFailure>()),
      );
      expect(
        await (await ToolsDatabase.instance.database).query('tools'),
        beforeDb,
      );
      expect(await Link('${active.path}/tool_images/unsafe').exists(), true);
    },
  );

  test(
    'ZIP entry-count limit is checked before allocating or extracting entries',
    () async {
      final before = await snapshot();
      final bytes = await File(backup).readAsBytes();
      final data = ByteData.sublistView(bytes);
      data.setUint16(
        bytes.length - 14,
        SafeRestore.maxEntries + 1,
        Endian.little,
      );
      data.setUint16(
        bytes.length - 12,
        SafeRestore.maxEntries + 1,
        Endian.little,
      );
      await File(backup).writeAsBytes(bytes);
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreFailure>()),
      );
      expect(await snapshot(), before);
    },
  );

  test(
    'ZIP advertised decompressed limit is checked before inflation',
    () async {
      final before = await snapshot();
      final bytes = await File(backup).readAsBytes();
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i < bytes.length - 46; i++) {
        if (data.getUint32(i, Endian.little) == 0x02014b50) {
          data.setUint32(i + 24, SafeRestore.maxFileBytes + 1, Endian.little);
          break;
        }
      }
      await File(backup).writeAsBytes(bytes);
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(isA<RestoreFailure>()),
      );
      expect(await snapshot(), before);
    },
  );

  test(
    'Old format v1 and SQLite v7 migrate only the isolated incoming database',
    () async {
      // Use a simple legacy fixture with none of the later-version related records.
      final archive = ZipDecoder().decodeBytes(
        await File(backup).readAsBytes(),
      );
      final manifest = archive.findFile('manifest.json')!;
      archive.removeFile(manifest);
      final bytes = utf8.encode(
        jsonEncode({
          'format': 'gestor_herramientas_backup',
          'format_version': 1,
          'database': 'database/gestor_herramientas.db',
          'images': 'tool_images',
        }),
      );
      archive.addFile(ArchiveFile('manifest.json', bytes.length, bytes));
      await File(backup).writeAsBytes(ZipEncoder().encode(archive));
      await alterDatabase((db) async {
        await db.execute('PRAGMA foreign_keys=OFF');
        for (final table in [
          'tool_documents',
          'maintenance_records',
          'maintenance_tasks',
          'loan_events',
          'loan_contents',
          'tool_loans',
          'borrowers',
          'management_settings',
        ]) {
          await db.execute('DROP TABLE $table');
        }
        await db.setVersion(7);
      });
      await BackupManager.restoreBackup(backup);
      expect(
        await (await ToolsDatabase.instance.database).getVersion(),
        toolsDatabaseVersion,
      );
      expect(
        (await ToolsDatabase.instance.loadTool(1))!.name,
        'Conjunto-nuevo',
      );
    },
  );

  test(
    'Concurrent restoration and ordinary DB access are blocked during application',
    () async {
      var checked = false;
      SafeRestore.testFault = (point) async {
        if (point != 'applied_database') return;
        // Leave the internal zone to simulate an independent screen callback.
        final independent = runZoned(() async {
          await expectLater(
            BackupManager.restoreBackup(backup),
            throwsA(isA<RestoreFailure>()),
          );
          await expectLater(
            ToolsDatabase.instance.database,
            throwsA(isA<RestoreFailure>()),
          );
        }, zoneValues: {'safe_restore_internal_access': false});
        await independent;
        checked = true;
      };
      await BackupManager.restoreBackup(backup);
      expect(checked, true);
    },
  );

  test(
    'An already running SQLite transaction is drained before the recovery point is taken',
    () async {
      final db = await ToolsDatabase.instance.database;
      final entered = Completer<void>(), release = Completer<void>();
      final writer = db.transaction((txn) async {
        await txn.update('tools', {
          'name': 'Última escritura anterior',
        }, where: 'id=1');
        entered.complete();
        await release.future;
      });
      await entered.future;
      void protecting() {
        if (SafeRestore.status.value.phase == RestorePhase.protecting &&
            !release.isCompleted)
          release.complete();
      }

      SafeRestore.status.addListener(protecting);
      SafeRestore.testFault = (point) async {
        if (point == 'applied_database')
          throw const FileSystemException('injected application fault');
      };
      try {
        await expectLater(
          BackupManager.restoreBackup(backup),
          throwsA(
            isA<RestoreFailure>().having((e) => e.recovered, 'recovered', true),
          ),
        );
      } finally {
        if (!release.isCompleted) release.complete();
        await writer;
        SafeRestore.status.removeListener(protecting);
      }
      expect(
        (await ToolsDatabase.instance.loadTool(1))!.name,
        'Última escritura anterior',
      );
    },
  );

  test(
    'Post-application SQLite corruption triggers recovery instead of a success result',
    () async {
      final before = await snapshot();
      SafeRestore.testFault = (point) async {
        if (point == 'applied_database')
          await File(
            await ToolsDatabase.instance.databasePath,
          ).writeAsString('broken incoming DB');
      };
      await expectLater(
        BackupManager.restoreBackup(backup),
        throwsA(
          isA<RestoreFailure>().having((e) => e.recovered, 'recovered', true),
        ),
      );
      expect(await snapshot(), before);
    },
  );

  test(
    'A rebuilt startup gate waits for an active restore without starting duplicate recovery',
    () async {
      Future<bool>? restarted;
      SafeRestore.testFault = (point) async {
        if (point == 'applied_database') {
          restarted = runZoned(
            SafeRestore.ensureReady,
            zoneValues: {'safe_restore_internal_access': false},
          );
        }
      };
      await BackupManager.restoreBackup(backup);
      expect(await restarted!, false);
      expect(
        (await ToolsDatabase.instance.loadTool(1))!.name,
        'Conjunto-nuevo',
      );
      expect(SafeRestore.blocked, false);
    },
  );

  testWidgets(
    'Recovery UI blocks inventory and retry is reachable with large text',
    (tester) async {
      Future<void> waitFor(bool Function() complete) async {
        for (var i = 0; i < 120; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 100));
          if (complete()) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await tester.pump();
            return;
          }
        }
        fail('The restore UI did not finish the expected phase');
      }

      await tester.binding.setSurfaceSize(const Size(280, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: RestoreGate(
              child: const Text('INVENTARIO NORMAL'),
              testRecovery: () async {
                attempts++;
                if (attempts == 1) {
                  SafeRestore.status.value = const RestoreStatus(
                    RestorePhase.blocked,
                  );
                  throw const RestoreFailure(
                    'Synthetic unavailable storage',
                    blocked: true,
                  );
                }
                SafeRestore.status.value = const RestoreStatus(
                  RestorePhase.recovering,
                );
                await Future<void>.value();
                SafeRestore.status.value = const RestoreStatus(
                  RestorePhase.idle,
                );
                return true;
              },
            ),
          ),
        ),
      );
      await waitFor(() => SafeRestore.blocked);
      expect(find.text('INVENTARIO NORMAL'), findsNothing);
      expect(find.text('No se pudo recuperar el inventario'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Reintentar recuperación'),
        200,
      );
      expect(tester.takeException(), isNull);
      SafeRestore.testFreeBytes = (_) async => 100 * 1024 * 1024 * 1024;
      await tester.tap(find.text('Reintentar recuperación'));
      await waitFor(() => SafeRestore.status.value.phase == RestorePhase.idle);
      expect(find.text(SafeRestore.recoveredMessage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
