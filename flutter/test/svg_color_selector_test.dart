import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_herramientas/main_quill_integrated_test.dart';
import 'package:gestor_herramientas/svg_editor_model.dart';

void main() {
  Future<void> open(WidgetTester tester, void Function(String?) receive) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Abrir colores'),
              onPressed: () async => receive(
                await showSvgColorSelector(
                  context,
                  title: 'Color de relleno',
                  initialValue: '#009688',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir colores'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Selection is confirmed explicitly and cancellation preserves value',
    (tester) async {
      String? result = 'pending';
      await open(tester, (value) => result = value);
      await tester.tap(find.byKey(const ValueKey('svg_color_#e91e63')));
      await tester.pump();
      expect(result, 'pending');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('Abrir colores'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('svg_color_#e91e63')));
      await tester.tap(find.text('Seleccionar'));
      await tester.pumpAndSettle();
      expect(result, '#e91e63');
    },
  );
  testWidgets(
    'Custom hex validation and original versus transparent are distinct',
    (tester) async {
      String? result;
      await open(tester, (value) => result = value);
      await tester.tap(find.text('Personalizar'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('svg_color_hex')),
        '#xyz',
      );
      await tester.tap(find.text('Seleccionar'));
      await tester.pumpAndSettle();
      expect(find.text('Introduce un color #RRGGBB'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('svg_color_hex')),
        '#ABCDEF',
      );
      await tester.tap(find.text('Seleccionar'));
      await tester.pumpAndSettle();
      expect(result, '#abcdef');
      for (final option in {
        'Sin color': 'none',
        'Conservar original': '',
      }.entries) {
        await tester.tap(find.text('Abrir colores'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(OutlinedButton, option.key));
        await tester.tap(find.text('Seleccionar'));
        await tester.pumpAndSettle();
        expect(result, option.value);
      }
    },
  );
  testWidgets(
    'Editor applies one confirmed change and undo restores the original',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SvgEditorPage(
            document: SvgEditorDocument.parse(
              '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="10" y="10" width="80" height="80" fill="#123456"/></svg>',
            ),
            originalKey: 'electric_alicates',
            initialName: 'Prueba',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final choose = find.byKey(const ValueKey('svg_select_fill'));
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('svg_color_#e91e63')));
      await tester.tap(find.text('Seleccionar'));
      await tester.pumpAndSettle();
      TextFormField field() => tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Relleno'),
      );
      expect(field().initialValue, '#e91e63');
      await tester.tap(find.byTooltip('Deshacer'));
      await tester.pumpAndSettle();
      expect(field().initialValue, '');
      await tester.tap(find.byTooltip('Rehacer'));
      await tester.pumpAndSettle();
      expect(field().initialValue, '#e91e63');
    },
  );
  testWidgets(
    'Small screen and enlarged text have scrollable accessible controls',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: const Scaffold(
              body: SvgColorSelector(title: 'Color de relleno'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Seleccionar'), findsOneWidget);
    },
  );
}
