import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/main_quill_integrated_test.dart';

ToolItem detailTool(int id, {int? parent, bool set = false}) => ToolItem(
  id: id, name: 'Taladro $id', description: 'Descripción conservada', descriptionDelta: '',
  barcode: 'REF-$id', quantity: 1, unit: 'ud', minimumStock: 0, purchasePrice: 50,
  condition: 'Bueno', type: 'Herramienta manual', parentId: parent, isSet: set);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tool_details_');
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

  test('v9 upgrade retains tools, pieces, active loans, photos and documents', () async {
    final database = ToolsDatabase.instance;
    await database.saveTool(detailTool(1, set: true)..images = [
      ToolImage(toolId: 1, path: '/existing/photo.jpg', isPrimary: true)]);
    await database.saveTool(detailTool(2, parent: 1));
    await database.saveTool(detailTool(3)..loanDraft = LoanDraft(
      borrower: 'Pedro', startedOn: DateTime.now(), notes: 'Con cargador'));
    await database.saveDocument(const ToolDocument(toolId: 3, name: 'Manual', url: 'https://example.com/manual'));
    final db = await database.database;
    for (final column in toolDetailColumns) { await db.execute('ALTER TABLE tools DROP COLUMN $column'); }
    await db.setVersion(9);
    await database.closeForBackup();
    final tools = await database.loadTools(includeComponents: true);
    expect(tools, hasLength(3));
    expect(tools.firstWhere((t) => t.id == 2).parentId, 1);
    expect(tools.firstWhere((t) => t.id == 1).images.single.path, '/existing/photo.jpg');
    final borrowed = tools.firstWhere((t) => t.id == 3);
    expect(borrowed.activeLoan!.notes, 'Con cargador');
    expect(borrowed.description, 'Descripción conservada');
    expect(borrowed.brand, isEmpty);
    expect(borrowed.location.isEmpty, true);
    expect((await database.loadDocuments(3)).single.name, 'Manual');
    expect(await (await database.database).getVersion(), toolsDatabaseVersion);
  });

  test('Identification and location survive reopen and backup restoration', () async {
    final tool = detailTool(1)..brand = 'Bosch'..model = 'GSB 18V'..serialNumber = 'S-001'
      ..locationSite = 'Taller'..locationRack = 'Estantería 2'..locationShelf = 'Balda 3'
      ..locationContainer = 'Maletín azul';
    await ToolsDatabase.instance.saveTool(tool);
    final backup = await BackupManager.createBackup();
    await ToolsDatabase.instance.saveTool(detailTool(1));
    await BackupManager.restoreBackup(backup.path);
    final restored = (await ToolsDatabase.instance.loadTool(1))!;
    expect(restored.toMap(), tool.toMap());
    expect(restored.copy().serialNumber, 'S-001');
    expect(restored.location.label, 'Taller → Estantería 2 → Balda 3 → Maletín azul');
  });

  test('Pieces inherit only when their whole location is empty; filters and search use it', () {
    final kit = detailTool(1, set: true)..locationSite = 'Taller'..locationRack = '2'
      ..locationShelf = '3'..locationContainer = 'Azul';
    final inherited = detailTool(2, parent: 1)..brand = 'Bosch'..model = 'GSB'..serialNumber = 'S-002';
    final separate = detailTool(3, parent: 1)..locationSite = 'Furgoneta';
    final tools = [kit, inherited, separate];
    final facts = InventoryFacts(tools);
    expect(facts.locationFor(inherited).label, kit.location.label);
    expect(facts.locationFor(separate).label, 'Furgoneta');
    final preferences = InventoryPreferences(includePieces: true, sites: {'Taller'},
      racks: {'2'}, shelves: {'3'}, containers: {'Azul'}, brands: {'Bosch'});
    expect(selectInventoryTools(tools, preferences, facts).single.id, 2);
    for (final query in ['bosCH', 'GSB', 's-002', 'furgoneta']) {
      expect(selectInventoryTools(tools, const InventoryPreferences(), facts, query: query).single.id, 1);
    }
    separate.locationSite = '';
    expect(facts.locationFor(separate).label, kit.location.label);
  });

  test('Location filters are remembered; previous preferences and missing locations are supported', () async {
    const preferences = InventoryPreferences(view: InventoryView.grid, sites: {'Taller'},
      racks: {'2'}, shelves: {'3'}, containers: {''}, brands: {'Bosch'});
    await saveInventoryPreferences(preferences);
    await ToolsDatabase.instance.closeForBackup();
    expect((await loadInventoryPreferences()).toMap(), preferences.toMap());
    expect(preferences.clearFilters().filterCount, 0);
    expect(InventoryPreferences.fromMap({'view': 'compact'}).sites, isEmpty);
    final tools = [detailTool(1), detailTool(2)..locationSite = 'Taller'];
    expect(selectInventoryTools(tools, const InventoryPreferences(sites: {''}),
      InventoryFacts(tools)).single.id, 1);
  });

  testWidgets('Optional details can be edited on a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 750); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final controllers = List.generate(7, (_) => TextEditingController());
    addTearDown(() { for (final controller in controllers) { controller.dispose(); } });
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: Scaffold(body: SingleChildScrollView(child: ToolDetailsForm(
        brand: controllers[0], model: controllers[1], serialNumber: controllers[2],
        site: controllers[3], rack: controllers[4], shelf: controllers[5], container: controllers[6],
        inheritedLocation: 'Taller → Estantería 2 → Balda 3'))))));
    await tester.tap(find.text('Identificación')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('tool_brand')));
    await tester.enterText(find.byKey(const ValueKey('tool_brand')), 'Bosch');
    await tester.ensureVisible(find.text('Ubicación')); await tester.tap(find.text('Ubicación'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('tool_location_container')));
    await tester.enterText(find.byKey(const ValueKey('tool_location_container')), 'Caja azul');
    expect(controllers[0].text, 'Bosch'); expect(controllers[6].text, 'Caja azul');
    expect(tester.takeException(), isNull);
  });
}
