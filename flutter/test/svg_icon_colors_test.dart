import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main_quill_integrated_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    docs = await Directory.systemTemp.createTemp('svg_colors_');
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

  test('SVG mapping keeps circle, lines and transparency independent', () {
    const mapper = IconSvgColorMapper(Colors.red, Colors.blue);
    expect(mapper.substitute('fondo', 'circle', 'fill', Colors.white), Colors.blue);
    expect(mapper.substitute(null, 'path', 'stroke', Colors.black), Colors.red);
    expect(mapper.substitute(null, 'path', 'fill', Colors.black), Colors.red);
    expect(mapper.substitute(null, 'path', 'fill', Colors.transparent), Colors.transparent);
    expect(mapper, const IconSvgColorMapper(Colors.red, Colors.blue));
    expect(mapper == const IconSvgColorMapper(Colors.green, Colors.blue), isFalse);
  });

  test('Appearance survives restart and unrelated manager changes', () async {
    const key = 'custom:/old/place/test.svg';
    await saveIconAppearance(key, const IconAppearance(0xFFE53935, 0xFFDDEEFF));
    await saveIconGroup('Medición');
    await updateIconSettings(key, favorite: true, group: 'Medición');
    await saveIconName(key, 'Medidor');
    await loadIconSettings();
    final restored = iconAppearance('custom:/restored/place/test.svg');
    expect(restored.lineValue, 0xFFE53935);
    expect(restored.circleValue, 0xFFDDEEFF);
    expect(isIconFavorite(key), isTrue);
    expect(iconCategoryForKey(key), 'Medición');
    expect(appIconLabel(key), 'Medidor');
    expect(hasIconCircle(key), isTrue);
    expect(hasIconCircle('custom:/photo.png'), isFalse);
  });

  test('ZIP imports exactly 80 glyphs, preserving names and both colors', () async {
    final archive = Archive();
    final catalog = <Map<String, Object>>[];
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path stroke="#000" fill="none" d="M8 8L56 56"/></svg>';
    void file(String name, String data) {
      final bytes = utf8.encode(data);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    for (var i = 0; i < 80; i++) {
      final name = 'icono_$i.svg';
      file('iconos/$name', svg.replaceFirst('M8 8L56 56', 'M8 $i L56 56'));
      file('con_circulo/$name', svg);
      catalog.add({'archivo': 'iconos/$name', 'nombre': 'Motivo $i',
        'color_lineas': '#23836D', 'color_fondo': '#E2F1ED'});
    }
    file('catalogo.json', jsonEncode({'iconos': catalog}));
    file('vista_previa.svg', svg);
    final keys = await importIconArchive(ZipEncoder().encode(archive));
    expect(keys.length, 80);
    expect(keys.toSet().length, 80);
    expect(appIconLabel(keys.first), 'Motivo 0');
    expect(iconAppearance(keys.first).lineValue, 0xFF23836D);
    expect(iconAppearance(keys.first).circleValue, 0xFFE2F1ED);
    expect(await loadCustomIconKeys(), hasLength(80));
    await loadIconNames();
    await loadIconSettings();
    expect(appIconLabel(keys.last), 'Motivo 79');
    expect(iconAppearance(keys.last).lineValue, 0xFF23836D);
  });

  test('ZIP paths stay inside private icon storage', () async {
    final archive = Archive();
    final bytes = utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>');
    archive.addFile(ArchiveFile('../../escaped.svg', bytes.length, bytes));
    final keys = await importIconArchive(ZipEncoder().encode(archive));
    final storage = await customIconsDirectory();
    expect(File(customIconPathFromKey(keys.single)).parent.path, storage.path);
    expect(await File('${docs.path}/escaped.svg').exists(), isFalse);
  });
  test('Repeated ZIP content is skipped despite renamed files and preserves edits', () async {
    List<int> zip(Map<String, String> entries) {
      final archive = Archive();
      for (final entry in entries.entries) {
        final bytes = utf8.encode(entry.value);
        archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
      }
      return ZipEncoder().encode(archive);
    }
    const svg = '<svg xmlns="http://www.w3.org/2000/svg"><path d="M8 8L56 56"/></svg>';
    final firstReport = IconImportReport();
    final first = await importIconArchive(zip({'uno.svg': svg, 'otro_nombre.svg': svg}), report: firstReport);
    expect(first, hasLength(1));
    expect(firstReport.skippedDuplicates, 1);
    await saveIconName(first.single, 'Mi nombre');
    await saveIconAppearance(first.single, const IconAppearance(0xFFFF0000, 0xFF0000FF));
    final report = IconImportReport();
    expect(await importIconArchive(zip({'renombrado.svg': svg}), report: report), isEmpty);
    expect(report.skippedDuplicates, 1);
    expect(appIconLabel(first.single), 'Mi nombre');
    expect(iconAppearance(first.single).lineValue, 0xFFFF0000);
    expect(await loadCustomIconKeys(), hasLength(1));
    final different = await importIconArchive(zip({'uno.svg': svg.replaceFirst('56 56', '40 40')}));
    expect(different, hasLength(1));
    await updateIconSettings(first.single, hidden: true);
    final trashed = IconImportReport();
    expect(await importIconArchive(zip({'uno.svg': svg}), report: trashed), isEmpty);
    expect(trashed.duplicatesInTrash, 1);
  });

  test('Duplicate review detects existing copies by content, not name or edited color', () async {
    final directory = await customIconsDirectory();
    final a = File('${directory.path}/primero.svg');
    final b = File('${directory.path}/renombrado.svg');
    final c = File('${directory.path}/distinto.svg');
    await a.writeAsString('<svg/>');
    await b.writeAsString('<svg/>');
    await c.writeAsString('<svg viewBox="0 0 64 64"/>');
    final ka = 'custom:${a.path}', kb = 'custom:${b.path}';
    await saveIconAppearance(kb, const IconAppearance(0xFFFF0000, 0xFF00FF00));
    final groups = await findDuplicateIconGroups();
    expect(groups, hasLength(1));
    expect(groups.single.toSet(), {ka, kb});
    await updateIconSettings(kb, hidden: true);
    expect(await findDuplicateIconGroups(), isEmpty);
    expect(await a.exists(), isTrue);
    expect(await b.exists(), isTrue);
  });

}
