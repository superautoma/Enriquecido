import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/main_quill_integrated_test.dart';

ToolItem article(int id, {int? parent, bool set = false, double quantity = 1}) =>
  ToolItem(id: id, name: 'Artículo $id', description: 'Notas conservadas', descriptionDelta: '',
    barcode: '000$id', quantity: quantity, unit: 'ud', minimumStock: 1,
    purchasePrice: 30, condition: 'Bueno', type: 'Herramienta manual', parentId: parent, isSet: set);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final store = ToolsDatabase.instance;
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tool_trash_');
    await databaseFactory.setDatabasesPath('${directory.path}/db');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => directory.path);
  });
  tearDown(() async {
    await store.closeForBackup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), null);
    await directory.delete(recursive: true);
  });

  Future<List<ToolItem>> all() => store.loadTools(includeComponents: true, includeDeleted: true);
  Future<void> kit() async {
    await store.saveTool(article(1, set: true));
    await store.saveTool(article(2, parent: 1));
    await store.saveTool(article(3, parent: 1));
  }

  test('v11 migration keeps labels and existing data active', () async {
    await store.saveTool(article(42)..brand = 'Bosch');
    final label = await ensureOwnToolLabel(42);
    final db = await store.database;
    await db.execute('DROP INDEX idx_tool_trash_group');
    await db.execute('ALTER TABLE tools DROP COLUMN deleted_at');
    await db.execute('ALTER TABLE tools DROP COLUMN trash_group');
    await db.setVersion(11);
    await store.closeForBackup();
    final migrated = (await store.loadTool(42))!;
    expect(migrated.labelCode, label); expect(migrated.brand, 'Bosch');
    expect(migrated.isDeleted, false); expect(migrated.trashGroup, isEmpty);
    expect(await (await store.database).getVersion(), toolsDatabaseVersion);
  });

  test('Trash survives restart, hides searches and keeps IDs without reseeding', () async {
    await store.saveTool(article(42));
    final label = await ensureOwnToolLabel(42);
    await store.trashTool(42);
    await store.closeForBackup();
    await store.seedIfEmpty([article(1)]);
    expect(await store.loadTools(), isEmpty); expect(await store.loadTool(42), isNull);
    expect(await store.nextToolId(), 43);
    final stored = (await all()).single;
    expect(stored.isDeleted, true); expect(stored.copy().isDeleted, true);
    expect(stored.toMap()['trash_group'], stored.trashGroup);
    expect(toolsMatchingCode([stored], label), isEmpty);
    expect(toolsMatchingCode([stored], label, includeDeleted: true).single.id, 42);
    expect(selectInventoryTools([stored], const InventoryPreferences(), InventoryFacts([stored])), isEmpty);
    await store.restoreTrashedTool(42);
    expect((await store.loadTool(42))!.labelCode, label);
    expect((await store.loadTool(42))!.barcode, '00042');
  });

  test('Recovery preserves photographs, documents, returned loans and maintenance', () async {
    final photos = Directory('${directory.path}/tool_images'); await photos.create();
    final photo = File('${photos.path}/photo.jpg'); await photo.writeAsBytes([1, 2, 3]);
    await store.saveTool(article(1)..images = [ToolImage(toolId: 1, path: photo.path, isPrimary: true)]
      ..loanDraft = LoanDraft(borrower: 'Pedro', startedOn: DateTime.now()));
    final loan = (await store.loadLoans()).single;
    await store.returnLoan(loan.id, DateTime.now());
    await store.saveDocument(const ToolDocument(toolId: 1, name: 'Manual', url: 'https://example.com/manual'));
    final taskId = await store.saveMaintenance(MaintenanceTask(toolId: 1, title: 'Revisión', dueOn: DateTime.now()));
    await store.trashTool(1);
    expect(await store.loadMaintenance(), isEmpty);
    expect((await store.loadLoans()).single.isActive, false);
    expect((await store.loadDocuments(1)).single.name, 'Manual');
    expect(await photo.exists(), true);
    await store.restoreTrashedTool(1);
    expect((await store.loadTool(1))!.images.single.path, photo.path);
    expect((await store.loadTool(1))!.description, 'Notas conservadas');
    expect((await store.loadMaintenance()).single.id, taskId);
    expect((await store.loadMaintenance()).single.enabled, true);
  });

  test('Pending direct loans and partial returns prevent deletion atomically', () async {
    await store.saveTool(article(1, quantity: 3)..loanDraft = LoanDraft(
      borrower: 'Ana', startedOn: DateTime.now(), quantity: 2));
    final loan = (await store.loadLoans()).single;
    await store.recordReturn(loan.id, LoanReturnDraft(date: DateTime.now(), quantity: 1));
    await expectLater(store.trashCandidates(1), throwsStateError);
    await expectLater(store.trashTool(1), throwsStateError);
    expect((await store.loadTools()).single.id, 1);
    await store.returnLoan(loan.id, DateTime.now());
    await store.trashTool(1); expect(await store.loadTools(), isEmpty);
  });

  test('Confirmation does not bypass a loan created after preview', () async {
    await store.saveTool(article(1));
    expect(await store.trashCandidates(1), hasLength(1));
    await store.saveTool((await store.loadTool(1))!..loanDraft = LoanDraft(borrower: 'Ana', startedOn: DateTime.now()));
    await expectLater(store.trashTool(1), throwsStateError);
    expect((await store.loadTool(1))!.activeLoan, isNotNull);
  });

  test('A piece loan protects the whole set; a set loan protects its pieces', () async {
    await kit();
    await store.saveTool((await store.loadTool(2))!..loanDraft = LoanDraft(borrower: 'Ana', startedOn: DateTime.now()));
    await expectLater(store.trashTool(1), throwsStateError);
    expect(await all(), hasLength(3)); expect((await all()).any((tool) => tool.isDeleted), false);
    await store.returnLoan((await store.loadLoans()).single.id, DateTime.now());
    await store.saveTool((await store.loadTool(1))!..loanDraft = LoanDraft(borrower: 'Ana', startedOn: DateTime.now()));
    await expectLater(store.trashTool(2), throwsStateError);
    await expectLater(store.trashTool(1), throwsStateError);
  });

  test('Set recovery restores its batch while previously removed pieces stay removed', () async {
    await kit();
    await store.trashTool(2);
    final firstGroup = (await all()).firstWhere((tool) => tool.id == 2).trashGroup;
    await store.trashTool(1);
    final stored = await all();
    expect(stored.firstWhere((tool) => tool.id == 1).trashGroup,
      stored.firstWhere((tool) => tool.id == 3).trashGroup);
    expect(stored.firstWhere((tool) => tool.id == 1).trashGroup, isNot(firstGroup));
    await expectLater(store.restoreTrashedTool(2), throwsStateError);
    await store.restoreTrashedTool(3);
    expect((await store.loadTools(includeComponents: true)).map((tool) => tool.id), [3, 1]);
    await store.restoreTrashedTool(2); expect(await store.loadComponents(1), hasLength(2));
  });

  test('Removed pieces do not reserve or block active sets; recovery waits for loans', () async {
    await kit();
    final db = await store.database;
    await db.update('tools', {'out_of_service': 1}, where: 'id=2');
    await store.trashTool(2);
    expect((await store.loadTool(1))!.availableQuantity, 1);
    final inventory = await all();
    expect(InventoryFacts(inventory).children[1]!.map((tool) => tool.id), [3]);
    expect(selectInventoryTools(inventory, const InventoryPreferences(), InventoryFacts(inventory), query: '0002'), isEmpty);
    await store.saveTool((await store.loadTool(1))!..loanDraft = LoanDraft(borrower: 'Ana', startedOn: DateTime.now()));
    expect((await store.loadLoanContents((await store.loadLoans()).single.id)).map((piece) => piece.componentId), [3]);
    await expectLater(store.restoreTrashedTool(2), throwsStateError);
    await store.returnLoan((await store.loadLoans()).single.id, DateTime.now());
    await store.restoreTrashedTool(2);
    expect((await store.loadTool(2))!.outOfService, true);
  });

  test('Stale editors and new pieces cannot edit, lend or resurrect trashed records', () async {
    await kit();
    final stale = (await store.loadTool(2))!;
    await store.trashTool(1);
    await expectLater(store.saveTool(stale..name = 'Cambio'), throwsStateError);
    await expectLater(store.saveTool(stale..loanDraft = LoanDraft(borrower: 'Ana', startedOn: DateTime.now())), throwsStateError);
    await expectLater(store.saveTool(article(4, parent: 1)), throwsStateError);
    await expectLater(store.detachComponent(2), throwsStateError);
    await expectLater(ensureOwnToolLabel(2), throwsStateError);
    expect(await store.loadLoans(), isEmpty); expect(await all(), hasLength(3));
  });

  test('Backups preserve trash and additive imports keep recovery groups independent', () async {
    await kit();
    final label = await ensureOwnToolLabel(1);
    await store.trashTool(1);
    final originalGroup = (await all()).first.trashGroup;
    final backup = await BackupManager.createBackup();
    final copy = await backup.copy('${directory.path}/copy.zip');
    final plan = await BackupImportPlan.prepare(copy.path);
    try {
      final result = await plan.apply(); expect(result.tools, 1); expect(result.pieces, 2); expect(result.trashed, 3);
      expect(result.summary, contains('3 artículos permanecen en la papelera'));
      expect(await all(), hasLength(6)); expect(await store.loadTools(), isEmpty);
      final groups = (await all()).map((tool) => tool.trashGroup).toSet();
      expect(groups, hasLength(2)); expect(groups, contains(originalGroup));
      await store.restoreTrashedTool(1);
      expect(await store.loadTools(includeComponents: true), hasLength(3));
      expect((await all()).where((tool) => tool.isDeleted), hasLength(3));
      await BackupManager.restoreBackup(copy.path);
      expect(await all(), hasLength(3)); expect(await store.loadTools(), isEmpty);
      expect((await all()).firstWhere((tool) => tool.id == 1).labelCode, label);
      expect((await all()).first.trashGroup, originalGroup);
    } finally { await plan.dispose(); }
  });

  testWidgets('Canceling confirmation leaves the article in the inventory', (tester) async {
    await tester.runAsync(() => store.saveTool(article(1)));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async {
        if (await confirmToolTrash(context, article(1), 0) == true) await store.trashTool(1);
      }, child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir')); await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar')); await tester.pumpAndSettle();
    await tester.runAsync(() async { expect(await store.loadTool(1), isNotNull); });
  });

  testWidgets('Trash recovery works on a narrow Android-size screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async { await store.saveTool(article(1)); await store.trashTool(1); });
    await tester.pumpWidget(const MaterialApp(home: ToolTrashPage()));
    for (var i = 0; i < 250 && find.text('Artículo 1').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('Artículo 1'), findsOneWidget); expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Recuperar artículo'));
    for (var i = 0; i < 250 && find.text('La papelera está vacía').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('La papelera está vacía'), findsOneWidget); expect(tester.takeException(), isNull);
    await tester.runAsync(() async { expect(await store.loadTool(1), isNotNull); });
  });
}
