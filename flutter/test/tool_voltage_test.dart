import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/main_quill_integrated_test.dart';

ToolItem sampleTool({String voltage = ''}) => ToolItem(
      id: 42,
      name: 'Taladro',
      description: 'Herramienta de prueba',
      descriptionDelta: '',
      barcode: '12345',
      quantity: 2,
      unit: 'ud',
      minimumStock: 1,
      purchasePrice: 50,
      condition: 'Bueno',
      type: 'Herramienta eléctrica',
      voltage: voltage,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tool_voltage_');
    await databaseFactory.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    await ToolsDatabase.instance.closeForBackup();
    await directory.delete(recursive: true);
  });

  test('Voltages sort numerically and keep a saved custom voltage', () {
    expect(voltageOptionsFor(''),
        ['', '12 V', '18 V', '20 V', '24 V', '36 V', '48 V', '110 V', '230 V', '400 V']);
    expect(voltageOptionsFor('21,6 V'),
        ['', '12 V', '18 V', '20 V', '21,6 V', '24 V', '36 V', '48 V', '110 V', '230 V', '400 V']);
    expect(voltageOptionsFor('24 V').where((value) => value == '24 V'),
        hasLength(1));
  });

  testWidgets('Voltage badges fit narrow screens with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: ListView(children: [
            for (final voltage in voltageOptionsFor('21,6 V'))
              ListTile(
                leading: VoltageBadge(voltage: voltage),
                title: Text(voltage.isEmpty ? 'Sin especificar' : voltage),
              ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final badge = find.widgetWithText(VoltageBadge, '400');
    await tester.scrollUntilVisible(badge, 200);
    expect(badge, findsOneWidget);
    expect(find.descendant(of: badge, matching: find.text('V')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Upgrade from v5 keeps tools, images and descriptions', () async {
    final legacy = sampleTool();
    legacy.images = [
      ToolImage(toolId: 42, path: '/existing/photo.jpg', isPrimary: true),
    ];
    await ToolsDatabase.instance.saveTool(legacy);
    final db = await ToolsDatabase.instance.database;
    await db.execute('ALTER TABLE tools DROP COLUMN voltage');
    await db.setVersion(5);
    await ToolsDatabase.instance.closeForBackup();

    final tools = await ToolsDatabase.instance.loadTools();
    expect(tools, hasLength(1));
    expect(tools.single.name, legacy.name);
    expect(tools.single.description, legacy.description);
    expect(tools.single.barcode, legacy.barcode);
    expect(tools.single.quantity, legacy.quantity);
    expect(tools.single.type, legacy.type);
    expect(tools.single.images.single.path, '/existing/photo.jpg');
    expect(tools.single.voltage, isEmpty);
    expect(await (await ToolsDatabase.instance.database).getVersion(), 7);
  });

  test('Each requested voltage survives saving and reopening SQLite', () async {
    for (final voltage in ['230 V', '24 V', '18 V']) {
      await ToolsDatabase.instance.saveTool(sampleTool(voltage: voltage));
      await ToolsDatabase.instance.closeForBackup();
      final item = (await ToolsDatabase.instance.loadTools()).single;
      expect(item.voltage, voltage);
      expect(item.copy().voltage, voltage);
      expect((await ToolsDatabase.instance.databaseOverview()).single['voltage'],
          voltage);
    }
  });

  testWidgets('Electrical type shows voltage, restores selection and saves it',
      (tester) async {
    tester.view.physicalSize = const Size(393, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ToolItem? saved;
    await tester.runAsync(() async {
      await ToolsDatabase.instance.database;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await Navigator.of(context).push<ToolItem>(
                  MaterialPageRoute(
                    builder: (_) => EditToolPage(
                      item: sampleTool(voltage: '24 V'),
                      nextId: 43,
                    ),
                  ),
                );
              },
              child: const Text('Editar'),
            ),
          );
        }),
      ));
      await tester.tap(find.text('Editar'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final voltageField = find.byKey(const ValueKey('tool_voltage'));
    expect(voltageField, findsOneWidget);
    expect(find.text('24 V'), findsOneWidget);
    expect(find.widgetWithText(VoltageBadge, '24'), findsOneWidget);
    expect(tester.widget<DropdownButton<String>>(find.descendant(
      of: voltageField,
      matching: find.byType(DropdownButton<String>),
    )).items!.map((item) => item.value).toList(), voltageOptionsFor('24 V'));

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Herramienta manual').last);
    await tester.pumpAndSettle();
    expect(voltageField, findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Herramienta eléctrica').last);
    await tester.pumpAndSettle();
    expect(find.text('24 V'), findsOneWidget);
    await tester.tap(voltageField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('230 V').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(VoltageBadge, '230'), findsOneWidget);
    expect(
      tester.state<FormFieldState<String>>(
        find.byKey(const ValueKey('tool_type')),
      ).value,
      'Herramienta eléctrica',
    );
    expect(tester.widget<TextFormField>(find.byType(TextFormField).first)
        .controller?.text, 'Taladro');
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();
    expect(find.text('Selecciona el tipo'), findsNothing);
    expect(find.text('Escribe el nombre'), findsNothing);
    // The caller receives the result once the popped route completes.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(saved?.voltage, '230 V');
    await tester.runAsync(() async {
      await ToolsDatabase.instance.saveTool(saved!);
      await ToolsDatabase.instance.closeForBackup();
      expect((await ToolsDatabase.instance.loadTools()).single.voltage, '230 V');
    });
    expect(tester.takeException(), isNull);
  });
}
