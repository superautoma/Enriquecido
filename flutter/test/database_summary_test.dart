import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/main_quill_integrated_test.dart';

ToolItem record(int id, {int? parent, bool set = false, bool deleted = false}) =>
  ToolItem.fromMap({'id': id, 'name': 'Ficha $id', 'quantity': 7.0,
    'parent_id': parent, 'is_set': set ? 1 : 0,
    'deleted_at': deleted ? '2026-10-11' : ''});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('summary_');
    await databaseFactory.setDatabasesPath('${directory.path}/db');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => directory.path);
    await SafeRestore.ensureReady();
  });
  tearDown(() async {
    await ToolsDatabase.instance.closeForBackup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), null);
    await directory.delete(recursive: true);
  });

  test('Empty database partitions into zero records', () async {
    final stats = await ToolsDatabase.instance.getStats();
    expect([stats.tools, stats.activeMainTools, stats.activePieces, stats.trashTools], [0, 0, 0, 0]);
  });

  test('Read-only summary partitions roots, pieces and trash without changing records or photos', () async {
    final db = await ToolsDatabase.instance.database;
    for (final tool in [record(1), record(2, set: true), record(3, parent: 2),
        record(4, parent: 2, deleted: true), record(5, deleted: true),
        record(6)..outOfService = true]) {
      await db.insert('tools', tool.toMap());
    }
    final photo = File('${directory.path}/tool_images/photo.jpg');
    await photo.parent.create(recursive: true);
    await photo.writeAsBytes([1, 2, 3]);
    final before = await db.query('tools');
    final version = await db.getVersion();
    await db.execute('PRAGMA query_only=ON');
    try {
      final stats = await ToolsDatabase.instance.getStats();
      expect([stats.tools, stats.activeMainTools, stats.activePieces, stats.trashTools], [6, 3, 1, 2]);
      expect(stats.activeMainTools + stats.activePieces + stats.trashTools, stats.tools);
      expect(stats.imagesBytes, 3);
      expect(await db.query('tools'), before);
      expect(await db.getVersion(), version);
      expect(await photo.readAsBytes(), [1, 2, 3]);
    } finally { await db.execute('PRAGMA query_only=OFF'); }
  });

  test('141 records are 101 main articles plus 40 active pieces, not summed quantities', () async {
    final db = await ToolsDatabase.instance.database;
    final batch = db.batch();
    for (var id = 1; id <= 141; id++) {
      batch.insert('tools', record(id, parent: id > 101 ? 1 : null, set: id == 1).toMap());
    }
    await batch.commit(noResult: true);
    final stats = await ToolsDatabase.instance.getStats();
    expect([stats.tools, stats.activeMainTools, stats.activePieces, stats.trashTools], [141, 101, 40, 0]);
    final tools = await ToolsDatabase.instance.loadTools(includeComponents: true);
    final facts = InventoryFacts(tools);
    expect(selectInventoryTools(tools, const InventoryPreferences(), facts), hasLength(101));
    expect(selectInventoryTools(tools, const InventoryPreferences(includePieces: true), facts), hasLength(141));
  });

  testWidgets('Existing database page shows the partition and retains storage and backup controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await ToolsDatabase.instance.saveTool(record(1, set: true));
      await ToolsDatabase.instance.saveTool(record(2, parent: 1));
      await tester.pumpWidget(MaterialApp(home: DatabaseManagementPage(
        onCreateBackup: () async {}, onRestoreBackup: () async => false,
        onImportBackup: () async => false)));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    for (final label in ['Total de registros de herramientas', 'Artículos principales activos',
        'Piezas activas pertenecientes a conjuntos', 'Registros en la papelera', 'SQLite', 'Fotos',
        'Crear copia de seguridad', 'Importar y añadir', 'Restaurar y sustituir']) {
      await tester.scrollUntilVisible(find.text(label), 150);
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
