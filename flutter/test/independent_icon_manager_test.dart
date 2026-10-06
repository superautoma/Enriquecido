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
    await tester.tap(find.byTooltip('Opciones del icono'));
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
  testWidgets('Picker edits SVG background and stroke without selecting or leaving',
      (tester) async {
    late String key;
    await tester.runAsync(() async {
      final directory = await customIconsDirectory();
      final file = File('${directory.path}/aviso.svg');
      await file.writeAsString('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path stroke="#BD7A23" fill="none" d="M32 8L56 54H8Z"/></svg>');
      key = 'custom:${file.path}';
      await saveIconName(key, 'Aviso propio');
      await tester.pumpWidget(MaterialApp(home: IconPickerPage(currentKey: key)));
    });
    await finish(tester);
    await tester.tap(find.byKey(const ValueKey('picker_edit_current_colors')));
    await finish(tester);
    expect(find.text('Color del círculo'), findsOneWidget);
    expect(find.text('Color de las líneas'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('icon_circle_4279858898')));
    await tester.tap(find.byKey(const ValueKey('icon_circle_4279858898')));
    await tester.ensureVisible(find.byKey(const ValueKey('icon_line_4293212469')));
    await tester.tap(find.byKey(const ValueKey('icon_line_4293212469')));
    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar'));
    });
    await finish(tester);
    expect(find.text('Seleccionar icono'), findsOneWidget);
    expect(find.text('Colores del icono'), findsNothing);
    final expectedCircle = const Color(0xFF1976D2).withValues(alpha: 0.16).toARGB32();
    expect(iconAppearance(key).circleValue, expectedCircle);
    expect(iconAppearance(key).lineValue, 0xFFE53935);
    await tester.runAsync(() async { await loadIconSettings(); });
    expect(iconAppearance(key).lineValue, 0xFFE53935);

    final tile = find.descendant(of: find.byType(GridView),
      matching: find.text('Aviso propio'));
    await tester.longPress(tile);
    await finish(tester);
    expect(find.text('Colores del icono'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('icon_line_4279858898')));
    await tester.tap(find.byKey(const ValueKey('icon_line_4279858898')));
    await tester.tap(find.text('Cancelar'));
    await finish(tester);
    expect(iconAppearance(key).lineValue, 0xFFE53935);
    expect(find.text('Seleccionar icono'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 480.0, 800.0]) {
    testWidgets('Picker views preserve filtering, colors and selection at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? selected;
      await tester.pumpWidget(MaterialApp(home: Builder(
        builder: (context) => Scaffold(body: TextButton(
          onPressed: () async {
            selected = await Navigator.push<String>(context,
              MaterialPageRoute(builder: (_) => const IconPickerPage(
                currentKey: 'electric_enchufe_schuko')));
          },
          child: const Text('Abrir selector'),
        )),
      )));
      await tester.tap(find.text('Abrir selector'));
      await finish(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Buscar iconos'), 'Enchufe Schuko');
      await finish(tester);
      expect(find.descendant(of: find.byType(GridView),
        matching: find.text('Enchufe Schuko')), findsOneWidget);
      for (final view in ['Conjunto compacto', 'Lista', 'Cuadrícula', 'Galería ampliada']) {
        await tester.tap(find.byKey(const ValueKey('icon_picker_view')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(view));
        await tester.pumpAndSettle();
        expect(find.text('Enchufe Schuko').first, findsOneWidget);
        final tile = view == 'Lista'
            ? find.byType(ListTile)
            : find.descendant(of: find.byType(GridView), matching: find.byType(InkWell));
        expect(tile, findsOneWidget);
        if (view == 'Conjunto compacto') {
          expect(find.descendant(of: find.byType(GridView), matching: find.byType(Text)), findsNothing);
        }
        await tester.longPress(tile);
        await tester.pumpAndSettle();
        expect(find.text('Colores del icono'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(selected, isNull);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const ValueKey('icon_picker_view')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lista'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(selected, 'electric_enchufe_schuko');
      expect(find.text('Seleccionar icono'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 800.0]) {
    testWidgets('Manager supports four views and keeps editing at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(home: IconManagementPage()));
      });
      await finish(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Buscar iconos'), 'Enchufe Schuko');
      await finish(tester);
      for (final view in ['Cuadrícula', 'Conjunto compacto', 'Por grupos', 'Galería ampliada', 'Lista']) {
        await tester.tap(find.byKey(const ValueKey('icon_manager_view')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(view));
        await tester.pumpAndSettle();
        if (view == 'Por grupos') {
          expect(find.byKey(ValueKey('icon_manager_group_${iconCategoryForKey('electric_enchufe_schuko')}')), findsOneWidget);
        }
        final tile = view == 'Lista' ? find.byType(ListTile)
            : find.descendant(of: find.byType(CustomScrollView), matching: find.byType(InkWell));
        expect(tile, findsOneWidget);
        await tester.longPress(tile);
        await tester.pumpAndSettle();
        expect(find.text('Colores del icono'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        if (view != 'Lista') {
          await tester.tap(tile);
          await tester.pumpAndSettle();
          expect(find.text('Cambiar nombre'), findsOneWidget);
          expect(find.text('Cambiar grupo'), findsOneWidget);
          expect(find.text('Eliminar'), findsOneWidget);
          await tester.runAsync(() async {
            await tester.tap(find.text(isIconFavorite('electric_enchufe_schuko')
                ? 'Quitar de favoritos' : 'Añadir a favoritos'));
          });
          await finish(tester);
        }
        expect(find.text('Gestor de iconos'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('Ordenar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nombre: Z–A'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
      await tester.tap(find.text('Papelera'));
      await tester.pumpAndSettle();
      expect(find.text('La papelera está vacía'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('Icon ordering respects names, groups, favorites and original order', () async {
    const a = 'electric_enchufe_schuko';
    const b = 'electric_bombilla';
    const c = 'electric_cuadro_electrico';
    final keys = [b, c, a];
    await saveIconName(a, 'Álvaro');
    await saveIconName(b, 'Zeta');
    await saveIconName(c, 'Beta');
    expect(orderedIconKeys(keys, 'original'), [b, c, a]);
    expect(orderedIconKeys(keys, 'az'), [a, c, b]);
    expect(orderedIconKeys(keys, 'za'), [b, c, a]);
    await updateIconSettings(b, favorite: true);
    expect(orderedIconKeys(keys, 'favorites'), [b, a, c]);
    await saveIconGroup('Medición');
    await updateIconSettings(b, group: 'Medición');
    await updateIconSettings(a, group: 'Herramientas');
    expect(orderedIconKeys(keys, 'group'), [a, b, c]);
    expect(keys, [b, c, a]);
    await saveIconName(c, 'Álvaro');
    expect(orderedIconKeys([c, a], 'az'), [c, a]);
  });

}
