import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main_quill_integrated_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  setUp(() async {
    docs = await Directory.systemTemp.createTemp('icon_management_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => docs.path);
    await loadIconNames();
    await loadIconSettings();
  });
  tearDown(() async {
    await docs.delete(recursive: true);
    await loadIconNames();
    await loadIconSettings();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
  });

  test('Names, groups and trash persist without changing the icon identity', () async {
    const key = 'electric_bombilla';
    await saveIconName(key, 'Luz del taller');
    await updateIconSettings(key, group: 'Herramientas', hidden: true);
    await loadIconNames();
    await loadIconSettings();
    expect(appIconLabel(key), 'Luz del taller');
    expect(iconCategoryForKey(key), 'Herramientas');
    expect(isIconHidden(key), isTrue);
    expect(appIconChoiceFor(key).key, key);
    await updateIconSettings(key, hidden: false);
    await saveIconName(key, '');
    await loadIconNames();
    await loadIconSettings();
    expect(appIconLabel(key), 'Bombilla');
    expect(isIconHidden(key), isFalse);
    // Imported files retain their aliases after a backup moves their directory.
    await saveIconName('custom:/old/icons/photo.svg', 'Mi dibujo');
    expect(appIconLabel('custom:/restored/icons/photo.svg'), 'Mi dibujo');
  });

  testWidgets('Search, rename, delete and restore through the manager', (tester) async {
    Future<void> finish() async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: IconManagementPage()));
    });
    await finish();
    final search = find.widgetWithText(TextField, 'Buscar iconos');
    await tester.enterText(search, 'Enchufe Schuko');
    await tester.pumpAndSettle();
    await tester.runAsync(() async { await tester.tap(find.widgetWithText(ListTile, 'Enchufe Schuko')); });
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre del icono'), 'Toma del taller');
    await tester.runAsync(() async { await tester.tap(find.text('Guardar')); });
    await finish();
    await tester.enterText(search, 'Toma del taller');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Toma del taller'), findsOneWidget);
    await tester.runAsync(() async { await tester.tap(find.byTooltip('Opciones del icono')); });
    await tester.pumpAndSettle();
    await tester.runAsync(() async { await tester.tap(find.text('Eliminar')); });
    await tester.pumpAndSettle();
    await tester.runAsync(() async { await tester.tap(find.widgetWithText(FilledButton, 'Eliminar')); });
    await finish();
    expect(find.widgetWithText(ListTile, 'Toma del taller'), findsNothing);
    await tester.tap(find.text('Papelera'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Toma del taller'), findsOneWidget);
    await tester.runAsync(() async { await tester.tap(find.widgetWithText(ListTile, 'Toma del taller')); });
    await finish();
    expect(find.widgetWithText(ListTile, 'Toma del taller'), findsNothing);
    await tester.tap(find.text('Iconos activos'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Toma del taller'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
