import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/main_quill_integrated_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    docs = await Directory.systemTemp.createTemp('electric_collection_');
    await databaseFactory.setDatabasesPath(docs.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => docs.path,
        );
  });
  tearDown(() async {
    await ToolsDatabase.instance.closeForBackup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await docs.delete(recursive: true);
  });

  testWidgets('All 50 assets render and are selectable under Mis iconos', (
    tester,
  ) async {
    final choices = appIconChoices
        .where((i) => isElectricCollectionKey(i.key))
        .toList();
    expect(choices, hasLength(50));
    expect(choices.map((i) => i.key).toSet(), hasLength(50));
    expect(choices.every((i) => i.category == 'Mis iconos'), isTrue);
    // Decode every SVG, including those normally outside the lazy grid viewport.
    for (final choice in choices) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: iconWidgetForKey(choice.key, color: Colors.red, size: 24),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SvgPicture), findsOneWidget);
    }
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: IconPickerPage(currentKey: choices.first.key)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Enchufe Schuko'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Interruptor'), 200,
      scrollable: find.descendant(of: find.byType(GridView),
        matching: find.byType(Scrollable)));
    expect(find.text('Interruptor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'Upgrade v6 preserves options and independent colors survive reopening',
    () async {
      final db = await ToolsDatabase.instance.database;
      await db.execute(
        'ALTER TABLE field_options DROP COLUMN circle_color_value',
      );
      await db.setVersion(6);
      final before = await db.query('field_options');
      await ToolsDatabase.instance.closeForBackup();
      final migrated = await ToolsDatabase.instance.database;
      expect(await migrated.query('field_options'), hasLength(before.length));
      final row = FieldOption.fromMap(
        (await migrated.query('field_options')).first,
      );
      final option = row.copyWith(
        iconKey: 'electric_bombilla',
        colorValue: 0xFFCD4945,
        circleColorValue: 0xFFEAF2FB,
      );
      await migrated.update(
        'field_options',
        option.toMap(),
        where: 'id = ?',
        whereArgs: [option.id],
      );
      await ToolsDatabase.instance.closeForBackup();
      final reopened = await ToolsDatabase.instance.database;
      final saved = FieldOption.fromMap(
        (await reopened.query(
          'field_options',
          where: 'id = ?',
          whereArgs: [option.id],
        )).single,
      );
      expect(saved.iconKey, 'electric_bombilla');
      expect(saved.color, const Color(0xFFCD4945));
      expect(saved.circleColor, const Color(0xFFEAF2FB));
    },
  );
}
