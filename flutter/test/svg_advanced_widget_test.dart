import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gestor_herramientas/main_quill_integrated_test.dart';
import 'package:gestor_herramientas/svg_editor_model.dart';
import 'svg_advanced_test.dart' show advancedSource, element;
import 'svg_editor_widget_test.dart' show settle;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  setUp(() async {
    docs = await Directory.systemTemp.createTemp('svg_phase2_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => docs.path,
        );
    await loadIconNames();
    await loadIconSettings();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await docs.delete(recursive: true);
  });
  Future<void> launch(
    WidgetTester tester,
    void Function(String?) receive, {
    bool basic = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                receive(
                  await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => basic
                          ? SvgEditorPage(
                              document: SvgEditorDocument.parse(advancedSource),
                              originalKey: 'electric_alicates',
                              initialName: 'Prueba avanzada',
                            )
                          : const SvgAdvancedPage(
                              source: advancedSource,
                              initialName: 'Prueba avanzada',
                              initialGroup: 'Mis iconos',
                            ),
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
    if (basic) {
      final entry = find.byKey(const ValueKey('svg_advanced'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await settle(tester);
    }
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<String> save(WidgetTester tester, String? Function() result) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('advanced_save')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
    expect(result(), isNotNull);
    return (await tester.runAsync(
      () => File(customIconPathFromKey(result()!)).readAsString(),
    ))!;
  }

  testWidgets(
    'Real basic editor opens advanced, adds and recolors only a copy on small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = File('${docs.path}/original.svg');
      await tester.runAsync(() => original.writeAsString(advancedSource));
      String? result;
      await launch(tester, (value) => result = value, basic: true);
      expect(find.text('SVG avanzado'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('Nuevo rectángulo'));
      await tapVisible(tester, find.text('Relleno de selección'));
      await tester.tap(find.byKey(const ValueKey('svg_color_#e91e63')));
      await tester.tap(find.widgetWithText(FilledButton, 'Seleccionar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Deshacer'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rehacer'));
      await tester.pumpAndSettle();
      final source = await save(tester, () => result);
      expect(source, contains('#e91e63'));
      expect(element(source, 'red').getAttribute('fill'), '#ff0000');
      expect(
        element(source, 'curve').getAttribute('d'),
        'M 20 40 Q 40 10 60 40 T 90 40',
      );
      expect(
        await tester.runAsync(() => original.readAsString()),
        advancedSource,
      );
      expect(find.text('SVG avanzado'), findsNothing);
      expect(find.text('Editor SVG'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Tree selects curve and numeric node controls preserve other shapes',
    (tester) async {
      String? result;
      await launch(tester, (value) => result = value);
      await tester.tap(find.text('Elementos'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Trazado · curve'));
      await tester.tap(find.text('Nodos').first);
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.byKey(const ValueKey('advanced_handle_1_0')),
      );
      await tapVisible(tester, find.text('Editar coordenadas'));
      await tester.enterText(
        find.byKey(const ValueKey('advanced_node_X')),
        '45.123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('advanced_node_Y')),
        '46.789',
      );
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      final source = await save(tester, () => result);
      expect(element(source, 'curve').getAttribute('d'), contains('C'));
      expect(element(source, 'red').getAttribute('fill'), '#ff0000');
      final doc = SvgVectorDocument(source),
          handle = doc
              .handles('curve')
              .firstWhere((h) => h.segment == 1 && h.point == 0);
      expect(handle.position.dx, closeTo(45.123, .0001));
      expect(handle.position.dy, closeTo(46.789, .0001));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Canvas dragging is an undoable edit and cancel discards without files',
    (tester) async {
      String? result;
      await launch(tester, (value) => result = value);
      await tapVisible(tester, find.text('Nuevo rectángulo'));
      await tapVisible(tester, find.text('Mover'));
      final canvas = find.byKey(const ValueKey('advanced_canvas'));
      await tester.ensureVisible(canvas);
      String canvasSource() =>
          (tester
                      .widget<SvgPicture>(
                        find.descendant(
                          of: canvas,
                          matching: find.byType(SvgPicture),
                        ),
                      )
                      .bytesLoader
                  as SvgStringLoader)
              .provideSvg(null);
      final beforeDrag = canvasSource();
      await tester.drag(canvas, const Offset(35, 20));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final afterDrag = canvasSource();
      expect(afterDrag, isNot(beforeDrag));
      await tester.tap(find.byTooltip('Deshacer'));
      await tester.pumpAndSettle();
      expect(canvasSource(), beforeDrag);
      await tester.tap(find.byTooltip('Rehacer'));
      await tester.pumpAndSettle();
      expect(canvasSource(), afterDrag);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar edición avanzada?'), findsOneWidget);
      await tester.tap(find.text('Seguir editando'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar'));
      await settle(tester);
      expect(result, isNull);
      expect(
        docs
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.svg')),
        isEmpty,
      );
    },
  );
  testWidgets(
    'Vertical drawing drag and camera zoom preserve geometry and world coordinates',
    (tester) async {
      await launch(tester, (_) {});
      await tapVisible(tester, find.text('Nuevo rectángulo'));
      final canvas = find.byKey(const ValueKey('advanced_canvas'));
      String rendered() =>
          (tester
                      .widget<SvgPicture>(
                        find.descendant(
                          of: canvas,
                          matching: find.byType(SvgPicture),
                        ),
                      )
                      .bytesLoader
                  as SvgStringLoader)
              .provideSvg(null);
      await tapVisible(tester, find.text('Vista'));
      await tester.ensureVisible(canvas);
      final original = rendered();
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1)
        ..setTranslationRaw(-100, -100, 0);
      await tester.pumpAndSettle();
      expect(rendered(), original);
      await tapVisible(tester, find.text('Mover'));
      await tester.ensureVisible(canvas);
      final before = SvgVectorDocument(rendered()).elements.last.bounds;
      await tester.drag(canvas, const Offset(0, 40));
      await tester.pumpAndSettle();
      final after = SvgVectorDocument(rendered()).elements.last.bounds;
      expect(after.top - before.top, closeTo(7.5, .01));
      expect(after.width, closeTo(before.width, .001));
      await tester.tap(find.byTooltip('Deshacer'));
      await tester.pumpAndSettle();
      expect(rendered(), original);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Canvas Bézier handle dragging changes only selected path and is one undo operation',
    (tester) async {
      await launch(tester, (_) {});
      await tester.tap(find.text('Elementos'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Trazado · curve'));
      await tester.tap(find.text('Lienzo'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Nodos'));
      final canvas = find.byKey(const ValueKey('advanced_canvas'));
      await tester.ensureVisible(canvas);
      String rendered() =>
          (tester
                      .widget<SvgPicture>(
                        find.descendant(
                          of: canvas,
                          matching: find.byType(SvgPicture),
                        ),
                      )
                      .bytesLoader
                  as SvgStringLoader)
              .provideSvg(null);
      final before = rendered(), doc = SvgVectorDocument(before);
      final handle = doc.handles('curve')[1], rect = tester.getRect(canvas);
      final local = Offset(
        (handle.position.dx - doc.viewport.left) /
            doc.viewport.width *
            rect.width,
        (handle.position.dy - doc.viewport.top) /
            doc.viewport.height *
            rect.height,
      );
      await tester.dragFrom(rect.topLeft + local, const Offset(24, -24));
      await tester.pumpAndSettle();
      final after = rendered();
      expect(after, isNot(before));
      expect(
        element(after, 'red').toXmlString(),
        element(before, 'red').toXmlString(),
      );
      final moved = SvgVectorDocument(after).handles('curve')[1];
      expect(moved.position.dx - handle.position.dx, closeTo(9, .01));
      expect(moved.position.dy - handle.position.dy, closeTo(-9, .01));
      await tester.tap(find.byTooltip('Deshacer'));
      await tester.pumpAndSettle();
      expect(rendered(), before);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Vista pans vertically and pinches with scale limits without editing SVG',
    (tester) async {
      await launch(tester, (_) {});
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Vista'));
      final canvas = find.byKey(const ValueKey('advanced_canvas'));
      await tester.ensureVisible(canvas);
      await tester.pumpAndSettle();
      String rendered() =>
          (tester
                      .widget<SvgPicture>(
                        find.descendant(
                          of: canvas,
                          matching: find.byType(SvgPicture),
                        ),
                      )
                      .bytesLoader
                  as SvgStringLoader)
              .provideSvg(null);
      final original = rendered();
      final controller = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      await tester.drag(canvas, const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(controller.value.getTranslation().y, closeTo(40, .01));
      final center = tester.getCenter(canvas);
      final a = await tester.startGesture(
            center - const Offset(30, 0),
            pointer: 1,
          ),
          b = await tester.startGesture(
            center + const Offset(30, 0),
            pointer: 2,
          );
      await a.moveTo(center - const Offset(50, 0));
      await b.moveTo(center + const Offset(50, 0));
      await tester.pump();
      await a.moveTo(center - const Offset(70, 0));
      await b.moveTo(center + const Offset(70, 0));
      await tester.pump();
      expect(controller.value.entry(0, 0), greaterThan(1.5));
      await a.moveTo(center - const Offset(2000, 0));
      await b.moveTo(center + const Offset(2000, 0));
      await tester.pump();
      expect(controller.value.entry(0, 0), closeTo(8, .001));
      await a.moveTo(center - const Offset(.1, 0));
      await b.moveTo(center + const Offset(.1, 0));
      await tester.pump();
      expect(controller.value.entry(0, 0), closeTo(.5, .001));
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      final c = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 3,
      );
      final d = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 4,
      );
      await c.moveTo(center - const Offset(1, 0));
      await d.moveTo(center + const Offset(1, 0));
      await tester.pump();
      expect(controller.value.entry(0, 0), closeTo(.5, .001));
      await c.up();
      await d.up();
      await tester.pumpAndSettle();
      expect(rendered(), original);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar edición avanzada?'), findsNothing);
      expect(await tester.runAsync(() => docs.list().toList()), isEmpty);
    },
  );
  testWidgets(
    'Small drag updates escape guide snapping and ignore selected group descendants',
    (tester) async {
      await launch(tester, (_) {});
      await tester.tap(find.text('Elementos'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Grupo · layer'));
      await tester.tap(find.text('Lienzo'));
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.widgetWithText(FilterChip, 'Ajuste a guías'),
      );
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Mover'));
      final canvas = find.byKey(const ValueKey('advanced_canvas'));
      await tester.ensureVisible(canvas);
      String rendered() =>
          (tester
                      .widget<SvgPicture>(
                        find.descendant(
                          of: canvas,
                          matching: find.byType(SvgPicture),
                        ),
                      )
                      .bytesLoader
                  as SvgStringLoader)
              .provideSvg(null);
      final original = rendered(),
          before = SvgVectorDocument(
            original,
          ).elements.firstWhere((e) => e.id == 'layer').bounds;
      final gesture = await tester.startGesture(tester.getCenter(canvas));
      for (var i = 0; i < 30; i++) {
        await gesture.moveBy(const Offset(2, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      final after = rendered(),
          bounds = SvgVectorDocument(
            after,
          ).elements.firstWhere((e) => e.id == 'layer').bounds;
      expect(bounds.center.dx - before.center.dx, closeTo(22.5, 3.1));
      expect(
        element(after, 'green').toXmlString(),
        element(original, 'green').toXmlString(),
      );
      await tester.tap(find.byTooltip('Deshacer'));
      await tester.pumpAndSettle();
      expect(rendered(), original);
      expect(tester.takeException(), isNull);
    },
  );
}
