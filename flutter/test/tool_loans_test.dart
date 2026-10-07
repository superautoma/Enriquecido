import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/main_quill_integrated_test.dart';

ToolItem sample() => ToolItem(id: 101, name: 'Taladro', description: 'Con maletín',
  descriptionDelta: '', barcode: 'ABC', quantity: 2, unit: 'ud', minimumStock: 1,
  purchasePrice: 70, condition: 'Revisar', type: 'Herramienta eléctrica', voltage: '24 V');
LoanDraft draft({String borrower = 'Juan García', DateTime? due}) => LoanDraft(
  borrower: borrower, startedOn: loanDay(DateTime.now()).subtract(const Duration(days: 3)),
  dueOn: due, notes: 'Incluye cargador');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tool_loans_');
    await databaseFactory.setDatabasesPath('${directory.path}/database');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path);
  });
  tearDown(() async {
    await ToolsDatabase.instance.closeForBackup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    await directory.delete(recursive: true);
  });

  test('v7 migrates without losing descriptions, voltage, photos or custom states', () async {
    final item = sample();
    item.images = [ToolImage(toolId: item.id, path: '/photo.jpg', isPrimary: true)];
    await ToolsDatabase.instance.saveTool(item);
    final db = await ToolsDatabase.instance.database;
    await db.execute('DROP TABLE tool_loans');
    await db.setVersion(7);
    await ToolsDatabase.instance.closeForBackup();
    final loaded = (await ToolsDatabase.instance.loadTools()).single;
    expect(loaded.name, item.name);
    expect(loaded.voltage, '24 V');
    expect(loaded.description, 'Con maletín');
    expect(loaded.condition, 'Revisar');
    expect(loaded.images.single.path, '/photo.jpg');
    expect(await (await ToolsDatabase.instance.database).getVersion(), 8);
    expect(await ToolsDatabase.instance.loadLoans(), isEmpty);
  });

  test('Loan, edits, reopen, return and second loan preserve history and stock', () async {
    final item = sample()..loanDraft = draft();
    await ToolsDatabase.instance.saveTool(item);
    await ToolsDatabase.instance.closeForBackup();
    final loaded = (await ToolsDatabase.instance.loadTools()).single;
    expect(loaded.condition, 'Prestado');
    expect(loaded.activeLoan!.borrower, 'Juan García');
    expect(loaded.activeLoan!.notes, 'Incluye cargador');
    expect(loaded.quantity, 2);
    loaded.name = 'Taladro nuevo nombre';
    loaded.condition = 'Bueno'; // Cannot bypass a live loan with an old editor.
    await ToolsDatabase.instance.saveTool(loaded);
    expect((await ToolsDatabase.instance.loadTools()).single.condition, 'Prestado');
    final firstLoan = (await ToolsDatabase.instance.loadLoans()).single;
    expect(firstLoan.toolName, 'Taladro');
    await ToolsDatabase.instance.returnLoan(firstLoan.id, DateTime.now());
    await ToolsDatabase.instance.closeForBackup();
    final returned = (await ToolsDatabase.instance.loadTools()).single;
    expect(returned.activeLoan, isNull);
    expect(returned.condition, 'Revisar');
    expect(returned.quantity, 2);
    expect((await ToolsDatabase.instance.loadLoans()).single.returnedOn, isNotNull);
    returned.loanDraft = draft(borrower: 'Ana');
    await ToolsDatabase.instance.saveTool(returned);
    final history = await ToolsDatabase.instance.loadLoans(toolId: 101);
    expect(history, hasLength(2));
    expect(history.where((l) => l.isActive), hasLength(1));
    expect(history.first.borrower, 'Ana');
  });

  test('Duplicate loan and invalid dates roll back the whole tool save', () async {
    final item = sample()..loanDraft = draft();
    await ToolsDatabase.instance.saveTool(item);
    final second = (await ToolsDatabase.instance.loadTools()).single;
    second.name = 'Must roll back';
    second.loanDraft = draft(borrower: 'Ana');
    await expectLater(ToolsDatabase.instance.saveTool(second), throwsStateError);
    expect((await ToolsDatabase.instance.loadTools()).single.name, 'Taladro');
    expect(await ToolsDatabase.instance.loadLoans(), hasLength(1));
    final loan = (await ToolsDatabase.instance.loadLoans()).single;
    await expectLater(ToolsDatabase.instance.returnLoan(loan.id,
      loan.startedOn.subtract(const Duration(days: 1))), throwsStateError);
    await expectLater(ToolsDatabase.instance.returnLoan(loan.id,
      DateTime.now().add(const Duration(days: 1))), throwsStateError);
    expect((await ToolsDatabase.instance.loadLoans()).single.isActive, isTrue);
    await ToolsDatabase.instance.returnLoan(loan.id, DateTime.now());
    await expectLater(ToolsDatabase.instance.returnLoan(loan.id, DateTime.now()), throwsStateError);
  });

  test('Editing keeps the same loan, history, availability and updated backup', () async {
    await ToolsDatabase.instance.saveTool(sample()..loanDraft = draft());
    final original = (await ToolsDatabase.instance.loadLoans()).single;
    final extended = loanDay(DateTime.now()).add(const Duration(days: 10));
    await ToolsDatabase.instance.updateLoan(original.id, LoanDraft(borrower: 'Ana',
      startedOn: original.startedOn, dueOn: extended, notes: 'Añadido cargador'));
    await ToolsDatabase.instance.closeForBackup();
    var edited = (await ToolsDatabase.instance.loadLoans()).single;
    expect(edited.id, original.id); expect(edited.toolId, original.toolId);
    expect(edited.borrower, 'Ana'); expect(edited.dueOn, extended);
    expect(edited.notes, 'Añadido cargador'); expect(edited.returnedOn, isNull);
    expect(edited.quantity, 2); expect(edited.previousCondition, 'Revisar');
    expect((await ToolsDatabase.instance.loadTools()).single.condition, 'Prestado');
    final backup = await BackupManager.createBackup();
    await ToolsDatabase.instance.updateLoan(original.id, LoanDraft(borrower: 'Ana',
      startedOn: original.startedOn, notes: 'Sin fecha'));
    expect((await ToolsDatabase.instance.loadLoans()).single.dueOn, isNull);
    await BackupManager.restoreBackup(backup.path);
    expect((await ToolsDatabase.instance.loadLoans()).single.dueOn, extended);
    await ToolsDatabase.instance.returnLoan(original.id, DateTime.now());
    await ToolsDatabase.instance.updateLoan(original.id, LoanDraft(borrower: 'Ana',
      startedOn: original.startedOn, notes: 'Se devolvió con el cargador'));
    await ToolsDatabase.instance.closeForBackup();
    edited = (await ToolsDatabase.instance.loadLoans()).single;
    expect(edited.isActive, isFalse); expect(edited.id, original.id);
    expect(edited.notes, 'Se devolvió con el cargador');
    expect((await ToolsDatabase.instance.loadTools()).single.condition, 'Revisar');
  });

  test('Invalid edits preserve data and do not reopen a returned loan', () async {
    await ToolsDatabase.instance.saveTool(sample()..loanDraft = draft());
    final original = (await ToolsDatabase.instance.loadLoans()).single;
    await expectLater(ToolsDatabase.instance.updateLoan(original.id,
      draft(borrower: ' ')), throwsStateError);
    await expectLater(ToolsDatabase.instance.updateLoan(original.id,
      draft(due: original.startedOn.subtract(const Duration(days: 1)))), throwsStateError);
    await expectLater(ToolsDatabase.instance.updateLoan(-1, draft()), throwsStateError);
    final returnedOn = original.startedOn.add(const Duration(days: 1));
    await ToolsDatabase.instance.returnLoan(original.id, returnedOn);
    await expectLater(ToolsDatabase.instance.updateLoan(original.id, LoanDraft(
      borrower: 'Ana', startedOn: returnedOn.add(const Duration(days: 1)))), throwsStateError);
    final unchanged = (await ToolsDatabase.instance.loadLoans()).single;
    expect(unchanged.borrower, original.borrower); expect(unchanged.notes, original.notes);
    expect(unchanged.returnedOn, returnedOn);
  });

  testWidgets('Edit form prefills data, saves notes and removes the due date', (tester) async {
    final due = loanDay(DateTime.now()).add(const Duration(days: 5));
    await ToolsDatabase.instance.saveTool(sample()..loanDraft = draft(due: due));
    final loan = (await ToolsDatabase.instance.loadLoans()).single;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => Navigator.push<LoanDraft>(context,
        MaterialPageRoute(builder: (_) => LoanFormPage(toolName: loan.toolName,
          quantity: loan.quantity, unit: loan.unit, initialLoan: loan))),
        child: const Text('Editar'))))));
    await tester.tap(find.text('Editar')); await tester.pumpAndSettle();
    expect(find.text('Editar préstamo'), findsOneWidget);
    expect(find.text(loan.borrower), findsOneWidget);
    expect(find.text(loan.notes), findsOneWidget);
    expect(find.text('Devolución prevista: ${loanDateText(due)}'), findsOneWidget);
    await tester.tap(find.text('Quitar fecha prevista')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('loan_notes')), 'También incluye batería');
    await tester.ensureVisible(find.byKey(const ValueKey('confirm_loan')));
    await tester.tap(find.byKey(const ValueKey('confirm_loan'))); await tester.pumpAndSettle();
    final edited = (await ToolsDatabase.instance.loadLoans()).single;
    expect(edited.notes, 'También incluye batería'); expect(edited.dueOn, isNull);
    expect(edited.id, loan.id); expect(edited.isActive, isTrue);
    expect(find.text('Editar préstamo'), findsNothing); expect(tester.takeException(), isNull);
  });

  testWidgets('Cancelling an edit keeps the saved loan unchanged', (tester) async {
    await ToolsDatabase.instance.saveTool(sample()..loanDraft = draft());
    final loan = (await ToolsDatabase.instance.loadLoans()).single;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => Navigator.push<LoanDraft>(context,
        MaterialPageRoute(builder: (_) => LoanFormPage(toolName: loan.toolName,
          quantity: loan.quantity, unit: loan.unit, initialLoan: loan))),
        child: const Text('Editar'))))));
    await tester.tap(find.text('Editar')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('loan_notes')), 'No guardar');
    await tester.pageBack(); await tester.pumpAndSettle();
    expect((await ToolsDatabase.instance.loadLoans()).single.notes, loan.notes);
  });

  test('Cannot create a new loan state without a borrower record', () async {
    await expectLater(ToolsDatabase.instance.saveTool(sample()..condition = 'Prestado'),
      throwsStateError);
    expect(await ToolsDatabase.instance.loadTools(), isEmpty);
    await expectLater(ToolsDatabase.instance.saveTool(sample()..loanDraft = draft(borrower: '   ')),
      throwsStateError);
    expect(await ToolsDatabase.instance.loadTools(), isEmpty);
    final invalid = sample()..loanDraft = draft(due: DateTime(2000));
    await expectLater(ToolsDatabase.instance.saveTool(invalid), throwsStateError);
    expect(await ToolsDatabase.instance.loadLoans(), isEmpty);
  });

  test('Due today is not late, missing due date is not late, returned loans are not late', () async {
    final today = loanDay(DateTime.now());
    await ToolsDatabase.instance.saveTool(sample()..loanDraft = draft(due: today));
    final loan = (await ToolsDatabase.instance.loadLoans()).single;
    expect(loan.isOverdueOn(today), isFalse);
    expect(loan.isOverdueOn(today.add(const Duration(days: 1))), isTrue);
    await ToolsDatabase.instance.returnLoan(loan.id, today);
    expect((await ToolsDatabase.instance.loadLoans()).single.isOverdue, isFalse);
  });

  test('Complete backup and restore keep active loans and returned history', () async {
    await ToolsDatabase.instance.saveTool(sample()..loanDraft = draft());
    var first = (await ToolsDatabase.instance.loadLoans()).single;
    await ToolsDatabase.instance.returnLoan(first.id, DateTime.now());
    final item = (await ToolsDatabase.instance.loadTools()).single..loanDraft = draft(borrower: 'Ana');
    await ToolsDatabase.instance.saveTool(item);
    final backup = await BackupManager.createBackup();
    // Restore overwrites later changes with the saved state.
    first = (await ToolsDatabase.instance.loadLoans()).first;
    await ToolsDatabase.instance.returnLoan(first.id, DateTime.now());
    await BackupManager.restoreBackup(backup.path);
    final history = await ToolsDatabase.instance.loadLoans();
    expect(history, hasLength(2));
    expect(history.where((l) => l.isActive).single.borrower, 'Ana');
    expect(history.where((l) => !l.isActive).single.borrower, 'Juan García');
    expect((await ToolsDatabase.instance.loadTools()).single.activeLoan!.borrower, 'Ana');
  });

  testWidgets('Loan form validates recipient and returns confirmed optional details', (tester) async {
    LoanDraft? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async {
        result = await Navigator.push<LoanDraft>(context, MaterialPageRoute(builder: (_) =>
          const LoanFormPage(toolName: 'Taladro', quantity: 1, unit: 'ud')));
      }, child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir')); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm_loan'))); await tester.pumpAndSettle();
    expect(find.text('Escribe quién recibe la herramienta'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('loan_borrower')), 'Pedro');
    await tester.enterText(find.byKey(const ValueKey('loan_notes')), 'Con batería');
    await tester.ensureVisible(find.byKey(const ValueKey('confirm_loan')));
    await tester.tap(find.byKey(const ValueKey('confirm_loan'))); await tester.pumpAndSettle();
    expect(result?.borrower, 'Pedro'); expect(result?.notes, 'Con batería');
    expect(result?.dueOn, isNull); expect(tester.takeException(), isNull);
  });

  testWidgets('Loan icon changes state and keeps details hidden until tapped', (tester) async {
    tester.view.physicalSize = const Size(320, 900); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final loan = ToolLoan(id: 1, toolId: 101, toolName: 'Taladro',
      borrower: 'Juan García Fernández nombre muy largo', startedOn: DateTime(2026, 1, 1),
      dueOn: DateTime(2026, 1, 2), notes: 'Con su cargador y su maletín',
      previousCondition: 'Bueno', quantity: 1, unit: 'ud');
    for (final lent in [false, true]) {
      var acted = false;
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(appBar: AppBar(
          title: const Text('Editar artículo', maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [LoanStatusButton(loan: lent ? loan : null,
            onLend: () => acted = true, onReturn: () => acted = true,
            onHistory: () {}), TextButton(onPressed: () {}, child: const Text('GUARDAR'))]),
          body: const Text('Información básica')))));
      await tester.pumpAndSettle();
      expect(find.byType(LoanStatusCard), findsNothing);
      expect(find.text(loan.borrower), findsNothing);
      expect(find.byIcon(lent ? Icons.handshake_outlined : Icons.inventory_2_outlined),
        findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tool_loan_status')));
      await tester.pumpAndSettle();
      expect(find.byType(LoanStatusCard), findsOneWidget);
      if (lent) expect(find.text(loan.borrower), findsOneWidget);
      final action = find.byKey(ValueKey(lent ? 'return_tool' : 'lend_tool'));
      await tester.ensureVisible(action);
      await tester.tap(action); await tester.pumpAndSettle();
      expect(acted, isTrue);
      expect(find.byType(LoanStatusCard), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
