import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/main_quill_integrated_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('startup_loading_');
    await databaseFactory.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    await ToolsDatabase.instance.closeForBackup();
    await directory.delete(recursive: true);
  });

  Future<void> finishDatabaseLoad(WidgetTester tester) async {
    // Real SQLite I/O must complete outside the widget test's fake clock.
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
    }
    fail('The database load did not finish');
  }

  testWidgets('Startup loader disappears when tools are ready', (tester) async {
    await tester.pumpWidget(const GestorHerramientasApp());
    expect(find.text('Cargando…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Buscar herramientas'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    await finishDatabaseLoad(tester);
    await tester.pumpAndSettle();
    expect(find.text('Cargando…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Destornillador aislado'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Failed startup offers a retry and then opens the tools',
      (tester) async {
    final invalidPath = File('${directory.path}/not_a_directory');
    await tester.runAsync(() async {
      await invalidPath.writeAsString('occupied');
      await databaseFactory.setDatabasesPath(invalidPath.path);
    });
    await tester.pumpWidget(const GestorHerramientasApp());
    await finishDatabaseLoad(tester);
    await tester.pumpAndSettle();
    expect(find.text('No se pudieron cargar las herramientas.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await databaseFactory.setDatabasesPath(directory.path);
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(find.text('Cargando…'), findsOneWidget);
    await finishDatabaseLoad(tester);
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsNothing);
    expect(find.text('Destornillador aislado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Startup status fits a small screen and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final hasError in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: StartupStatusPage(hasError: hasError, onRetry: () {}),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
