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
      for (final view in ['Conjunto compacto', 'Lista', 'Cuadrícula', 'Galería ampliada', 'Por colores']) {
        await tester.tap(find.byKey(const ValueKey('icon_picker_view')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(view));
        await tester.pumpAndSettle();
        expect(find.text('Enchufe Schuko').first, findsOneWidget);
        final tile = view == 'Lista'
            ? find.byType(ListTile)
            : find.descendant(of: view == 'Por colores' ? find.byType(CustomScrollView) : find.byType(GridView), matching: find.byType(InkWell));
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
      for (final view in ['Cuadrícula', 'Conjunto compacto', 'Por grupos', 'Galería ampliada', 'Por colores', 'Lista']) {
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

  test('Empty trash removes unused files and preserves assigned icons across reloads', () async {
    final directory = await customIconsDirectory();
    final unused = File('${directory.path}/unused.svg');
    final used = File('${directory.path}/used.svg');
    final active = File('${directory.path}/active.svg');
    for (final file in [unused, used, active]) {
      await file.writeAsString('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path d="M8 8L56 56"/></svg>');
    }
    final unusedKey = 'custom:${unused.path}';
    final usedKey = 'custom:${used.path}';
    final activeKey = 'custom:${active.path}';
    const builtIn = 'electric_bombilla';
    await saveIconName(usedKey, 'Asignado');
    await saveIconAppearance(usedKey, const IconAppearance(0xFFE53935, 0xFFEAF2FB));
    await File('${unused.path}.group.json').writeAsString('{"group":"Mis iconos"}');
    for (final key in [unusedKey, usedKey, builtIn]) {
      await updateIconSettings(key, hidden: true, favorite: true);
    }
    final result = await emptyIconTrash(protectedKeys: {usedKey, builtIn});
    expect(result.emptied, 3);
    expect(result.keptForUsage, 2);
    expect(await unused.exists(), isFalse);
    expect(await File('${unused.path}.group.json').exists(), isFalse);
    expect(await used.exists(), isTrue);
    expect(await active.exists(), isTrue);
    await loadCustomIconKeys();
    for (final key in [unusedKey, usedKey, builtIn]) {
      expect(isIconRemoved(key), isTrue);
      expect(isIconHidden(key), isTrue);
      expect(isIconFavorite(key), isFalse);
    }
    expect(isIconRemoved(activeKey), isFalse);
    expect(appIconLabel(usedKey), 'Asignado');
    expect(iconAppearance(usedKey).lineValue, 0xFFE53935);
    await updateIconSettings(activeKey, favorite: true);
    await loadIconSettings();
    expect(isIconRemoved(usedKey), isTrue);
    final again = await emptyIconTrash(protectedKeys: {usedKey});
    expect(again.emptied, 0);
  });

  testWidgets('Empty trash confirms all icons regardless of search and cancels safely',
      (tester) async {
    await tester.runAsync(() async {
      await updateIconSettings('electric_bombilla', hidden: true);
      await updateIconSettings('electric_enchufe_schuko', hidden: true);
      await tester.pumpWidget(const MaterialApp(home: IconManagementPage()));
    });
    await finish(tester);
    expect(find.byKey(const ValueKey('empty_icon_trash')), findsNothing);
    await tester.tap(find.text('Papelera'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Buscar iconos'), 'no coincide');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('empty_icon_trash')));
    await tester.pumpAndSettle();
    expect(find.textContaining('los 2 iconos de toda la papelera'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(isIconRemoved('electric_bombilla'), isFalse);
    expect(isIconHidden('electric_bombilla'), isTrue);
    expect(find.text('Gestor de iconos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Background color groups cover hues, neutral colors and transparency', () async {
    const key = 'electric_bombilla';
    final cases = {
      0xFFFF0000: 'Rojos', 0xFFFF8000: 'Naranjas', 0xFFFFFF00: 'Amarillos',
      0xFF00FF00: 'Verdes', 0xFF00FFFF: 'Turquesas', 0xFF0000FF: 'Azules',
      0xFF8000FF: 'Violetas', 0xFFFF00FF: 'Rosas', 0xFFFFFFFF: 'Blancos',
      0xFF808080: 'Grises', 0xFF000000: 'Negros', 0x00000000: 'Sin fondo',
      0x20E3F2FD: 'Azules',
    };
    for (final entry in cases.entries) {
      await saveIconAppearance(key, IconAppearance(0xFFFF0000, entry.key));
      expect(iconBackgroundColorGroup(key), entry.value);
    }
  });

  for (final manager in [false, true]) {
    testWidgets('Color view regroups after saving background, manager=$manager',
        (tester) async {
      const key = 'electric_enchufe_schuko';
      await tester.runAsync(() async {
        await saveIconAppearance(key, const IconAppearance(0xFF23836D, 0xFF1976D2));
        await tester.pumpWidget(MaterialApp(home: manager
            ? const IconManagementPage() : const IconPickerPage(currentKey: key)));
      });
      await finish(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Buscar iconos'), 'Enchufe Schuko');
      await finish(tester);
      await tester.tap(find.byKey(ValueKey(manager ? 'icon_manager_view' : 'icon_picker_view')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Por colores'));
      await tester.pumpAndSettle();
      final prefix = manager ? 'icon_manager_color_' : 'icon_picker_color_';
      expect(find.byKey(ValueKey('${prefix}Azules')), findsOneWidget);
      final tile = find.descendant(of: find.byType(CustomScrollView), matching: find.byType(InkWell));
      await tester.longPress(tile);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('icon_circle_4293212469')));
      await tester.tap(find.byKey(const ValueKey('icon_circle_4293212469')));
      await tester.runAsync(() async { await tester.tap(find.text('Guardar')); });
      await finish(tester);
      expect(find.byKey(ValueKey('${prefix}Azules')), findsNothing);
      expect(find.byKey(ValueKey('${prefix}Rojos')), findsOneWidget);
      expect(iconAppearance(key).lineValue, 0xFF23836D);
      expect(tester.takeException(), isNull);
    });
  }

}
