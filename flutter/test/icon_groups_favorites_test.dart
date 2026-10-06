import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/main_quill_integrated_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    docs = await Directory.systemTemp.createTemp('icon_favorites_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => docs.path);
    await loadIconSettings();
  });
  tearDown(() async {
    await docs.delete(recursive: true);
    await loadIconSettings();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'Existing settings migrate without losing hidden icons or groups',
    () async {
      final file = await iconSettingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'hidden': ['electric_bombilla'],
          'groups': {'electric_bombilla': 'Herramientas'},
        }),
      );
      await loadIconSettings();
      expect(isIconHidden('electric_bombilla'), isTrue);
      expect(iconCategoryForKey('electric_bombilla'), 'Herramientas');
      expect(isIconFavorite('electric_bombilla'), isFalse);
      await saveIconGroup('Carpintería');
      await updateIconSettings('electric_bombilla', favorite: true);
      await loadIconSettings();
      expect(isIconHidden('electric_bombilla'), isTrue);
      expect(iconCategoryForKey('electric_bombilla'), 'Herramientas');
      expect(isIconFavorite('electric_bombilla'), isTrue);
    },
  );
  test('Custom group lifecycle preserves names, favorites and trash', () async {
    const key = 'electric_bombilla';
    await saveIconGroup(' Carpintería ');
    await updateIconSettings(
      key,
      group: 'Carpintería',
      favorite: true,
      hidden: true,
    );
    await saveIconName(key, 'Luz del taller');
    await loadIconSettings();
    expect(iconGroups, contains('Carpintería'));
    expect(isIconFavorite(key), isTrue);
    await saveIconGroup('Medición', original: 'Carpintería');
    await loadIconSettings();
    expect(iconCategoryForKey(key), 'Medición');
    expect(iconGroups, isNot(contains('Carpintería')));
    await deleteIconGroup('Medición');
    await loadIconSettings();
    expect(iconCategoryForKey(key), 'Mis iconos');
    expect(isIconFavorite(key), isTrue);
    expect(isIconHidden(key), isTrue);
    expect(appIconLabel(key), 'Luz del taller');
    await updateIconSettings(key, favorite: false, hidden: false);
    await loadIconSettings();
    expect(isIconFavorite(key), isFalse);
    expect(iconGroupNameError('herramientas'), isNotNull);
    expect(iconGroupNameError('Favoritos'), isNotNull);
    expect(iconGroupNameError('   '), isNotNull);
    await saveIconGroup('Fontanería');
    expect(iconGroupNameError('fontanería'), isNotNull);
  });
  test(
    'Imported group and favorite survive directory relocation and rename',
    () async {
      await saveIconGroup('Medición');
      final directory = await customIconsDirectory();
      final file = File('${directory.path}/regla.svg');
      await file.writeAsString('<svg/>');
      final key = 'custom:${file.path}';
      await saveCustomIconGroup(key, 'Medición');
      await updateIconSettings(key, favorite: true);
      await saveIconGroup('Precisión', original: 'Medición');
      await loadIconSettings();
      expect((await loadCustomIconGroups([key]))[key], 'Precisión');
      expect(iconCategoryForKey('custom:/restored/regla.svg'), 'Precisión');
      expect(isIconFavorite('custom:/restored/regla.svg'), isTrue);
      await deleteIconGroup('Precisión');
      expect((await loadCustomIconGroups([key]))[key], 'Mis iconos');
    },
  );
  testWidgets('Create, rename and delete a group through its page', (
    tester,
  ) async {
    Future<void> finish() async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(const MaterialApp(home: IconGroupsPage()));
    await tester.runAsync(() async {
      await tester.tap(find.text('Crear grupo'));
    });
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del grupo'),
      'Carpintería',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar'));
    });
    await finish();
    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, 'Carpintería'),
      200,
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Carpintería'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Opciones del grupo'));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Cambiar nombre'));
    });
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del grupo'),
      'Medición',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar'));
    });
    await finish();
    expect(find.widgetWithText(ListTile, 'Medición'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Opciones del grupo'));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Eliminar grupo'));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar grupo'));
    });
    await finish();
    expect(find.widgetWithText(ListTile, 'Medición'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Manager star and Favorites filter work after reopening', (
    tester,
  ) async {
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
    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar iconos'),
      'Enchufe Schuko',
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Añadir a favoritos'));
    });
    await finish();
    expect(find.byTooltip('Quitar de favoritos'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const MaterialApp(home: IconManagementPage()));
    });
    await finish();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favoritos').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Enchufe Schuko'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Quitar de favoritos'));
    });
    await finish();
    expect(find.widgetWithText(ListTile, 'Enchufe Schuko'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
