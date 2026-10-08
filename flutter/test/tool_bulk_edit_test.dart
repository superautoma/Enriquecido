import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/main_quill_integrated_test.dart';

ToolItem tool(int id, {double quantity = 4, int? parent, bool isSet = false}) =>
    ToolItem(
      id: id,
      name: 'Herramienta $id',
      description: 'Texto $id',
      descriptionDelta: '',
      barcode: 'COD-$id',
      serialNumber: 'SERIE-$id',
      quantity: quantity,
      unit: 'ud',
      minimumStock: 1,
      purchasePrice: 12,
      condition: 'Bueno',
      brand: 'Marca $id',
      parentId: parent,
      isSet: isSet,
      locationSite: 'Taller',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final db = ToolsDatabase.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bulk_tools_');
    await databaseFactory.setDatabasesPath('${root.path}/db');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
  });
  tearDown(() async {
    await db.closeForBackup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await root.delete(recursive: true);
  });

  test(
    'Only chosen fields change; identity, loan history and images survive',
    () async {
      final photo = File('${root.path}/photo.jpg');
      await photo.writeAsString('keep');
      await db.saveTool(
        tool(1)
          ..images = [ToolImage(toolId: 1, path: photo.path, isPrimary: true)]
          ..loanDraft = LoanDraft(
            borrower: 'Ana',
            startedOn: DateTime.now(),
            quantity: 2,
          ),
      );
      await db.saveTool(tool(2));
      final before = await db.loadTools(includeComponents: true);
      final sql = await db.database;
      final history = await sql.query('loan_events');
      await db.updateToolsTogether(before, {
        'brand': 'Común',
        'location_site': '',
        'out_of_service': 1,
      });
      final after = await db.loadTools(includeComponents: true);
      for (final item in after) {
        expect(item.brand, 'Común');
        expect(item.locationSite, '');
        expect(item.outOfService, true);
        expect(item.barcode, 'COD-${item.id}');
        expect(item.serialNumber, 'SERIE-${item.id}');
        expect(item.quantity, 4);
        expect(item.description, 'Texto ${item.id}');
      }
      expect((await db.loadLoans()).single.borrower, 'Ana');
      expect(await sql.query('loan_events'), history);
      expect(await photo.readAsString(), 'keep');
      expect(await sql.getVersion(), 12);
    },
  );

  test(
    'Invalid stock on a later item rolls the entire operation back',
    () async {
      await db.saveTool(tool(1));
      await db.saveTool(
        tool(2)
          ..loanDraft = LoanDraft(
            borrower: 'Ana',
            startedOn: DateTime.now(),
            quantity: 3,
          ),
      );
      final originals = [(await db.loadTool(1))!, (await db.loadTool(2))!];
      await expectLater(
        db.updateToolsTogether(originals, {'brand': 'Cambio', 'quantity': 2}),
        throwsStateError,
      );
      expect((await db.loadTool(1))!.brand, 'Marca 1');
      expect((await db.loadTool(2))!.quantity, 4);
    },
  );

  test('Stale fields and trash entries reject the whole edit', () async {
    await db.saveTool(tool(1));
    await db.saveTool(tool(2));
    final originals = [(await db.loadTool(1))!, (await db.loadTool(2))!];
    await (await db.database).update('tools', {
      'brand': 'Nueva',
    }, where: 'id=2');
    await expectLater(
      db.updateToolsTogether(originals, {'brand': 'Común'}),
      throwsStateError,
    );
    expect((await db.loadTool(1))!.brand, 'Marca 1');
    await (await db.database).update('tools', {
      'deleted_at': '2026-10-08',
    }, where: 'id=2');
    await expectLater(
      db.updateToolsTogether(originals, {'location_site': 'Otro'}),
      throwsStateError,
    );
    expect((await db.loadTool(1))!.locationSite, 'Taller');
  });

  test(
    'Shared changes cannot bypass loans, sets, identity or numeric validation',
    () async {
      await db.saveTool(
        tool(1)
          ..loanDraft = LoanDraft(
            borrower: 'Ana',
            startedOn: DateTime.now(),
            quantity: 1,
          ),
      );
      final borrowed = [(await db.loadTool(1))!];
      for (final patch in <Map<String, Object?>>[
        {'condition': 'Bueno'},
        {'unit': 'cajas'},
        {'condition': 'Prestado'},
        {'quantity': double.nan},
        {'minimum_stock': -1},
        {'barcode': 'Duplicado'},
        {'name': ''},
        {'description': 'Sin formato'},
      ]) {
        await expectLater(
          db.updateToolsTogether(borrowed, patch),
          throwsStateError,
        );
      }
      await db.saveTool(tool(2, quantity: 1, isSet: true));
      await db.saveTool(tool(3, parent: 2));
      await expectLater(
        db.updateToolsTogether([(await db.loadTool(2))!], {'quantity': 2}),
        throwsStateError,
      );
    },
  );

  test('Formatted descriptions are replaced together without changing other fields', () async {
    await db.saveTool(tool(1));
    await db.saveTool(tool(2));
    final delta = jsonEncode([
      {
        'insert': 'Descripción común',
        'attributes': {'bold': true},
      },
      {'insert': '\n'},
    ]);
    await db.updateToolsTogether(await db.loadTools(), {
      'description': 'Descripción común',
      'description_delta': delta,
    });
    for (final item in await db.loadTools()) {
      expect(item.descriptionDelta, delta);
      expect(item.description, 'Descripción común');
      expect(item.brand, 'Marca ${item.id}');
    }
  });

  test('Unchosen concurrent changes are preserved and duplicate selections rejected', () async {
    await db.saveTool(tool(1));
    await db.saveTool(tool(2));
    final originals = await db.loadTools();
    await (await db.database).update('tools', {
      'model': 'Actualizado',
    }, where: 'id=1');
    await db.updateToolsTogether(originals, {'brand': 'Común'});
    expect((await db.loadTool(1))!.model, 'Actualizado');
    await expectLater(
      db.updateToolsTogether(
        [originals.first, originals.first],
        {'brand': 'Otro'},
      ),
      throwsStateError,
    );
  });

  testWidgets('Shared numeric values retain precision when enabled unchanged', (
    tester,
  ) async {
    late List<ToolItem> originals;
    await tester.runAsync(() async {
      await db.saveTool(tool(1, quantity: 1.234567));
      await db.saveTool(tool(2, quantity: 1.234567));
      originals = await db.loadTools();
    });
    await tester.pumpWidget(
      MaterialApp(home: BulkEditToolsPage(items: originals)),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('bulk_field_quantity'));
    await tester.scrollUntilVisible(
      field,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('bulk_value_quantity')),
          )
          .controller!
          .text,
      '1.234567',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home selection survives searches and selects only visible results',
    (tester) async {
      await tester.pumpWidget(const GestorHerramientasApp());
      for (
        var i = 0;
        i < 30 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bulk_select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Destornillador aislado'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Buscar herramientas'),
        'Taladro',
      );
      await tester.pumpAndSettle();
      expect(find.text('1 fuera de los resultados'), findsOneWidget);
      await tester.tap(find.text('Seleccionar resultados'));
      await tester.pumpAndSettle();
      expect(find.text('2 seleccionadas'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bulk_edit')));
      await tester.pumpAndSettle();
      expect(find.text('2 herramientas seleccionadas'), findsOneWidget);
      expect(find.byKey(const ValueKey('bulk_value_name')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Review can cancel; applying an explicitly empty field preserves unchosen values',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late List<ToolItem> originals;
      await tester.runAsync(() async {
        await db.saveTool(tool(1));
        await db.saveTool(tool(2));
        originals = await db.loadTools();
      });
      await tester.pumpWidget(
        MaterialApp(home: BulkEditToolsPage(items: originals)),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('bulk_field_location_site'));
      await tester.scrollUntilVisible(
        field,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('bulk_value_location_site')),
        '',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('bulk_save'));
      await tester.scrollUntilVisible(
        save,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Aplicar a 2 herramientas'), findsOneWidget);
      expect(find.text('Lugar / taller: Vaciar campo'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        expect((await db.loadTool(1))!.locationSite, 'Taller');
      });
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('bulk_confirm')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (final item in await db.loadTools()) {
          expect(item.locationSite, '');
          expect(item.brand, 'Marca ${item.id}');
        }
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Selection changes checkboxes in every inventory view without opening the editor',
    (tester) async {
      for (final view in InventoryView.values) {
        final items = [tool(1), tool(2)];
        final selected = <int>{};
        var opens = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => InventoryResults(
                  items: items,
                  view: view,
                  facts: InventoryFacts(items),
                  conditionOptions: defaultFieldOptions('condition'),
                  selecting: true,
                  selectedIds: selected,
                  onSelect: (item) => setState(() {
                    if (!selected.add(item.id)) selected.remove(item.id);
                  }),
                  onOpen: (_) => opens++,
                  onRefresh: () async {},
                  onClear: () {},
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Herramienta 1'));
        await tester.pump();
        expect(selected, {1});
        expect(opens, 0);
        expect(
          tester.widget<Checkbox>(find.byType(Checkbox).first).value,
          true,
        );
        await tester.tap(find.byType(Checkbox).first);
        await tester.pump();
        expect(selected, isEmpty);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
