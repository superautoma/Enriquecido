import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/main_quill_integrated_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controller = ButtonFeedbackController.instance;
  final calls = <Map<Object?, Object?>>[];
  final diagnosticCalls = <String>[];
  Map<Object?, Object?> deviceStatus = {};
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('button_feedback_');
    await databaseFactory.setDatabasesPath(directory.path);
    calls.clear();
    diagnosticCalls.clear();
    deviceStatus = {'hasVibrator': true, 'permissionGranted': true,
      'touchFeedbackEnabled': true, 'appVersion': 95};
    controller.value = const ButtonFeedbackPreferences();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(buttonFeedbackChannel, (call) async {
        if (call.method == 'tap') {
          calls.add(Map<Object?, Object?>.from(call.arguments as Map));
          return null;
        }
        diagnosticCalls.add(call.method);
        if (call.method == 'vibrationStatus') return deviceStatus;
        if (call.method == 'testVibration') return {...deviceStatus, 'status': 'requested', 'durationMs': 1000};
        if (call.method == 'openVibrationSettings') return true;
        fail('Unexpected channel method: ${call.method}');
      });
  });
  tearDown(() async {
    await ToolsDatabase.instance.closeForBackup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(buttonFeedbackChannel, null);
    await directory.delete(recursive: true);
  });

  Future<void> flushEffects() => Future<void>.delayed(Duration.zero);

  test('The two effects can be enabled and disabled independently', () async {
    for (final sound in [false, true]) {
      for (final vibration in [false, true]) {
        calls.clear();
        controller.value = ButtonFeedbackPreferences(sound: sound, vibration: vibration);
        var actions = 0;
        withButtonFeedback(() => actions++)!();
        expect(actions, 1, reason: 'The inventory action must run immediately');
        await flushEffects();
        expect(calls, sound || vibration ? [{'sound': sound, 'vibration': vibration}] : isEmpty);
      }
    }
  });

  test('Disabled callbacks stay disabled and nested callbacks respond once', () async {
    expect(withButtonFeedback(null), isNull);
    expect(withControlFeedback<bool>(null), isNull);
    var actions = 0;
    withButtonFeedback(withButtonFeedback(() => actions++))!();
    await flushEffects();
    expect(actions, 1);
    expect(calls, hasLength(1));
  });

  test('Preferences survive reopening SQLite without changing other settings', () async {
    final database = await ToolsDatabase.instance.database;
    await database.insert('management_settings', {'key': 'unrelated', 'value': 'preserved'});
    await controller.update(const ButtonFeedbackPreferences(sound: false, vibration: true));
    await ToolsDatabase.instance.closeForBackup();
    final reopened = ButtonFeedbackController();
    await reopened.load();
    expect(reopened.value.sound, isFalse);
    expect(reopened.value.vibration, isTrue);
    final rows = await (await ToolsDatabase.instance.database).query('management_settings',
      where: 'key=?', whereArgs: ['unrelated']);
    expect(rows.single['value'], 'preserved');
    reopened.dispose();
  });

  test('Absent and malformed saved settings recover usable defaults', () async {
    await controller.load();
    expect(controller.value.sound, isTrue);
    expect(controller.value.vibration, isTrue);
    await (await ToolsDatabase.instance.database).insert('management_settings',
      {'key': buttonFeedbackSettingsKey, 'value': '{broken'});
    await controller.load();
    expect(controller.value.sound, isTrue);
    expect(controller.value.vibration, isTrue);
  });

  test('Diagnostics explain missing motors, system blocking and service failures', () async {
    for (final scenario in [
      ({'hasVibrator': false}, 'no tiene motor'),
      ({'hasVibrator': true, 'permissionGranted': false}, 'no permite vibrar'),
      ({'hasVibrator': true, 'permissionGranted': true, 'touchFeedbackEnabled': false}, 'desactivada'),
      ({'hasVibrator': true, 'permissionGranted': true, 'status': 'unavailable'}, 'No se pudo acceder'),
    ]) {
      deviceStatus = scenario.$1;
      final status = await controller.checkVibration();
      expect(status.message, contains(scenario.$2));
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(buttonFeedbackChannel, (_) async => throw PlatformException(code: 'unavailable'));
    expect((await controller.testVibration()).result, 'unavailable');
    expect(await controller.openVibrationSettings(), isFalse);
  });

  testWidgets('A cancelled button press produces no action or effect', (tester) async {
    var actions = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child:
      FilledButton(style: const ButtonStyle(enableFeedback: false),
        onPressed: withButtonFeedback(() => actions++), child: const Text('Prueba'))))));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Prueba')));
    await gesture.moveBy(const Offset(0, 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(actions, 0);
    expect(calls, isEmpty);
    await tester.tap(find.text('Prueba'));
    await tester.pumpAndSettle();
    expect(actions, 1);
    expect(calls, hasLength(1));
  });

  testWidgets('Settings fit a small screen and large text, and test both effects', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)), child: const ButtonFeedbackPage())));
    expect(tester.takeException(), isNull);
    final testButton = find.byKey(const ValueKey('test_button_feedback'));
    await tester.scrollUntilVisible(testButton, 200);
    await tester.pumpAndSettle();
    await tester.tap(testButton);
    await tester.pumpAndSettle();
    expect(calls.single, {'sound': true, 'vibration': true});
    controller.value = const ButtonFeedbackPreferences(sound: false, vibration: true);
    calls.clear();
    await tester.pump();
    await tester.tap(testButton);
    await tester.pumpAndSettle();
    expect(calls.single, {'sound': false, 'vibration': true});
    expect(tester.takeException(), isNull);
  });

  testWidgets('The one-second test is independent from button feedback preferences', (tester) async {
    controller.value = const ButtonFeedbackPreferences(sound: false, vibration: false);
    await tester.pumpWidget(const MaterialApp(home: ButtonFeedbackPage()));
    await tester.pumpAndSettle();
    final testButton = find.byKey(const ValueKey('test_vibration'));
    await tester.scrollUntilVisible(testButton, 150);
    await tester.pumpAndSettle();
    await tester.tap(testButton);
    await tester.pumpAndSettle();
    expect(diagnosticCalls.where((method) => method == 'testVibration'), hasLength(1));
    expect(calls, isEmpty, reason: 'The long test must not also trigger a short pulse or a click');
    expect(find.textContaining('Prueba de un segundo enviada'), findsOneWidget);
    expect(controller.value.vibration, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('System-blocked vibration exposes settings and refresh without claiming success', (tester) async {
    deviceStatus = {'hasVibrator': true, 'permissionGranted': true, 'touchFeedbackEnabled': false};
    await tester.pumpWidget(const MaterialApp(home: ButtonFeedbackPage()));
    await tester.pumpAndSettle();
    final settings = find.byKey(const ValueKey('vibration_system_settings'));
    await tester.scrollUntilVisible(settings, 150);
    await tester.pumpAndSettle();
    expect(find.textContaining('desactivada la respuesta táctil'), findsOneWidget);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(diagnosticCalls, contains('openVibrationSettings'));
    deviceStatus = {'hasVibrator': true, 'permissionGranted': true, 'touchFeedbackEnabled': true};
    await tester.tap(find.byKey(const ValueKey('refresh_vibration_status')));
    await tester.pumpAndSettle();
    expect(find.text('Motor de vibración detectado.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
