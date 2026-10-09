import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xml/xml.dart';

import 'package:gestor_herramientas/main_quill_integrated_test.dart';
import 'package:gestor_herramientas/svg_editor_model.dart';

const source =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><g fill="none" stroke="#123456" stroke-width="1"><path d="M4 4L20 20"/><circle cx="10" cy="10" r="3" fill="#e53935"/></g></svg>';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    docs = await Directory.systemTemp.createTemp('svg_editor_');
    await databaseFactory.setDatabasesPath('${docs.path}/db');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => docs.path,
        );
    await loadIconSettings();
    await loadIconNames();
  });
  tearDown(() async {
    await ToolsDatabase.instance.closeForBackup();
    await docs.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });
  test(
    'Real geometry, paint and circle export and reopen with renderer',
    () async {
      final doc = SvgEditorDocument.parse(source);
      expect(doc.multicolor, isTrue);
      final edited = doc.export(
        const SvgEdits(
          fill: '#23836d',
          stroke: '#000000',
          strokeWidth: 2,
          background: '#ffffff',
          scale: 1.2,
          x: 8,
          y: -5,
          rotation: 35,
          fit: true,
        ),
      );
      final evidence = Directory('build/svg-editor-evidence');
      await evidence.create(recursive: true);
      await File('${evidence.path}/svg-editor-example.svg')
          .writeAsString(edited);
      final root = XmlDocument.parse(edited).rootElement;
      expect(root.getAttribute('data-gestor-svg'), '1');
      expect(
        root.findAllElements('circle').first.getAttribute('id'),
        'svg_editor_background',
      );
      expect(edited, contains('matrix('));
      expect(edited, contains('stroke-width="2.0"'));
      expect(edited, contains('fill="#23836d"'));
      expect(edited, contains('stroke="#000000"'));
      expect(await SvgStringLoader(edited).loadBytes(null), isNotNull);
      expect(
        await SvgStringLoader(
          SvgEditorDocument.parse(edited).export(const SvgEdits()),
        ).loadBytes(null),
        isNotNull,
      );
      final replaced = SvgEditorDocument.parse(edited)
          .export(const SvgEdits(background: '#1976d2'));
      expect(
        XmlDocument.parse(replaced).descendants
            .whereType<XmlElement>()
            .where((e) => e.getAttribute('id') == 'svg_editor_background'),
        hasLength(1),
      );
    },
  );
  test('Reopening a centered copy never shrinks art by fitting its background', () {
    const input =
        '<svg viewBox="0 0 20 20"><rect width="20" height="20" stroke-width="0"/></svg>';
    final first = SvgEditorDocument.parse(input)
        .export(const SvgEdits(fit: true, background: '#ffffff'));
    final second = SvgEditorDocument.parse(first)
        .export(const SvgEdits(fit: true));
    final root = XmlDocument.parse(second).rootElement;
    final wrapper = root.findElements('g').first.getAttribute('transform')!;
    expect(wrapper, 'matrix(1.0 0.0 0.0 1.0 0.0 0.0)');
    final background = root.findElements('circle').single;
    expect(background.getAttribute('r'), '49.0');
    expect(background.getAttribute('fill'), '#ffffff');
    final cleared = SvgEditorDocument.parse(first)
        .export(const SvgEdits(background: 'none'));
    expect(
      XmlDocument.parse(cleared).rootElement.findElements('circle'),
      isEmpty,
    );
  });
  test('Unselected colors, inline styles, fundo and group transforms preserved', () async {
    const input =
        '<svg viewBox="0 0 80 80"><circle id="fondo" cx="40" cy="40" r="35" fill="#abcdef"/><g transform="translate(20 10) rotate(25)" style="fill:none;stroke:#123456;stroke-width:2"><path d="M0 0L30 30"/></g></svg>';
    final doc = SvgEditorDocument.parse(input);
    expect(doc.multicolor, isTrue);
    final unchanged = doc.export(const SvgEdits());
    expect(unchanged, contains('stroke="#123456"'));
    expect(unchanged, contains('translate(20 10) rotate(25)'));
    final edited = XmlDocument.parse(
      doc.export(const SvgEdits(fill: '#000000', stroke: '#ffffff')),
    );
    expect(
      edited.descendants
          .whereType<XmlElement>()
          .firstWhere((e) => e.getAttribute('id') == 'fondo')
          .getAttribute('fill'),
      '#abcdef',
    );
  });
  test('Centering uses effective geometry outside original viewBox with margins', () async {
    const offset =
        '<svg viewBox="0 0 24 24"><rect x="100" y="200" width="40" height="20" fill="#123456" stroke-width="0"/></svg>';
    final result = XmlDocument.parse(
      SvgEditorDocument.parse(offset).export(const SvgEdits(fit: true)),
    ).rootElement;
    final wrapper = result.findElements('g').first;
    final matrix = wrapper
        .getAttribute('transform')!
        .substring(7)
        .replaceAll(')', '')
        .split(' ')
        .map(double.parse)
        .toList();
    final centerX = 120 * matrix[0] + 210 * matrix[2] + matrix[4];
    final centerY = 120 * matrix[1] + 210 * matrix[3] + matrix[5];
    expect(centerX, closeTo(50, .001));
    expect(centerY, closeTo(50, .001));
    expect(matrix[0], closeTo(2, .001));
    expect(result.getAttribute('viewBox'), '0.0 0.0 100.0 100.0');
  });
  test(
    'Curves, arcs and all bundled assets produce valid centered documents',
    () async {
      final curve = SvgEditorDocument.parse(
        '<svg viewBox="0 0 100 100"><path d="M5 5C0 90 95 90 95 5A10 15 30 0 1 50 50Q20 20 5 5Z"/></svg>',
      );
      await SvgStringLoader(
        curve.export(const SvgEdits(fit: true, rotation: 90)),
      ).loadBytes(null);
      for (final file in Directory(
        'assets/icons/electricos',
      ).listSync().whereType<File>()) {
        final result = SvgEditorDocument.parse(await file.readAsString())
            .export(const SvgEdits(fit: true));
        await SvgStringLoader(result).loadBytes(null);
      }
    },
  );
  test('Hex, undo redo reset, new branch and invalid geometry', () {
    expect(svgEditorHex('#AbCdEf'), '#abcdef');
    expect(svgEditorHex('red'), isNull);
    expect(svgEditorHex('#12345'), isNull);
    final history = SvgEditHistory();
    history.push(history.current.copyWith(x: 10));
    history.push(history.current.copyWith(rotation: 45));
    history.undo();
    expect(history.current.rotation, 0);
    history.redo();
    expect(history.current.rotation, 45);
    history.undo();
    history.push(history.current.copyWith(fill: '#000000'));
    expect(history.canRedo, isFalse);
    history.reset();
    expect(history.current.x, 0);
    history.undo();
    expect(history.current.x, 10);
    for (final edits in [
      const SvgEdits(scale: 0),
      const SvgEdits(strokeWidth: -1),
      const SvgEdits(fill: 'http://bad'),
      SvgEdits(x: double.nan),
    ]) {
      expect(
        () => SvgEditorDocument.parse(source).export(edits),
        throwsFormatException,
      );
    }
  });
  test('Copies survive reload, names groups originals favorites and assignments untouched', () async {
    final dir = await customIconsDirectory();
    final original = File('${dir.path}/original.svg');
    await original.writeAsString(source);
    final key = 'custom:${original.path}';
    await saveIconName(key, 'Original');
    await saveCustomIconGroup(key, 'Mis iconos');
    await updateIconSettings(key, favorite: true);
    final option = FieldOption(
      fieldKey: 'type',
      label: 'Prueba',
      iconKey: key,
      colorValue: 0xff000000,
      circleColorValue: 0xffffffff,
    );
    final assignment = option.toMap();
    final hash = sha256.convert(await original.readAsBytes());
    final copy = await saveSvgEditorCopy(
      SvgEditorDocument.parse(source),
      const SvgEdits(
        fill: '#23836d',
        stroke: '#1976d2',
        strokeWidth: 2,
        x: 12,
        y: 6,
        rotation: 40,
        scale: 1.3,
        fit: true,
      ),
      name: '../../Copia',
      group: 'Mis iconos',
    );
    expect(copy, isNot(key));
    expect(File(customIconPathFromKey(copy)).parent.path, dir.path);
    await loadCustomIconKeys();
    await loadIconNames();
    await loadIconSettings();
    expect(appIconLabel(copy), '../../Copia');
    expect(isIconFavorite(key), isTrue);
    expect(option.toMap(), assignment);
    expect(sha256.convert(await original.readAsBytes()), hash);
    expect(appIconLabel(key), 'Original');
    expect(isSvgEditorCopy(copy), isTrue);
    expect(iconAppearance(copy).circle.a, 0);
    final rendered = iconWidgetForKey(copy, color: Colors.red) as SizedBox;
    expect((rendered.child! as SvgPicture).bytesLoader, isA<SvgFileLoader>());
    final saved = await File(customIconPathFromKey(copy)).readAsString();
    await SvgStringLoader(saved).loadBytes(null);
    final second = await saveSvgEditorCopy(
      SvgEditorDocument.parse(source),
      const SvgEdits(),
      name: '../../Copia',
      group: 'Mis iconos',
    );
    expect(second, isNot(copy));
    final before = await dir.list().length;
    await expectLater(
      saveSvgEditorCopy(
        SvgEditorDocument.parse(source),
        const SvgEdits(fill: 'bad'),
        name: 'bad',
        group: 'Mis iconos',
      ),
      throwsFormatException,
    );
    expect(await dir.list().length, before);
  });
  test(
    'Full backup restore and additive import retain exported SVG and metadata',
    () async {
      await ToolsDatabase.instance.database;
      await ToolsDatabase.instance.saveTool(
        ToolItem(
          id: 1,
          name: "Herramienta preservada",
          description: "Texto",
          descriptionDelta: "",
          barcode: "QA",
          quantity: 2,
          unit: "ud",
          minimumStock: 1,
          purchasePrice: 10,
          condition: "Bueno",
        ),
      );
      final key = await saveSvgEditorCopy(
        SvgEditorDocument.parse(source),
        const SvgEdits(fill: '#23836d', background: '#ffffff', fit: true),
        name: 'Mi SVG',
        group: 'Mis iconos',
      );
      final originalBytes = await File(customIconPathFromKey(key))
          .readAsBytes();
      await updateIconSettings(key, favorite: true);
      final backup = await BackupManager.createBackup();
      final saved = File('${docs.path}/preserved.zip');
      await backup.copy(saved.path);
      final archive = ZipDecoder().decodeBytes(await saved.readAsBytes());
      expect(archive.files.any((f) => f.name.endsWith('.svg')), isTrue);
      await File(customIconPathFromKey(key)).writeAsString('damaged');
      await BackupManager.restoreBackup(saved.path);
      expect(
        await File(customIconPathFromKey(key)).readAsBytes(),
        originalBytes,
      );
      await loadCustomIconKeys();
      expect(appIconLabel(key), 'Mi SVG');
      expect(isIconFavorite(key), isTrue);
      expect(isSvgEditorCopy(key), isTrue);
      await SvgStringLoader(
        await File(customIconPathFromKey(key)).readAsString(),
      ).loadBytes(null);
      final plan = await BackupImportPlan.prepare(saved.path);
      try {
        await plan.apply();
      } finally {
        await plan.dispose();
      }
      expect(await ToolsDatabase.instance.loadTools(), isNotEmpty);
    },
  );
  test('Imported SVG ZIP stays valid, duplicate detection retained', () async {
    final svg = SvgEditorDocument.parse(source)
        .export(const SvgEdits(fill: '#1976d2', fit: true));
    final archive = Archive();
    final bytes = utf8.encode(svg);
    archive.addFile(ArchiveFile('../../svg_edit_new.svg', bytes.length, bytes));
    final encoded = ZipEncoder().encode(archive);
    final keys = await importIconArchive(encoded);
    expect(keys, hasLength(1));
    expect(await importIconArchive(encoded), isEmpty);
    expect(await File(customIconPathFromKey(keys.first)).readAsString(), svg);
  });
}
