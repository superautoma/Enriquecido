import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/app_security.dart';
import '../lib/main.dart' as official;
import '../lib/main_quill_integrated_test.dart' as integrated;

void main() {
  testWidgets(
    'Default entry point launches the complete app with security enabled',
    (tester) async {
      official.main();
      await tester.pump();

      final app = tester.widget<integrated.GestorHerramientasApp>(
        find.byType(integrated.GestorHerramientasApp),
      );
      expect(app.testBypassSecurity, isFalse);
      final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(material.home, isA<integrated.ToolsHomePage>());
      expect(find.byType(AppSecurityGate), findsOneWidget);
      expect(material.localizationsDelegates!.length, 4);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
