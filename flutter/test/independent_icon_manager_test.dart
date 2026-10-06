import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main_quill_integrated_test.dart';

Future<void> finish(WidgetTester tester) async {
  // Navigation creates the next page during a frame. Start that frame in
  // the real async zone so its file reads can finish outside the fake clock.
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    docs = await Directory.systemTemp.createTemp('independent_icons_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (_) async => docs.path);
    await loadIconSettings();
    await loadIconNames();
  });
  tearDown(() async {
    await docs.delete(recursive: true);
    await loadIconSettings();
    await loadIconNames();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
  });

  test('Legacy assignments remain intact; central colors apply to every usage', () async {
    final option = FieldOption(fieldKey: 'type', label: 'Taladro',
      iconKey: 'electric_bombilla', colorValue: 0xFFCD4945,
      circleColorValue: 0xFFEAF2FB);
    final stored = option.toMap();
    expect(option.color, const Color(0xFFCD4945));
    expect(option.circleColor, const Color(0xFFEAF2FB));
    await saveIconAppearance(option.iconKey,
      const IconAppearance(0xFF23836D, 0xFFE2F1ED));
    await loadIconSettings();
    expect(option.color, const Color(0xFF23836D));
    expect(option.circleColor, const Color(0xFFE2F1ED));
    expect(option.toMap(), stored);
    final second = option.copyWith(label: 'Otro tipo');
    expect(second.color, option.color);
    expect(second.circleColor, option.circleColor);
    expect(canEditIconColors('handyman'), isTrue);
    expect(canEditIconColors('tool_art_hammer'), isFalse);
  });

  testWidgets('Type editor only names and selects; picker has no management actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: FieldOptionEditPage(
      fieldKey: 'type', position: 0, existing: FieldOption(
        fieldKey: 'type', label: 'Eléctrica', iconKey: 'electric_bombilla',
        colorValue: 0xFF1976D2, circleColorValue: 0xFFEAF2FB),
    )));
    await finish(tester);
    expect(find.text('Color del círculo'), findsNothing);
    expect(find.text('Color de las líneas'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.byType(OutlinedButton));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await finish(tester);
    expect(find.text('Seleccionar icono'), findsOneWidget);
    expect(find.text('Importar'), findsNothing);
    expect(find.text('GALERÍA...'), findsNothing);
    expect(find.text('GENERAR CON IA'), findsNothing);
    expect(find.byTooltip('Gestionar iconos'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Buscar iconos'), 'Enchufe Schuko');
    await finish(tester);
    final selectedIcon = find.descendant(
      of: find.byType(GridView), matching: find.text('Enchufe Schuko'));
    expect(selectedIcon, findsOneWidget);
    await tester.tap(selectedIcon);
    await finish(tester);
    expect(find.text('Seleccionar icono'), findsNothing);
    expect(find.text('Icono: Enchufe Schuko'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Built-in colors are edited and saved from the manager', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: IconManagementPage()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await finish(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Buscar iconos'), 'Enchufe Schuko');
    await finish(tester);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await finish(tester);
    await tester.tap(find.text('Cambiar colores'));
    await finish(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('icon_line_4293212469')));
    await finish(tester);
    await tester.tap(find.byKey(const ValueKey('icon_line_4293212469')));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await finish(tester);
    expect(find.text('Colores del icono'), findsNothing);
    expect(iconAppearance('electric_enchufe_schuko').lineValue, 0xFFE53935);
    expect(tester.takeException(), isNull);
  });
}
