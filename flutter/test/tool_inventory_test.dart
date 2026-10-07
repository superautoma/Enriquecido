import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/main_quill_integrated_test.dart';

ToolItem item(int id, {String name = 'Taladro', double quantity = 1,
  double minimum = 0, String type = 'Herramienta eléctrica', String voltage = '18 V',
  int? parent, bool set = false, bool blocked = false}) => ToolItem(id: id,
    name: name, description: 'Descripción', descriptionDelta: '', barcode: 'COD-$id',
    quantity: quantity, unit: 'ud', minimumStock: minimum, purchasePrice: id.toDouble(),
    condition: 'Bueno', type: type, voltage: voltage, parentId: parent,
    isSet: set, outOfService: blocked, availableQuantity: quantity);

ToolLoan loan(int id, int toolId, String borrower, {bool overdue = false}) => ToolLoan(
  id: id, toolId: toolId, toolName: 'Taladro', borrower: borrower,
  startedOn: DateTime.now().subtract(const Duration(days: 5)),
  dueOn: DateTime.now().add(Duration(days: overdue ? -1 : 5)),
  notes: '', previousCondition: 'Bueno', quantity: 1, unit: 'ud');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Type, voltage and availability combine; multiple choices are alternatives', () {
    final tools = [item(1), item(2, voltage: '230 V'), item(3, type: 'Herramienta manual', voltage: '')];
    tools[0].activeLoans = [loan(1, 1, 'Pedro')];
    tools[0].availableQuantity = 0;
    final prefs = InventoryPreferences(types: {'Herramienta eléctrica'}, voltages: {'18 V', '230 V'},
      availability: InventoryAvailability.available);
    expect(selectInventoryTools(tools, prefs, InventoryFacts(tools)).map((tool) => tool.id), [2]);
  });

  test('Search ignores accents and sees all borrowers, references and set contents', () {
    final tools = [item(1, name: 'Llave dinamométrica', set: true), item(2, name: 'Pieza especial', parent: 1)];
    tools[0].activeLoans = [loan(1, 1, 'Ana'), loan(2, 1, 'Lucía')];
    final facts = InventoryFacts(tools);
    for (final query in ['dinamometrica', 'lucia', 'COD-1', 'especial']) {
      expect(selectInventoryTools(tools, const InventoryPreferences(), facts, query: query).single.id, 1);
    }
    expect(selectInventoryTools(tools, const InventoryPreferences(includePieces: true), facts), hasLength(2));
    expect(selectInventoryTools(tools, const InventoryPreferences(content: InventoryContent.pieces), facts).single.id, 2);
  });

  test('Partial stock can be available and lent, with an overdue second borrower', () {
    final tool = item(1, quantity: 5)..availableQuantity = 2
      ..activeLoans = [loan(1, 1, 'Ana'), loan(2, 1, 'Pedro', overdue: true)];
    final tools = [tool];
    for (final availability in [InventoryAvailability.available, InventoryAvailability.borrowed, InventoryAvailability.overdue]) {
      expect(selectInventoryTools(tools, InventoryPreferences(availability: availability), InventoryFacts(tools)), hasLength(1));
    }
  });

  test('Kit filters include child service, documents and maintenance without duplicating roots', () {
    final tools = [item(1, set: true), item(2, parent: 1, blocked: true), item(3)];
    final facts = InventoryFacts(tools, documentTools: {2}, pendingMaintenanceTools: {2}, overdueMaintenanceTools: {2});
    final prefs = InventoryPreferences(availability: InventoryAvailability.outOfService,
      withDocuments: true, maintenance: InventoryMaintenance.overdue);
    expect(selectInventoryTools(tools, prefs, facts).single.id, 1);
    expect(selectInventoryTools(tools, const InventoryPreferences(availability: InventoryAvailability.available), facts).single.id, 3);
    expect(tools[0].outOfService, false); // Computed state must not alter saved state.
    expect(selectInventoryTools(tools, prefs.copyWith(includePieces: true), facts).map((tool) => tool.id), [2, 1]);
  });

  test('Stock minimum uses owned quantities and zero stock; sorting remains deterministic', () {
    final tools = [item(1, name: 'Árbol', quantity: 0, minimum: 1),
      item(2, name: 'Broca', quantity: 2, minimum: 2), item(3, quantity: 8, minimum: 4)];
    final facts = InventoryFacts(tools);
    expect(selectInventoryTools(tools, const InventoryPreferences(stock: InventoryStock.low), facts).map((tool) => tool.id), [2, 1]);
    expect(selectInventoryTools(tools, const InventoryPreferences(stock: InventoryStock.empty), facts).single.id, 1);
    expect(selectInventoryTools(tools, const InventoryPreferences(sort: InventorySort.name), facts).map((tool) => tool.id), [1, 2, 3]);
    expect(selectInventoryTools(tools, const InventoryPreferences(sort: InventorySort.price), facts).first.id, 3);
  });

  test('Preferences retain all combinations and tolerate unknown older/newer values', () {
    final original = InventoryPreferences(view: InventoryView.grid, sort: InventorySort.name,
      types: {'Manual'}, conditions: {'Revisar'}, voltages: {'18 V'},
      availability: InventoryAvailability.overdue, stock: InventoryStock.low,
      content: InventoryContent.sets, maintenance: InventoryMaintenance.pending,
      includePieces: true, withDocuments: true, withPhotos: true);
    final decoded = InventoryPreferences.fromMap(jsonDecode(jsonEncode(original.toMap())));
    expect(decoded.toMap(), original.toMap());
    expect(decoded.clearFilters().filterCount, 0);
    expect(decoded.clearFilters().view, InventoryView.grid);
    expect(InventoryPreferences.fromMap({'view': 'missing', 'types': 3}).view, InventoryView.cards);
  });

  test('Saved preferences and batch availability survive reopening alongside loans', () async {
    sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('inventory_');
    await databaseFactory.setDatabasesPath(directory.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => directory.path);
    try {
      final kit = item(1, set: true);
      await ToolsDatabase.instance.saveTool(kit);
      await ToolsDatabase.instance.saveTool(item(2, parent: 1));
      await ToolsDatabase.instance.saveTool(item(3, quantity: 4)..loanDraft = LoanDraft(
        borrower: 'Ana', quantity: 2, startedOn: DateTime.now()));
      await ToolsDatabase.instance.saveTool((await ToolsDatabase.instance.loadTool(1))!..loanDraft = LoanDraft(
        borrower: 'Pedro', startedOn: DateTime.now()));
      await saveInventoryPreferences(const InventoryPreferences(view: InventoryView.compact,
        availability: InventoryAvailability.borrowed, includePieces: true));
      await ToolsDatabase.instance.closeForBackup();
      final tools = await ToolsDatabase.instance.loadTools(includeComponents: true);
      expect(tools.firstWhere((tool) => tool.id == 2).availableQuantity, 0);
      expect(tools.firstWhere((tool) => tool.id == 3).availableQuantity, 2);
      final preferences = await loadInventoryPreferences();
      expect(preferences.view, InventoryView.compact);
      expect(selectInventoryTools(tools, preferences, await loadInventoryFacts(tools)), hasLength(3));
    } finally {
      await ToolsDatabase.instance.closeForBackup();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null);
      await directory.delete(recursive: true);
    }
  });

  for (final view in InventoryView.values) {
    for (final width in [320.0, 393.0]) {
      testWidgets('${view.name} at $width with long names and large text stays inside the screen', (tester) async {
        tester.view.physicalSize = Size(width, 850); tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
        final tools = List.generate(100, (index) => item(index + 1,
          name: 'Maletín de herramientas con nombre largo y varias piezas de prueba', set: true));
        tools.first.activeLoans = [loan(1, 1, 'Ana', overdue: true)];
        tools.first.outOfService = true;
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: MediaQueryData(size: Size(width, 850), textScaler: const TextScaler.linear(2)),
          child: Scaffold(body: InventoryResults(items: tools, view: view, facts: InventoryFacts(tools),
            conditionOptions: defaultFieldOptions('condition'), onOpen: (_) {},
            onRefresh: () async {}, onClear: () {})))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(InventoryToolTile), findsWidgets);
      });
    }
  }

  testWidgets('Filter changes stay local until Apply and footer remains reachable', (tester) async {
    tester.view.physicalSize = const Size(320, 700); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final tools = [item(1), item(2, type: 'Herramienta manual', voltage: '')];
    InventoryPreferences? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () async { selected = await showModalBottomSheet<InventoryPreferences>(
        context: context, isScrollControlled: true, builder: (_) => InventoryFilterSheet(
          initial: const InventoryPreferences(), items: tools, facts: InventoryFacts(tools),
          conditionOptions: defaultFieldOptions('condition'))); }, child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Herramienta eléctrica')); await tester.pumpAndSettle();
    await tester.tap(find.text('Herramienta eléctrica')); await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.text('Ver 1 resultados')); await tester.pumpAndSettle();
    expect(selected!.types, {'Herramienta eléctrica'});
    expect(tester.takeException(), isNull);
  });
}
