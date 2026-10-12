import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/main_quill_integrated_test.dart';

ToolItem sample({int id = 1, int? parent, bool isSet = false}) => ToolItem(
  id: id,
  name: 'Taladro',
  description: 'Descripción original',
  descriptionDelta: jsonEncode([
    {
      'insert': 'Descripción original',
      'attributes': {'bold': true},
    },
    {'insert': '\n'},
  ]),
  barcode: '12345',
  labelCode: 'GH1:original-$id',
  quantity: isSet ? 1 : 2,
  unit: 'ud',
  minimumStock: 1,
  purchasePrice: 45,
  condition: 'Bueno',
  type: 'Herramienta eléctrica',
  voltage: '24 V',
  brand: 'Marca original',
  model: 'Modelo original',
  serialNumber: 'Serie original',
  locationSite: 'Taller',
  locationRack: 'Estante',
  locationShelf: 'Balda',
  locationContainer: 'Caja',
  parentId: parent,
  isSet: isSet,
  serviceNotes: 'Nota conservada',
);

Future<void> tab(WidgetTester tester, int index) async {
  final finder = find.byKey(ValueKey('editor_tab_$index'));
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, String key, String value) async {
  final field = find.byKey(ValueKey(key));
  await Scrollable.ensureVisible(tester.element(field), alignment: .3);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  ToolItem? result;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    result = null;
    directory = await Directory.systemTemp.createTemp('editor-tabs-');
    await databaseFactory.setDatabasesPath('${directory.path}/db');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    await ToolsDatabase.instance.database;
  });
  tearDown(() async {
    await ToolsDatabase.instance.closeForBackup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });
  Future<void> open(WidgetTester tester, ToolItem? item) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          quill.FlutterQuillLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<ToolItem>(
                  MaterialPageRoute(
                    builder: (_) => EditToolPage(item: item, nextId: 10),
                  ),
                );
              },
              child: const Text('Abrir ficha'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir ficha'));
    await tester.pump();
    for (var attempt = 0; attempt < 5; attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('Create: all sections preserve values and save through SQLite', (
    tester,
  ) async {
    await open(tester, null);
    await fill(tester, 'editor_name', 'Taladro nuevo');
    await tester.tap(find.byKey(const ValueKey('tool_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Herramienta eléctrica').last);
    await tester.pumpAndSettle();
    await fill(tester, 'tool_barcode', 'NEW-123');
    await tab(tester, 1);
    await tester.tap(find.byKey(const ValueKey('tool_voltage')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('18 V').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tool_identification')));
    await tester.pumpAndSettle();
    await fill(tester, 'tool_brand', 'Bosch');
    await fill(tester, 'tool_model', 'GSB');
    await fill(tester, 'tool_serial_number', 'SER-NEW');
    await tab(tester, 2);
    await tester.tap(find.byKey(const ValueKey('tool_is_set')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tool_location')));
    await tester.pumpAndSettle();
    await fill(tester, 'tool_location_site', 'Taller nuevo');
    await fill(tester, 'editor_quantity', '3');
    await fill(tester, 'editor_unit', 'juego');
    await fill(tester, 'editor_minimumStock', '2');
    await tab(tester, 3);
    expect(find.textContaining('Sin imágenes.'), findsOneWidget);
    await tab(tester, 4);
    await fill(tester, 'editor_purchasePrice', '59,50');
    await tab(tester, 0);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('editor_name')))
          .controller!
          .text,
      'Taladro nuevo',
    );
    await tab(tester, 3);
    await tester.tap(find.text('Guardar artículo'));
    await tester.pumpAndSettle();
    expect(result?.name, 'Taladro nuevo');
    expect(result?.type, 'Herramienta eléctrica');
    expect(result?.brand, 'Bosch');
    expect(result?.model, 'GSB');
    expect(result?.serialNumber, 'SER-NEW');
    expect(result?.voltage, '18 V');
    expect(result?.quantity, 3);
    expect(result?.minimumStock, 2);
    expect(result?.unit, 'juego');
    expect(result?.purchasePrice, 59.5);
    expect(result?.isSet, isTrue);
    expect(result?.locationSite, 'Taller nuevo');
    expect(result?.barcode, 'NEW-123');
    await tester.runAsync(() async {
      await ToolsDatabase.instance.saveTool(result!);
      await ToolsDatabase.instance.closeForBackup();
      final saved = (await ToolsDatabase.instance.loadTool(10))!;
      expect(saved.toMap(), result!.toMap());
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Validation from hidden General redirects there and prevents save',
    (tester) async {
      await open(tester, null);
      await tab(tester, 4);
      await tester.tap(find.text('GUARDAR'));
      await tester.pumpAndSettle();
      expect(find.text('Escribe el nombre'), findsOneWidget);
      expect(find.text('Selecciona el tipo').last, findsOneWidget);
      expect(result, isNull);
      expect(find.byType(EditToolPage), findsOneWidget);
      expect(
        tester
            .widget<IndexedStack>(find.byKey(const ValueKey('editor_sections')))
            .index,
        0,
      );
      await fill(tester, 'editor_name', 'Nombre válido');
      await tab(tester, 2);
      await tester.tap(find.text('Guardar artículo'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('Selecciona el tipo').last, findsOneWidget);
    },
  );

  testWidgets(
    'Editing unchanged tabs preserves every stored field, photo and relation',
    (tester) async {
      final original = sample(id: 2, parent: 1)..outOfService = true;
      original.images = [
        ToolImage(
          id: 7,
          toolId: 2,
          path: '${directory.path}/absent.jpg',
          description: 'Foto conservada',
          type: 'Detalle',
          isPrimary: true,
          createdAt: '2020-01-01',
        ),
      ];
      await tester.runAsync(() async {
        await ToolsDatabase.instance.saveTool(sample(isSet: true));
        await ToolsDatabase.instance.saveTool(original);
      });
      final before = original.toMap();
      final imageBefore = original.images.single.toMap();
      await open(tester, original);
      for (final index in [1, 2, 3, 4, 0]) {
        await tab(tester, index);
      }
      await tab(tester, 2);
      expect(find.byKey(const ValueKey('tool_is_set')), findsNothing);
      expect(find.textContaining('ubicación del conjunto'), findsOneWidget);
      expect(find.text('Fuera de servicio'), findsOneWidget);
      await tab(tester, 3);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      await tester.tap(find.text('GUARDAR'));
      await tester.pumpAndSettle();
      expect(result!.toMap(), before);
      expect(result!.images.single.toMap(), imageBefore);
      expect(original.toMap(), before);
      await tester.runAsync(() async {
        await ToolsDatabase.instance.saveTool(result!);
        expect((await ToolsDatabase.instance.loadTool(2))!.parentId, 1);
        expect((await ToolsDatabase.instance.loadTool(1))!.isSet, isTrue);
        expect(
          await (await ToolsDatabase.instance.database).getVersion(),
          toolsDatabaseVersion,
        );
      });
    },
  );

  testWidgets('Quill rich edits survive switching and save', (tester) async {
    await open(tester, sample());
    final description = find.byType(DescriptionQuillCard);
    await Scrollable.ensureVisible(tester.element(description));
    await tester.pumpAndSettle();
    await tester.tap(description);
    await tester.pumpAndSettle();
    final controller = tester
        .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
        .controller;
    expect(controller.document.toDelta().toJson().first['attributes'], {
      'bold': true,
    });
    controller.replaceText(
      0,
      controller.document.length - 1,
      'Nueva descripción',
      const TextSelection.collapsed(offset: 0),
    );
    controller.formatText(0, 5, quill.Attribute.bold);
    await tester.tap(find.text('ACEPTAR'));
    await tester.pumpAndSettle();
    await tab(tester, 4);
    await tab(tester, 0);
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();
    expect(result?.description, 'Nueva descripción');
    expect(result?.descriptionDelta, contains('"bold":true'));
  });

  testWidgets(
    'Image preview and primary control preserve original file bytes',
    (tester) async {
      late List<int> bytes;
      await tester.runAsync(() async {
        bytes = await File('assets/icons/herramientas.png').readAsBytes();
      });
      final file = File('${directory.path}/existing.png');
      await tester.runAsync(() async {
        await file.writeAsBytes(bytes);
      });
      final item = sample()
        ..images = [
          ToolImage(
            toolId: 1,
            path: file.path,
            description: 'Foto',
            isPrimary: false,
          ),
        ];
      await open(tester, item);
      await tab(tester, 3);
      expect(find.byTooltip('Cámara'), findsOneWidget);
      expect(find.byTooltip('Galería'), findsOneWidget);
      expect(find.byTooltip('URL'), findsOneWidget);
      expect(find.byTooltip('IA'), findsOneWidget);
      final image = find.byType(Image).first;
      await tester.tap(image);
      await tester.pumpAndSettle();
      expect(find.text('Datos'), findsOneWidget);
      expect(find.text('Eliminar'), findsOneWidget);
      await tester.tap(find.text('Hacer principal'));
      await tester.pumpAndSettle();
      await tab(tester, 1);
      await tab(tester, 3);
      await tester.tap(find.text('GUARDAR'));
      await tester.pumpAndSettle();
      expect(result?.images.single.isPrimary, isTrue);
      await tester.runAsync(() async {
        expect(await file.readAsBytes(), bytes);
      });
      expect(item.images.single.isPrimary, isFalse);
    },
  );

  testWidgets(
    'Set contents and loan controls remain accessible with unsaved values',
    (tester) async {
      final kit = sample(isSet: true);
      await tester.runAsync(() async {
        await ToolsDatabase.instance.saveTool(kit);
        await ToolsDatabase.instance.saveTool(
          sample(id: 2, parent: 1)..name = 'Pieza conservada',
        );
      });
      await open(tester, kit);
      expect(find.byType(LoanStatusButton), findsOneWidget);
      await fill(tester, 'editor_name', 'Conjunto editado');
      await tab(tester, 2);
      await tester.tap(find.byKey(const ValueKey('management_contents')));
      await tester.pump();
      for (var attempt = 0; attempt < 30; attempt++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        if (find.text('Pieza conservada').evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();
      expect(find.byType(ComponentsPage), findsOneWidget);
      expect(find.text('Pieza conservada'), findsOneWidget);
      await tester.pageBack();
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tab(tester, 0);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('editor_name')))
            .controller!
            .text,
        'Conjunto editado',
      );
      await tester.tap(find.text('GUARDAR'));
      await tester.pumpAndSettle();
      expect(result?.isSet, isTrue);
      await tester.runAsync(() async {
        expect((await ToolsDatabase.instance.loadTool(2))!.parentId, 1);
      });
    },
  );
  testWidgets(
    'Scrollable icon tabs fit a narrow screen and preserve an active loan',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final item = sample()
        ..condition = 'Prestado'
        ..activeLoan = ToolLoan(
          id: 5,
          toolId: 1,
          toolName: 'Taladro',
          borrower: 'Ana',
          startedOn: DateTime(2026, 1, 1),
          quantity: 1,
          unit: 'ud',
          notes: 'Con cargador',
          previousCondition: 'Bueno',
        );
      await open(tester, item);
      final tabs = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabs.isScrollable, isTrue);
      expect(tabs.tabs.length, 5);
      for (final index in [4, 3, 2, 1, 0]) {
        await tab(tester, index);
      }
      await tab(tester, 4);
      await tester.tap(find.text('GUARDAR'));
      await tester.pumpAndSettle();
      expect(result?.activeLoan?.id, 5);
      expect(result?.activeLoan?.notes, 'Con cargador');
      expect(result?.condition, 'Prestado');
      expect(tester.takeException(), isNull);
    },
  );
}
