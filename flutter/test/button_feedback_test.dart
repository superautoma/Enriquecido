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
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('button_feedback_');
    await databaseFactory.setDatabasesPath(directory.path);
    calls.clear();
    controller.value = const ButtonFeedbackPreferences();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(buttonFeedbackChannel, (call) async {
        expect(call.method, 'tap');
        calls.add(Map<Object?, Object?>.from(call.arguments as Map));
        return null;
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
    await tester.ensureVisible(testButton);
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
}
