import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/main_quill_integrated_test.dart';

ToolItem codeTool(int id, {String code = '0012345678905', int? parent, bool set = false}) => ToolItem(
  id: id, name: 'Herramienta $id', description: '', descriptionDelta: '', barcode: code,
  quantity: 1, unit: 'ud', minimumStock: 0, purchasePrice: 0, condition: 'Bueno',
  type: 'Herramienta manual', parentId: parent, isSet: set);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tool_codes_');
    await databaseFactory.setDatabasesPath('${directory.path}/db');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => directory.path);
  });
  tearDown(() async {
    await ToolsDatabase.instance.closeForBackup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), null);
    await directory.delete(recursive: true);
  });

  test('Detection removes blanks and repeated frames without changing zeros or case', () {
    expect(detectedToolCodes([null, '', ' 0012345678905 ', '0012345678905', 'AbC', 'abc']),
      ['0012345678905', 'AbC', 'abc']);
    final tools = [codeTool(1), codeTool(2, code: 'AbC')];
    expect(toolsMatchingCode(tools, '12345678905'), isEmpty);
    expect(toolsMatchingCode(tools, 'abc'), isEmpty);
    expect(toolsMatchingCode(tools, ' AbC ').single.id, 2);
    expect(toolsMatchingCode(tools, ''), isEmpty);
  });

  test('Exact lookup returns duplicate manufacturer codes and hidden pieces individually', () {
    final tools = [codeTool(1, set: true), codeTool(2), codeTool(3, parent: 1)];
    expect(toolsMatchingCode(tools, '0012345678905').map((tool) => tool.id), [1, 2, 3]);
    tools[2].labelCode = newOwnToolCode();
    expect(toolsMatchingCode(tools, tools[2].labelCode).single.id, 3);
    expect(selectInventoryTools(tools, const InventoryPreferences(), InventoryFacts(tools)), hasLength(2));
    expect(toolsMatchingCode(tools, 'new-code'), isEmpty);
  });

  test('v10 migration retains barcodes, loans, documents and metadata', () async {
    final tool = codeTool(1)..brand = 'Bosch'..serialNumber = 'SER-01'..locationSite = 'Taller'
      ..loanDraft = LoanDraft(borrower: 'Pedro', startedOn: DateTime.now());
    await ToolsDatabase.instance.saveTool(tool);
    await ToolsDatabase.instance.saveDocument(const ToolDocument(toolId: 1, name: 'Manual', url: 'https://example.com'));
    final db = await ToolsDatabase.instance.database;
    await db.execute('DROP INDEX idx_tool_label_code');
    await db.execute('ALTER TABLE tools DROP COLUMN label_code');
    await db.setVersion(10);
    await ToolsDatabase.instance.closeForBackup();
    final migrated = (await ToolsDatabase.instance.loadTool(1))!;
    expect(migrated.barcode, '0012345678905'); expect(migrated.labelCode, isEmpty);
    expect(migrated.brand, 'Bosch'); expect(migrated.locationSite, 'Taller');
    expect(migrated.serialNumber, 'SER-01'); expect(migrated.activeLoan!.borrower, 'Pedro');
    expect((await ToolsDatabase.instance.loadDocuments(1)).single.name, 'Manual');
    expect(await (await ToolsDatabase.instance.database).getVersion(), 11);
  });

  test('Own labels are unique, stable, saved once and protected from stale editors', () async {
    final stale = codeTool(1);
    await ToolsDatabase.instance.saveTool(stale);
    await ToolsDatabase.instance.saveTool(codeTool(2));
    final code = await ensureOwnToolLabel(1);
    expect(RegExp(r'^GH1:[0-9a-f]{32}$').hasMatch(code), true);
    expect(await ensureOwnToolLabel(1), code);
    expect(await ensureOwnToolLabel(2), isNot(code));
    await ToolsDatabase.instance.saveTool(stale..name = 'Editada');
    await ToolsDatabase.instance.closeForBackup();
    final saved = (await ToolsDatabase.instance.loadTool(1))!;
    expect(saved.labelCode, code); expect(saved.copy().labelCode, code);
    expect(saved.barcode, '0012345678905'); expect(saved.name, 'Editada');
    await expectLater(ensureOwnToolLabel(999), throwsStateError);
  });

  test('Backup restore preserves labels; additive imports regenerate only collisions', () async {
    await ToolsDatabase.instance.saveTool(codeTool(1, set: true));
    await ToolsDatabase.instance.saveTool(codeTool(2, parent: 1));
    final labels = [await ensureOwnToolLabel(1), await ensureOwnToolLabel(2)];
    final backup = await BackupManager.createBackup();
    final copy = await backup.copy('${directory.path}/copy.zip');
    final plan = await BackupImportPlan.prepare(copy.path);
    try {
      final result = await plan.apply();
      expect(result.regeneratedLabels, 2); expect(result.tools, 1); expect(result.pieces, 1);
      expect(result.summary, contains('etiquetas QR nuevas'));
      final tools = await ToolsDatabase.instance.loadTools(includeComponents: true);
      expect(tools.map((tool) => tool.labelCode).toSet(), hasLength(4));
      expect(tools.firstWhere((tool) => tool.id == 1).labelCode, labels[0]);
      expect(tools.firstWhere((tool) => tool.id == 2).labelCode, labels[1]);
      final piece = tools.firstWhere((tool) => tool.id == 4);
      expect(piece.parentId, 3); expect(piece.barcode, '0012345678905');
    } finally { await plan.dispose(); }
    await BackupManager.restoreBackup(copy.path);
    final restored = await ToolsDatabase.instance.loadTools(includeComponents: true);
    expect(restored.map((tool) => tool.labelCode).toSet(), labels.toSet());
    // Import into an empty inventory keeps the original printed labels usable.
    final db = await ToolsDatabase.instance.database;
    await db.update('tools', {'parent_id': null}); await db.delete('tools');
    final empty = await BackupImportPlan.prepare(copy.path);
    try {
      expect((await empty.apply()).regeneratedLabels, 0);
      expect((await ToolsDatabase.instance.loadTools(includeComponents: true)).map((t) => t.labelCode).toSet(), labels.toSet());
    } finally { await empty.dispose(); }
  });

  test('Label PDF is generated offline with long Spanish names', () async {
    final tool = codeTool(1)..name = 'Destornillador aislado de precisión para instalación eléctrica y mantenimiento'
      ..brand = 'Marca de prueba'..serialNumber = 'SER-000123'..labelCode = newOwnToolCode();
    final bytes = await toolLabelPdf(tool);
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(1000));
    await expectLater(toolLabelPdf(codeTool(2)), throwsStateError);
  });

  testWidgets('Own label fits a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: ToolLabelPage(tool: codeTool(1)..labelCode = newOwnToolCode()))));
    await tester.ensureVisible(find.text('Compartir PDF'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Manual fallback preserves leading zeros, ignores blanks and cancels cleanly', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async {
        result = await showDialog<String>(context: context, builder: (_) => const ManualToolCodeDialog());
      }, child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir')); await tester.pumpAndSettle();
    await tester.tap(find.text('Usar código')); await tester.pumpAndSettle();
    expect(find.byType(ManualToolCodeDialog), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('scan_manual_code')), ' 001AbC ');
    await tester.tap(find.text('Usar código')); await tester.pumpAndSettle();
    expect(result, '001AbC'); expect(tester.takeException(), isNull);
    await tester.tap(find.text('Abrir')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('scan_manual_code')), 'NO-GUARDAR');
    await tester.tap(find.text('Cancelar')); await tester.pumpAndSettle();
    expect(result, isNull); expect(tester.takeException(), isNull);
  });
}
