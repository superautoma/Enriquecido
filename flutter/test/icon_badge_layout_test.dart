import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../lib/main_quill_integrated_test.dart';

void main() {
  testWidgets('Type and status buttons give imported SVGs the full badge space',
      (tester) async {
    late Directory directory;
    late File file;
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path d="M10 10L54 54" stroke="black"/></svg>';
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('icon_badge_');
      file = File('${directory.path}/test.svg');
      await file.writeAsString(svg);
    });
    for (final field in ['type', 'condition']) {
      for (final size in [32.0, 48.0]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
          child: SizedBox(width: 280, child: Row(children: [
            fieldOptionIconWidget(FieldOption(fieldKey: field,
              label: 'Nueva opción', iconKey: 'custom:${file.path}',
              colorValue: 0xFF34688B), size: size),
            const SizedBox(width: 8),
            const Expanded(child: Text('Nueva opción')),
          ])),
        ))));
        expect(find.byType(CircleAvatar), findsNothing);
        expect(tester.getSize(find.byType(ClipOval)).width, size);
        expect(tester.getSize(find.byType(SvgPicture)).width,
            closeTo(size * .90, .01));
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      expect(await file.readAsString(), svg);
      await directory.delete(recursive: true);
    });
  });

  testWidgets('Built-in icons use the same outer size as imported icons',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: fieldOptionIconWidget(FieldOption(fieldKey: 'condition',
        label: 'Bueno', iconKey: 'check', colorValue: 0xFF43A047),
        size: 48),
    ))));
    expect(tester.getSize(find.byType(ClipOval)), const Size(48, 48));
    expect(tester.getSize(find.byType(Icon)).width, closeTo(31.2, .01));
    expect(find.byType(CircleAvatar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
