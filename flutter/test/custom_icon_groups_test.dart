import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/main_quill_integrated_test.dart';

class IconFilePicker extends FilePicker {
  IconFilePicker(this.file);
  final File file;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(
      name: 'Llave_importada.png',
      path: file.path,
      size: await file.length(),
    ),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Import into Herramientas and retain group after reopening', (
    tester,
  ) async {
    late Directory docs;
    late File source;
    await tester.runAsync(() async {
      docs = await Directory.systemTemp.createTemp('icon_group_test_');
      source = File('${docs.path}/original.png');
      await source.writeAsBytes(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg==',
      ));
    });
    FilePicker.platform = IconFilePicker(source);
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => docs.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await docs.delete(recursive: true);
    });

    Future<void> open(String key) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MaterialApp(home: IconPickerPage(currentKey: key)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }

    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: IconManagementPage()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Herramientas').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Importar'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    late List<String> imported;
    await tester.runAsync(() async {
      imported = await loadCustomIconKeys();
      expect(imported, hasLength(1));
      expect((await loadCustomIconGroups(imported))[imported.single],
          'Herramientas');
    });
    final label = appIconLabel(imported.single);
    expect(find.text(label), findsOneWidget);
    await open(imported.single);
    expect(find.text(label), findsOneWidget);
    expect(find.text('Martillo'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Existing imports without group metadata remain accessible.
    await tester.runAsync(() async {
      final directory = await customIconsDirectory();
      final legacy = File('${directory.path}/Antiguo.png');
      await source.copy(legacy.path);
      final all = await loadCustomIconKeys();
      expect((await loadCustomIconGroups(all))['custom:${legacy.path}'],
          'Mis iconos');
    });
  });
}
