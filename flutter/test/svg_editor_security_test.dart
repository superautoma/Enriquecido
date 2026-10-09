import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gestor_herramientas/svg_editor_model.dart';
import 'package:gestor_herramientas/main_quill_integrated_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final attacks = <String>[
    '<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]><svg>&x;</svg>',
    '<svg><script>alert(1)</script></svg>',
    '<svg onload="alert(1)"/>',
    '<svg><foreignObject/></svg>',
    '<svg><image href="https://bad"/></svg>',
    '<svg><use href="file:///bad"/></svg>',
    '<svg><path fill="url(http://bad)"/></svg>',
    '<svg><style>path{fill:red}</style></svg>',
    '<svg><g style="filter:url(#bad)"/></svg>',
    '<svg><g><svg/></g></svg>',
    '<svg xmlns:x="bad"><x:path/></svg>',
    '<svg><g transform="scale(1e99)"/></svg>',
    '<svg viewBox="0 0 -1 10"/>',
    '<svg><path d="M0 0Q"/></svg>',
    '<svg><rect width="-4"/></svg>',
    '<svg><g stroke-width="NaN"/></svg>',
    '<svg><g transform="skewX(30)"/></svg>',
    '<svg><mask/></svg>',
    '<svg><text>Unsupported</text></svg>',
    '<svg><g stroke-miterlimit="10000"/></svg>',
    '<svg><?bad test?></svg>',
    '<svg',
    '<svg>${List.filled(26, "<g>").join()}${List.filled(26, "</g>").join()}</svg>',
    '<svg>${List.filled(1501, "<circle/>").join()}</svg>',
    '<svg><desc>${"a" * (svgEditorMaxBytes + 1)}</desc></svg>',
  ];
  for (var i = 0; i < attacks.length; i++) {
    test('Reject unsafe unsupported or unbounded SVG $i before renderer', () {
      expect(() => validateSvgSource(attacks[i]), throwsFormatException);
    });
  }
  test(
    'Safe subset import preflight prevents partial writes on malicious ZIP',
    () async {
      final docs = await Directory.systemTemp.createTemp('svg_security_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => docs.path,
          );
      try {
        final archive = Archive();
        for (final entry in {
          'safe.svg': '<svg><circle cx="5" cy="5" r="3"/></svg>',
          'bad.svg': attacks[1],
        }.entries) {
          final bytes = utf8.encode(entry.value);
          archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
        }
        await expectLater(
          importIconArchive(ZipEncoder().encode(archive)),
          throwsFormatException,
        );
        expect(await (await customIconsDirectory()).list().length, 0);
        expect(await (await iconSettingsFile()).exists(), isFalse);
      } finally {
        await docs.delete(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
      }
    },
  );
}
