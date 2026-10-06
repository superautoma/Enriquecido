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
      file('iconos/$name', svg);
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
}
