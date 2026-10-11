import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import '../lib/visual_search.dart';
import '../lib/main_quill_integrated_test.dart';

Uint8List shape(int kind, {int brightness = 0}) {
  final data = Uint8List(128 * 128 * 4);
  for (var y = 0; y < 128; y++) {
    for (var x = 0; x < 128; x++) {
      final inside = kind == 0
          ? (x > 54 && x < 70 && y > 15 && y < 110)
          : kind == 1
          ? (y > 54 && y < 70 && x > 15 && x < 110)
          : false;
      final value = (inside ? 30 : 200) + brightness;
      final i = (y * 128 + x) * 4;
      data[i] = data[i + 1] = data[i + 2] = value;
      data[i + 3] = 255;
    }
  }
  return data;
}

Future<String> photo(Directory dir, String name, int kind) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  canvas.drawRect(
    kind == 0
        ? const Rect.fromLTWH(54, 15, 16, 95)
        : const Rect.fromLTWH(15, 54, 95, 16),
    Paint()..color = Colors.black,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(128, 128);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(png!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return file.path;
}

ToolItem tool(int id, String path, {int? parent}) => ToolItem(
  id: id,
  name: 'Herramienta $id',
  description: '',
  descriptionDelta: '',
  barcode: '',
  quantity: 1,
  unit: 'ud',
  minimumStock: 0,
  purchasePrice: 0,
  condition: 'Bueno',
  parentId: parent,
  images: [ToolImage(toolId: id, path: path)],
);
Future<void> finishVisualSearch(WidgetTester tester) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) return;
  }
  fail('Local photo comparison did not finish');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('visual-test-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test('Different shapes with identical colors and brightness tolerance', () {
    final vertical = VisualDescriptor.fromRgba(shape(0), 128)!;
    expect(vertical.similarity(vertical), closeTo(1, .00001));
    expect(
      vertical.similarity(VisualDescriptor.fromRgba(shape(1), 128)!),
      lessThan(.90),
    );
    expect(
      vertical.similarity(
        VisualDescriptor.fromRgba(shape(0, brightness: 20), 128)!,
      ),
      greaterThan(.99),
    );
    expect(VisualDescriptor.fromRgba(shape(2), 128), isNull);
  });
  testWidgets(
    'PNG content ranking, missing/corrupt files, cache invalidation and cancellation',
    (tester) async {
      await tester.runAsync(() async {
        final query = await photo(dir, 'query.png', 0);
        final same = await photo(dir, 'unrelated-name.png', 0);
        final other = await photo(dir, 'query-copy-name.png', 1);
        final corrupt = File('${dir.path}/broken.png');
        await corrupt.writeAsString('broken');
        final engine = LocalVisualSearch();
        final report = await engine.search(query, [
          VisualCandidate(1, [other]),
          VisualCandidate(2, [same, '${dir.path}/missing.png', corrupt.path]),
        ]);
        expect(report.matches.map((m) => m.id), [2, 1]);
        expect(report.comparablePhotos, 2);
        expect(report.skippedPhotos, 2);
        expect(report.hasCloseMatch, isTrue);
        final count = engine.cachedDescriptors;
        await engine.search(query, [
          VisualCandidate(2, [same]),
        ]);
        expect(engine.cachedDescriptors, count);
        await File(same).writeAsBytes(await File(other).readAsBytes());
        expect(
          (await engine.search(query, [
            VisualCandidate(2, [same]),
          ])).hasCloseMatch,
          isFalse,
        );
        final empty = await engine.search(query, [
          VisualCandidate(3, ['${dir.path}/missing.png']),
        ]);
        expect(empty.comparablePhotos, 0);
        expect(empty.matches, isEmpty);
        await expectLater(
          engine.search(corrupt.path, []),
          throwsFormatException,
        );
        expect(
          (await engine.search(query, [
            VisualCandidate(1, [other]),
          ], cancelled: () => true)).matches,
          isEmpty,
        );
      });
    },
  );
  testWidgets('Permission denial and cancellation are handled', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisualInventoryResults(
            source: ImageSource.camera,
            items: const [],
            eligibleItems: const [],
            engine: LocalVisualSearch(),
            picker: (_) async =>
                throw PlatformException(code: 'camera_access_denied'),
            onOpen: (_) {},
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Permiso denegado'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisualInventoryResults(
            key: const ValueKey('cancel'),
            source: ImageSource.gallery,
            items: const [],
            eligibleItems: const [],
            engine: LocalVisualSearch(),
            picker: (_) async => null,
            onOpen: (_) {},
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(closed, isTrue);
  });
  testWidgets('Eligible pieces, result opening and no close match', (
    tester,
  ) async {
    late String query, other;
    await tester.runAsync(() async {
      query = await photo(dir, 'query.png', 0);
      other = await photo(dir, 'other.png', 1);
    });
    final items = [tool(1, other), tool(2, query, parent: 1)];
    ToolItem? opened;
    Widget page(List<ToolItem> eligible) => MaterialApp(
      home: Scaffold(
        body: VisualInventoryResults(
          source: ImageSource.gallery,
          items: items,
          eligibleItems: eligible,
          engine: LocalVisualSearch(),
          picker: (_) async => XFile(query),
          onOpen: (item) => opened = item,
          onClose: () {},
        ),
      ),
    );
    await tester.pumpWidget(page(items));
    await finishVisualSearch(tester);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Pieza de Herramienta 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('visual_result_2')));
    expect(opened?.id, 2);
    items[1].voltage = '18 V';
    items[1].type = 'Herramienta manual';
    final facts = InventoryFacts(items);
    final combined = selectInventoryTools(
      items,
      const InventoryPreferences(
        includePieces: true,
        types: {'Herramienta manual'},
        conditions: {'Bueno'},
        voltages: {'18 V'},
      ),
      facts,
      query: 'herramienta 2 18V',
    );
    await tester.pumpWidget(page(combined));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('visual_result_2')), findsOneWidget);
    expect(find.byKey(const ValueKey('visual_result_1')), findsNothing);
    await tester.pumpWidget(
      page(selectInventoryTools(items, const InventoryPreferences(), facts)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('visual_result_2')), findsNothing);
    expect(find.textContaining('No hay coincidencias fiables'), findsOneWidget);
    await tester.pumpWidget(page([]));
    await tester.pumpAndSettle();
    expect(find.textContaining('No hay resultados con'), findsOneWidget);
  });
  testWidgets('No comparable photographs has an explicit empty state', (
    tester,
  ) async {
    late String query;
    await tester.runAsync(() async {
      query = await photo(dir, 'query.png', 0);
    });
    final missing = tool(1, '${dir.path}/absent.png');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisualInventoryResults(
            source: ImageSource.gallery,
            items: [missing],
            eligibleItems: [missing],
            engine: LocalVisualSearch(),
            picker: (_) async => XFile(query),
            onOpen: (_) {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await finishVisualSearch(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('No hay imágenes comparables'), findsOneWidget);
    expect(find.byKey(const ValueKey('visual_result_1')), findsNothing);
  });
}
