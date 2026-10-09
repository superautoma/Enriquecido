import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gestor_herramientas/main_quill_integrated_test.dart';
import 'package:gestor_herramientas/svg_editor_model.dart';
import 'svg_editor_test.dart' show source;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  setUp(() async {
    docs = await Directory.systemTemp.createTemp('svg_widget_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => docs.path,
        );
    await loadIconNames();
    await loadIconSettings();
  });
  tearDown(() async {
    await docs.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });
  testWidgets(
    'Small screen real save invalid hex history and rendering of saved badge',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SvgEditorPage(
                        document: SvgEditorDocument.parse(source),
                        originalKey: 'electric_alicates',
                        initialName: 'SVG prueba',
                      ),
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await settle(tester);
      expect(find.text('Editor SVG'), findsOneWidget);
      expect(find.text('24 px'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final fill = find.widgetWithText(TextFormField, 'Relleno');
      await tester.ensureVisible(fill);
      await tester.enterText(fill, '#bad');
      final save = find.byKey(const ValueKey('svg_save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await settle(tester);
      expect(result, isNull);
      expect(find.text('Utiliza #RRGGBB o none'), findsWidgets);
      await tester.ensureVisible(fill);
      await tester.enterText(fill, '#23836d');
      await tester.ensureVisible(find.text('Centrar y ajustar'));
      await tester.tap(find.text('Centrar y ajustar'));
      await tester.pump();
      await tester.tap(find.byTooltip('Deshacer'));
      await tester.pump();
      await tester.tap(find.byTooltip('Rehacer'));
      await tester.pump();
      await tester.ensureVisible(save);
      await tester.runAsync(() async {
        await tester.tap(save);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settle(tester);
      expect(result, isNotNull);
      expect(find.text('Editor SVG'), findsNothing);
      expect(
        await tester.runAsync(
          () => File(customIconPathFromKey(result!)).readAsString(),
        ),
        contains('fill="#23836d"'),
      );
      for (final size in [24.0, 48.0, 80.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: iconBadgeWidget(
                  result!,
                  color: Colors.red,
                  circleColor: Colors.transparent,
                  size: size,
                ),
              ),
            ),
          ),
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'Cancel asks only with changes, discard never writes and reset is clean',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SvgEditorPage(
                      document: SvgEditorDocument.parse(source),
                      originalKey: 'electric_alicates',
                      initialName: 'SVG prueba',
                    ),
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await settle(tester);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.text('Descartar cambios'), findsNothing);
      expect(find.text('Editor SVG'), findsNothing);
      await tester.tap(find.text('Abrir'));
      await settle(tester);
      await tester.ensureVisible(find.text('Centrar y ajustar'));
      await tester.tap(find.text('Centrar y ajustar'));
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Descartar cambios'), findsOneWidget);
      await tester.tap(find.text('Seguir editando'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Restablecer'));
      await tester.tap(find.text('Restablecer'));
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.text('Editor SVG'), findsNothing);
      expect(
        await tester.runAsync(
          () async => (await customIconsDirectory()).list().length,
        ),
        0,
      );
    },
  );
  testWidgets(
    'Manager action in list grid gallery detail and selector preserve original',
    (tester) async {
      for (final mode in [
        'Lista',
        'Cuadrícula',
        'Galería ampliada',
        'Detalle',
      ]) {
        await tester.runAsync(
          () =>
              tester.pumpWidget(const MaterialApp(home: IconManagementPage())),
        );
        await settle(tester);
        await tester.enterText(
          find.widgetWithText(TextField, 'Buscar iconos'),
          'Alicates de corte',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        tester.testTextInput.hide();
        await settle(tester);
        if (mode != 'Lista') {
          await tester.tap(find.byKey(const ValueKey('icon_manager_view')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text(mode).last);
          await tester.pumpAndSettle();
          await tester.tap(
            find
                .ancestor(
                  of: find.text(mode).last,
                  matching: find.byType(CheckedPopupMenuItem<String>),
                )
                .first,
          );
          await tester.pumpAndSettle();
        }
        if (mode == 'Lista') {
          await tester.tap(find.byTooltip('Opciones del icono'));
          await tester.pumpAndSettle();
        } else if (mode == 'Detalle') {
          await tester.ensureVisible(find.text('Más opciones'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Más opciones'));
          await tester.pumpAndSettle();
        } else {
          await tester.tap(find.text('Alicates de corte').last);
          await tester.pumpAndSettle();
        }
        expect(find.text('Editar SVG'), findsOneWidget, reason: mode);
        await tester.runAsync(() async {
          await tester.tap(find.text('Editar SVG'));
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await settle(tester);
        expect(find.text('Editor SVG'), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      }
      await tester.runAsync(
        () => tester.pumpWidget(
          const MaterialApp(
            home: IconPickerPage(currentKey: 'electric_alicates_corte'),
          ),
        ),
      );
      await settle(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Editar SVG del icono actual'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await settle(tester);
      expect(find.text('Editor SVG'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.text('Seleccionar icono'), findsOneWidget);
      expect(
        await tester.runAsync(
          () async => (await customIconsDirectory()).list().length,
        ),
        0,
      );
    },
  );
}
