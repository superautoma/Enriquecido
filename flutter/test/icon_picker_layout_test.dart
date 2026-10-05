import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/main_quill_integrated_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('icon_picker_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => documents.path,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await documents.delete(recursive: true);
  });

  for (final width in [320.0, 393.0, 600.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('Names fit at width $width and text scale $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.runAsync(() async {
          await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            home: const IconPickerPage(currentKey: 'tool_art_handsaw'),
          ));
          await loadCustomIconKeys();
        });
        await tester.pumpAndSettle();
        expect(find.text('Sierra de mano'), findsOneWidget);
        expect(find.text('Destornillador'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Also exercise long imported filenames with the same cell geometry.
        final folder = Directory(
          '${documents.path}/tool_images/custom_icons',
        );
        final file = File('${folder.path}/icono_personalizado_nombre_largo.png');
        await tester.runAsync(() async {
          await file.writeAsBytes(base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg==',
          ));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            home: IconPickerPage(currentKey: 'custom:${file.path}'),
          ));
          await loadCustomIconKeys();
        });
        await tester.pumpAndSettle();
        expect(find.text('icono_personalizado_nombre_largo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
