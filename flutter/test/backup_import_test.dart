import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/main_quill_integrated_test.dart';

ToolItem fixtureTool(int id, String name, {int? parent, bool set = false, double quantity = 3}) =>
  ToolItem(id: id, name: name, description: 'Observaciones importantes', descriptionDelta: '',
    barcode: 'COMPARTIDA', quantity: quantity, unit: 'ud', minimumStock: 1,
    purchasePrice: 45, condition: 'Bueno', type: 'Herramienta manual', parentId: parent, isSet: set);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, active;
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('import_test_');
    active = Directory('${root.path}/source'); await active.create();
    await databaseFactory.setDatabasesPath('${active.path}/db');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => active.path);
  });
  tearDown(() async {
    await ToolsDatabase.instance.closeForBackup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> sourceBackup() async {
    final images = Directory('${active.path}/tool_images'); await images.create();
    final photo = File('${images.path}/shared.jpg'); await photo.writeAsBytes([1, 2, 3, 4]);
    final kit = fixtureTool(1, 'Juego importado', set: true, quantity: 1)
      ..images = [ToolImage(toolId: 1, path: photo.path, isPrimary: true)];
    await ToolsDatabase.instance.saveTool(kit);
    await ToolsDatabase.instance.saveTool(fixtureTool(2, 'Pieza importada', parent: 1, quantity: 2));
    await ToolsDatabase.instance.saveTool(fixtureTool(3, 'Taladro importado', quantity: 4));
    final icons = Directory('${images.path}/custom_icons'); await icons.create();
    final icon = File('${icons.path}/taladro.svg');
    await icon.writeAsString('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><path d="M1 1L19 19"/></svg>');
    await File('${icon.path}.group.json').writeAsString('{"group":"Mis iconos"}');
    final db = await ToolsDatabase.instance.database;
    await db.insert('field_options', {'field_key': 'type', 'label': 'Tipo importado',
      'icon_key': 'custom:${icon.path}', 'color_value': 0xff123456, 'position': 7});
    await db.update('tools', {'tool_type': 'Tipo importado'}, where: 'id=3');
    await File('${images.path}/icon_settings.json').writeAsString(jsonEncode({
      'appearances': {'custom:taladro.svg': {'line': 0xff234567, 'circle': 0xffeeeeee}}}));
    await File('${images.path}/icon_names.json').writeAsString('{"custom:taladro.svg":"Taladro bonito"}');
    final day = loanDay(DateTime.now());
    await ToolsDatabase.instance.saveTool((await ToolsDatabase.instance.loadTool(1))!..loanDraft = LoanDraft(
      borrower: 'Ana', startedOn: day.subtract(const Duration(days: 5)), dueOn: day.add(const Duration(days: 5))));
    final kitLoan = (await ToolsDatabase.instance.loadLoans()).single;
    final content = (await ToolsDatabase.instance.loadLoanContents(kitLoan.id)).single;
    await ToolsDatabase.instance.recordReturn(kitLoan.id, LoanReturnDraft(date: day, contents: {content.id: 1}, notes: 'Falta una pieza'));
    await ToolsDatabase.instance.saveTool((await ToolsDatabase.instance.loadTool(3))!..loanDraft = LoanDraft(
      borrower: 'Ana', startedOn: day.subtract(const Duration(days: 3)), quantity: 2, notes: 'Préstamo antiguo'));
    final previous = (await ToolsDatabase.instance.loadLoans()).first;
    await ToolsDatabase.instance.returnLoan(previous.id, day);
    await ToolsDatabase.instance.saveTool((await ToolsDatabase.instance.loadTool(3))!..loanDraft = LoanDraft(
      borrower: 'Ana', startedOn: day, quantity: 1, notes: 'Préstamo activo', contact: 'Contacto de origen'));
    final currentLoan = (await ToolsDatabase.instance.loadLoans()).first;
    final task = await ToolsDatabase.instance.saveMaintenance(MaintenanceTask(toolId: 1,
      title: 'Revisión importada', dueOn: day, interval: 6));
    await ToolsDatabase.instance.saveMaintenanceRecord(MaintenanceRecord(taskId: task, date: day,
      notes: 'Trabajo realizado', parts: 'Escobillas', cost: 15));
    final documents = await toolDocumentsDirectory();
    await File('${documents.path}/shared.pdf').writeAsString('Documento del origen');
    await ToolsDatabase.instance.saveDocument(ToolDocument(toolId: 3, loanId: currentLoan.id,
      name: 'Entrega importada', fileName: 'shared.pdf', kind: 'Entrega'));
    await ToolsDatabase.instance.saveDocument(ToolDocument(toolId: 1, taskId: task,
      name: 'Revisión importada', fileName: 'shared.pdf', kind: 'Mantenimiento'));
    await saveInventoryPreferences(const InventoryPreferences(view: InventoryView.grid));
    final backup = await BackupManager.createBackup();
    final target = File('${root.path}/source.zip'); await backup.copy(target.path);
    return target.path;
  }

  Future<void> targetDatabase() async {
    await ToolsDatabase.instance.closeForBackup();
    active = Directory('${root.path}/target'); await active.create();
    await databaseFactory.setDatabasesPath('${active.path}/db');
    final images = Directory('${active.path}/tool_images'); await images.create();
    final photo = File('${images.path}/shared.jpg'); await photo.writeAsBytes([9, 8, 7]);
    await File('${images.path}/icon_names.json').writeAsString('{"handyman":"Mi nombre original"}');
    final own = fixtureTool(1, 'Mi herramienta real')
      ..images = [ToolImage(toolId: 1, path: photo.path, isPrimary: true)]
      ..loanDraft = LoanDraft(borrower: 'Ana', startedOn: DateTime.now(), quantity: 1,
        contact: 'Mi contacto original', notes: 'No cambiar estas notas');
    await ToolsDatabase.instance.saveTool(own);
    final docs = await toolDocumentsDirectory();
    await File('${docs.path}/shared.pdf').writeAsString('Mi documento original');
    await ToolsDatabase.instance.saveDocument(const ToolDocument(toolId: 1,
      name: 'Mi documento', fileName: 'shared.pdf'));
    await ToolsDatabase.instance.saveMaintenance(MaintenanceTask(toolId: 1,
      title: 'Mi mantenimiento', dueOn: DateTime.now()));
    await saveInventoryPreferences(const InventoryPreferences(view: InventoryView.compact));
    final db = await ToolsDatabase.instance.database;
    await db.update('field_options', {'color_value': 0xffabcdef}, where: "field_key='condition' AND label='Bueno'");
  }

  Future<Map<String, Object?>> snapshot() async {
    final db = await ToolsDatabase.instance.database;
    final result = <String, Object?>{};
    for (final table in ['tools', 'tool_images', 'tool_loans', 'loan_contents', 'loan_events',
      'maintenance_tasks', 'maintenance_records', 'tool_documents', 'borrowers', 'field_options', 'management_settings']) {
      result[table] = await db.query(table);
    }
    final files = <String, List<int>>{};
    await for (final file in active.list(recursive: true)) {
      if (file is File && !file.path.contains('/db/')) files[file.path] = await file.readAsBytes();
    }
    result['files'] = files;
    return result;
  }

  test('Import remaps colliding IDs and filenames while preserving existing data and preferences', () async {
    final backup = await sourceBackup(); await targetDatabase();
    final before = await snapshot();
    final plan = await BackupImportPlan.prepare(backup);
    try {
      expect(plan.tools, 2); expect(plan.pieces, 1); expect(plan.matchingReferences, 3);
      final result = await plan.apply(); expect(result.tools, 2); expect(result.pieces, 1);
      final db = await ToolsDatabase.instance.database;
      final tools = await db.query('tools'); expect(tools, hasLength(4));
      expect(tools.firstWhere((row) => row['id'] == 1), (before['tools'] as List).single);
      final kit = tools.singleWhere((row) => row['name'] == 'Juego importado');
      final child = tools.singleWhere((row) => row['name'] == 'Pieza importada');
      expect(child['parent_id'], kit['id']); expect(kit['id'], isNot(1));
      expect(await File('${active.path}/tool_images/shared.jpg').readAsBytes(), [9, 8, 7]);
      expect(await File('${active.path}/tool_documents/shared.pdf').readAsString(), 'Mi documento original');
      expect(await File(kit['image_path'] as String).readAsBytes(), [1, 2, 3, 4]);
      final importedDocs = (await db.query('tool_documents')).where((row) => row['tool_id'] != 1).toList();
      expect(importedDocs, hasLength(2));
      expect(importedDocs[0]['file_name'], importedDocs[1]['file_name']);
      expect(await File('${active.path}/tool_documents/${importedDocs.first['file_name']}').readAsString(), 'Documento del origen');
      for (final doc in importedDocs) {
        if (doc['loan_id'] != null) expect((await db.query('tool_loans', where: 'id=?', whereArgs: [doc['loan_id']])).single['tool_id'], doc['tool_id']);
        if (doc['task_id'] != null) expect((await db.query('maintenance_tasks', where: 'id=?', whereArgs: [doc['task_id']])).single['tool_id'], doc['tool_id']);
      }
      final contents = (await db.query('loan_contents')).single;
      expect(contents['component_id'], child['id']); expect(contents['returned_quantity'], 1);
      expect((await db.query('loan_events', where: 'loan_id=1')), before['loan_events']);
      expect((await db.query('tool_loans', where: 'id=1')).single, (before['tool_loans'] as List).single);
      expect((await loadInventoryPreferences()).view, InventoryView.compact);
      expect((await db.query('borrowers', where: "name='Ana'")).single['contact'], 'Mi contacto original');
      expect((await db.query('field_options', where: "field_key='condition' AND label='Bueno'")).single['color_value'], 0xffabcdef);
      expect(await File('${active.path}/tool_images/icon_names.json').readAsString(), '{"handyman":"Mi nombre original"}');
      final importedOption = (await db.query('field_options', where: "label='Tipo importado'")).single;
      expect(await File(customIconPathFromKey(importedOption['icon_key'] as String)).exists(), true);
      expect(importedOption['color_value'], 0xff234567);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally { await plan.dispose(); }
  });

  test('Importing the exact 100-tool example adds to existing tools and repeating it is harmless', () async {
    await targetDatabase();
    final fixture = File('test/fixtures/demo_100_v9.zip');
    final first = await BackupImportPlan.prepare(fixture.path);
    try {
      expect(first.tools, 100); expect(first.pieces, 40);
      await first.apply();
    } finally { await first.dispose(); }
    expect(await ToolsDatabase.instance.loadTools(), hasLength(101));
    expect(await ToolsDatabase.instance.loadTools(includeComponents: true), hasLength(141));
    final before = await snapshot();
    final second = await BackupImportPlan.prepare(fixture.path);
    try { expect(second.alreadyImported, true); expect((await second.apply()).alreadyImported, true); }
    finally { await second.dispose(); }
    expect(await snapshot(), before);
    await ToolsDatabase.instance.closeForBackup();
    expect((await ToolsDatabase.instance.loadTool(1))!.name, 'Mi herramienta real');
  });

  test('A database failure rolls back every inserted record and newly copied asset', () async {
    final backup = await sourceBackup(); await targetDatabase();
    final db = await ToolsDatabase.instance.database;
    await db.execute("CREATE TRIGGER fail_import BEFORE INSERT ON tools BEGIN SELECT RAISE(ABORT,'simulated failure'); END");
    final before = await snapshot();
    final plan = await BackupImportPlan.prepare(backup);
    try { await expectLater(plan.apply(), throwsA(isA<DatabaseException>())); }
    finally { await plan.dispose(); }
    expect(await snapshot(), before);
  });

  test('Missing assets, malformed ZIPs and traversal paths never change the current database', () async {
    final backup = await sourceBackup(); await targetDatabase();
    final before = await snapshot();
    final original = ZipDecoder().decodeBytes(await File(backup).readAsBytes());
    final incomplete = Archive();
    for (final entry in original) { if (entry.name != 'tool_documents/shared.pdf') incomplete.addFile(entry); }
    final missing = File('${root.path}/missing.zip'); await missing.writeAsBytes(ZipEncoder().encode(incomplete));
    await expectLater(BackupImportPlan.prepare(missing.path), throwsFormatException);
    final traversal = Archive()..addFile(ArchiveFile('../outside.txt', 1, [0]));
    final invalid = File('${root.path}/invalid.zip'); await invalid.writeAsBytes(ZipEncoder().encode(traversal));
    await expectLater(BackupImportPlan.prepare(invalid.path), throwsFormatException);
    await invalid.writeAsString('not a zip');
    await expectLater(BackupImportPlan.prepare(invalid.path), throwsA(anything));
    expect(await snapshot(), before);
  });

  test('An older v7 backup migrates in isolation before importing', () async {
    await ToolsDatabase.instance.saveTool(fixtureTool(42, 'Herramienta antigua'));
    final db = await ToolsDatabase.instance.database;
    await db.execute('DROP TABLE tool_loans'); await db.setVersion(7);
    final backup = await BackupManager.createBackup();
    final copy = File('${root.path}/legacy.zip'); await backup.copy(copy.path);
    await targetDatabase();
    final plan = await BackupImportPlan.prepare(copy.path);
    try { expect(plan.tools, 1); await plan.apply(); } finally { await plan.dispose(); }
    expect(await ToolsDatabase.instance.loadTools(), hasLength(2));
    expect((await ToolsDatabase.instance.loadTool(1))!.name, 'Mi herramienta real');
    expect(await (await ToolsDatabase.instance.database).getVersion(), 9);
  });

  testWidgets('Import screen remains usable on a narrow display with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(2)), child: ImportBackupPage())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Seleccionar archivo ZIP'), findsOneWidget);
  });
}
