import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/app_security.dart';
import '../lib/main_quill_integrated_test.dart';
import '../lib/tools_main_menu.dart';

const options = {
  'inventory': 'Herramientas',
  'loans': 'Préstamos',
  'maintenance': 'Mantenimientos',
  'trash': 'Papelera',
  'management': 'Gestión de herramientas',
  'ai_photo': 'Crear ficha con IA',
  'ai_settings': 'Conexión con ChatGPT',
  'fields': 'Tipos y estados',
  'icons': 'Gestor de iconos',
  'security': 'Seguridad y acceso',
  'button_feedback': 'Sonido y vibración',
  'backup': 'Copia de seguridad',
  'import': 'Importar datos',
  'database': 'Base de datos',
  'restore': 'Restaurar y sustituir',
};

Future<void> reveal(WidgetTester tester, String value) async {
  final scroll = find.descendant(
    of: find.byKey(const ValueKey('tools_menu_scroll')),
    matching: find.byType(Scrollable),
  );
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(
    find.byKey(ValueKey('menu_$value')),
    180,
    scrollable: scroll,
  );
  await tester.pumpAndSettle();
}

Future<void> finishIo(WidgetTester tester) async {
  // Finish route/drawer transitions before checking destination I/O.
  await tester.pump(const Duration(milliseconds: 400));
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        !tester.binding.hasScheduledFrame) {
      return;
    }
  }
  fail('La pantalla no terminó de cargar');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  var pickerCalls = 0;
  final sharedFiles = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FilePickerIO.registerWith();
    // Optional real-font rendering for previews, without adding a production dependency.
    if (Platform.environment['V122_MENU_PREVIEW_DIR'] != null) {
      final fonts =
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
      for (final entry in {
        'Roboto': 'Roboto-Regular.ttf',
        'MaterialIcons': 'MaterialIcons-Regular.otf',
      }.entries) {
        final loader = FontLoader(entry.key);
        loader.addFont(
          File(
            '$fonts/${entry.value}',
          ).readAsBytes().then(ByteData.sublistView),
        );
        await loader.load();
      }
    }
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tools_menu_');
    await databaseFactory.setDatabasesPath('${directory.path}/database');
    pickerCalls = 0;
    sharedFiles.clear();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    messenger.setMockMethodCallHandler(
      buttonFeedbackChannel,
      (_) async => {'hasVibrator': true},
    );
    messenger.setMockMethodCallHandler(
      toolAiChannel,
      (call) async => call.method == 'read'
          ? jsonEncode({
              'version': 1,
              'host_id': 'urn:uuid:00000000-0000-0000-0000-000000000000',
              'active': 'saved-account',
              'profiles': [
                {'client_id': 'saved-account', 'email': 'menu@test.local'},
              ],
            })
          : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(
        'miguelruivo.flutter.plugins.filepicker',
        JSONMethodCodec(),
      ),
      (call) async {
        pickerCalls++;
        return null; // Cancel selection; never replace test data.
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (call) async {
        expect(call.method, 'shareFiles');
        sharedFiles.addAll(
          List<String>.from((call.arguments as Map)['paths'] as List),
        );
        return 'shared';
      },
    );
  });
  tearDown(() async {
    await ToolsDatabase.instance.closeForBackup();
    for (final channel in [
      const MethodChannel('plugins.flutter.io/path_provider'),
      buttonFeedbackChannel,
      toolAiChannel,
      const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
      const MethodChannel('dev.fluttercommunity.plus/share'),
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    await directory.delete(recursive: true);
  });

  testWidgets(
    'All grouped menu options remain reachable and dispatch their original actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final selected = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: ToolsMainMenu(onSelected: selected.add),
            ),
          ),
        ),
      );
      expect(find.text('Menú'), findsOneWidget);
      expect(find.text('Gestor de Herramientas'), findsOneWidget);
      expect(find.text('TRABAJO DIARIO'), findsOneWidget);
      for (final entry in options.entries) {
        await reveal(tester, entry.key);
        expect(find.text(entry.value), findsOneWidget);
        final tile = find.byKey(ValueKey('menu_${entry.key}'));
        final icon = find
            .descendant(of: tile, matching: find.byType(Icon))
            .first;
        final iconRect = tester.getRect(icon);
        final containerRect = tester.getRect(
          find.ancestor(of: icon, matching: find.byType(Container)).first,
        );
        expect(containerRect.intersect(iconRect), iconRect);
        expect(containerRect.center, iconRect.center);
        expect(tester.widget<Icon>(icon).size, 22);
        await tester.tap(tile);
        expect(tester.takeException(), isNull);
      }
      expect(selected, options.keys.toList());
      await reveal(tester, 'backup');
      expect(find.text('DATOS'), findsOneWidget);
    },
  );

  testWidgets(
    'Narrow, landscape and enlarged-text menus scroll without overflowing',
    (tester) async {
      for (final size in [
        const Size(280, 540),
        const Size(740, 320),
        const Size(390, 800),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.centerRight,
                child: ToolsMainMenu(onSelected: (_) {}),
              ),
            ),
          ),
        );
        for (final value in options.keys) {
          await reveal(tester, value);
          expect(tester.takeException(), isNull, reason: '$size / $value');
          expect(
            tester.getRect(find.byKey(ValueKey('menu_$value'))).width,
            lessThanOrEqualTo(size.width),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    },
  );

  testWidgets(
    'Inventory drawer opens every existing destination and returns to inventory',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preview = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: preview,
          child: const GestorHerramientasApp(testBypassSecurity: true),
        ),
      );
      await finishIo(tester);

      Future<void> open() async {
        await tester.tap(find.byKey(const ValueKey('open_tools_menu')));
        await tester.pumpAndSettle();
        expect(find.text('Menú'), findsOneWidget);
      }

      Future<void> capture(String name) async {
        final destination = Platform.environment['V122_MENU_PREVIEW_DIR'];
        if (destination == null) return;
        final boundary =
            preview.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(destination).create(recursive: true);
          await File(
            '$destination/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await open();
      await capture('menu-superior');
      await reveal(tester, 'restore');
      await capture('menu-datos');
      await reveal(tester, 'inventory');
      await tester.tap(find.byKey(const ValueKey('menu_inventory')));
      await tester.pumpAndSettle();
      expect(find.text('Menú'), findsNothing);
      expect(find.text('Mis herramientas'), findsOneWidget);

      final destinations = <String, Type>{
        'loans': LoansPage,
        'maintenance': MaintenancePage,
        'trash': ToolTrashPage,
        'management': ManagementHubPage,
        'ai_photo': AiPhotoPage,
        'ai_settings': ChatGptSettingsPage,
        'fields': FieldOptionsManagementPage,
        'icons': IconManagementPage,
        'security': SecuritySettingsPage,
        'button_feedback': ButtonFeedbackPage,
        'import': ImportBackupPage,
        'database': DatabaseManagementPage,
      };
      for (final entry in destinations.entries) {
        await open();
        await reveal(tester, entry.key);
        await tester.tap(find.byKey(ValueKey('menu_${entry.key}')));
        await finishIo(tester);
        expect(find.byType(entry.value), findsOneWidget, reason: entry.key);
        expect(find.text('Menú'), findsNothing);
        if (entry.key == 'fields') {
          expect(find.text('Tipo'), findsWidgets);
          expect(find.text('Estado'), findsWidgets);
        }
        if (entry.key == 'ai_settings') {
          expect(
            ChatGptConnection.instance.profiles.single.email,
            'menu@test.local',
          );
        }
        expect(tester.takeException(), isNull, reason: entry.key);
        final context = tester.element(find.byType(entry.value));
        Navigator.of(context).pop();
        await finishIo(tester);
        expect(find.text('Mis herramientas'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await finishIo(tester);
    },
  );

  testWidgets(
    'Backup and restore still invoke existing data actions without losing inventory',
    (tester) async {
      await tester.pumpWidget(
        const GestorHerramientasApp(testBypassSecurity: true),
      );
      await finishIo(tester);
      final before = await tester.runAsync(
        () => ToolsDatabase.instance.loadTools(),
      );
      for (final value in ['backup', 'restore']) {
        await tester.tap(find.byKey(const ValueKey('open_tools_menu')));
        await tester.pumpAndSettle();
        await reveal(tester, value);
        await tester.tap(find.byKey(ValueKey('menu_$value')));
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
          if (value == 'backup' ? sharedFiles.isNotEmpty : pickerCalls > 0)
            break;
        }
        await finishIo(tester);
        expect(find.text('Menú'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      expect(sharedFiles.single, endsWith('.zip'));
      expect(
        await tester.runAsync(() => File(sharedFiles.single).exists()),
        isTrue,
      );
      expect(pickerCalls, 1);
      final after = await tester.runAsync(
        () => ToolsDatabase.instance.loadTools(),
      );
      expect(after!.map((item) => item.id), before!.map((item) => item.id));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
