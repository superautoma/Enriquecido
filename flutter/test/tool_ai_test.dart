import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/main_quill_integrated_test.dart';

Map<String, dynamic> draftData() => {'identified': true, 'name': 'Taladro',
  'description': 'Taladro de batería visible en la fotografía.', 'type': 'Herramienta eléctrica',
  'brand': 'Bosch', 'model': 'GSB 18V', 'serialNumber': '000123', 'voltage': '18 V',
  'labelText': 'Bosch\nGSB 18V\nS/N 000123\n18 V', 'warnings': <String>[]};

Map<String, dynamic> completedPhoto() => {'status': 'completed', 'output': [
  {'type': 'message', 'content': [{'type': 'output_text', 'text': jsonEncode(draftData())}]}]};

String fakeIdToken(Map<String, dynamic> claims) => '${base64UrlEncode(utf8.encode('{"alg":"RS256"}'))}.'
  '${base64UrlEncode(utf8.encode(jsonEncode(claims)))}.not-a-real-signature';

class ModelsHttp extends AiHttp {
  @override
  Future<Map<String, dynamic>> json(Uri uri, {String method = 'GET',
    Map<String, String> headers = const {}, String? body}) async => {'models': [
      {'slug': 'local-test-model', 'display_name': 'Modelo de prueba', 'visibility': 'list'},
      {'slug': 'hidden', 'display_name': 'Oculto', 'visibility': 'hidden'}]};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File photo;
  late String? savedCredentials;
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tool_ai_');
    await databaseFactory.setDatabasesPath('${directory.path}/db');
    photo = File('${directory.path}/photo.png');
    await photo.writeAsBytes(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='));
    savedCredentials = jsonEncode({'version': 1, 'host_id': 'urn:uuid:00000000-0000-4000-8000-000000000001',
      'active': 'oaiapp_local_test', 'profiles': [{'client_id': 'oaiapp_local_test', 'subject': 'local-subject',
        'email': 'cuenta@example.com', 'access_token': 'local-test-token',
        'scopes': ['chatgpt.tokens.use.direct', 'resource.invoke'],
        'expires_at': DateTime.now().millisecondsSinceEpoch + 3600000, 'model': 'local-test-model'}]});
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => directory.path);
    messenger.setMockMethodCallHandler(toolAiChannel, (call) async {
      if (call.method == 'read') return savedCredentials;
      if (call.method == 'write') savedCredentials = (call.arguments as Map)['value'] as String;
      return null;
    });
  });
  tearDown(() async {
    await ToolsDatabase.instance.closeForBackup();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    messenger.setMockMethodCallHandler(toolAiChannel, null);
    await directory.delete(recursive: true);
  });

  test('Photo request matches public ChatGPT-plan contract and limits requested fields', () async {
    final body = aiPhotoRequest('local-test-model', await photo.readAsBytes(), 'image/png', ['Herramienta eléctrica']);
    expect(body['store'], false); expect(body['stream'], true);
    for (final key in ['max_output_tokens', 'temperature', 'conversation', 'previous_response_id', 'metadata']) {
      expect(body.containsKey(key), false);
    }
    expect((body['input'] as List).single['role'], 'user');
    final schema = body['text']['format']['schema'];
    expect(schema['additionalProperties'], false);
    expect(schema['required'].toSet(), schema['properties'].keys.toSet());
    expect(schema['properties'].containsKey('quantity'), false);
    expect(schema['properties'].containsKey('purchasePrice'), false);
    expect(aiImageMime(await photo.readAsBytes()), 'image/png');
    expect(() => aiImageMime(Uint8List.fromList([1, 2, 3])), throwsA(isA<AiPhotoException>()));
  });

  test('Legible identifiers retain zeros; unsupported label claims stay blank', () {
    final data = draftData();
    final draft = AiToolDraft.fromMap(data, ['Herramienta eléctrica']);
    expect(draft.serialNumber, '000123'); expect(draft.model, 'GSB 18V');
    expect(draft.photoPath, isNull);
    final unknown = AiToolDraft.fromMap({...data, 'model': 'Made up', 'serialNumber': '99999'}, ['Herramienta eléctrica']);
    expect(unknown.model, isEmpty); expect(unknown.serialNumber, isEmpty); expect(unknown.warnings, hasLength(2));
    expect(() => AiToolDraft.fromMap({...data, 'identified': false}, ['Herramienta eléctrica']), throwsA(isA<AiPhotoException>()));
    expect(() => AiToolDraft.fromMap({...data, 'type': 'Unknown'}, ['Herramienta eléctrica']), throwsA(isA<AiPhotoException>()));
    expect(() => AiToolDraft.fromMap({...data, 'serialNumber': 123}, ['Herramienta eléctrica']), throwsA(isA<AiPhotoException>()));
    expect(() => aiDraftFromResponse({'status': 'incomplete', 'output': []}, []), throwsA(isA<AiPhotoException>()));
    expect(() => aiDraftFromResponse({'status': 'completed', 'output': [
      {'type': 'message', 'content': [{'type': 'refusal', 'refusal': 'No'}]}]}, []), throwsA(isA<AiPhotoException>()));
  });

  test('SSE handles UTF8/chunk boundaries and never accepts a partial stream', () async {
    final data = utf8.encode('event: response.completed\r\ndata: ${jsonEncode({'type': 'response.completed', 'response': completedPhoto()})}\r\n\r\n');
    final events = await aiSseEvents(Stream.fromIterable(data.map((byte) => [byte]))).toList();
    expect(events.single['type'], 'response.completed');
    expect(aiDraftFromResponse(events.single['response'] as Map<String, dynamic>, ['Herramienta eléctrica']).brand, 'Bosch');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map<String, dynamic>>[];
    final subscription = server.listen((request) async {
      requests.add(jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>);
      expect(request.headers.value(HttpHeaders.authorizationHeader), 'Bearer local-test-token');
      request.response.headers.contentType = ContentType('text', 'event-stream');
      request.response.write('data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': jsonEncode(draftData())})}\n\n');
      if (request.uri.path == '/completed') request.response.write('data: ${jsonEncode({'type': 'response.completed', 'response': completedPhoto()})}\n\n');
      if (request.uri.path == '/limit') request.response.write('data: ${jsonEncode({'type': 'response.failed', 'response': {'error': {'code': 'subscription_sharing_usage_limit_exceeded'}}})}\n\n');
      await request.response.close();
    });
    final http = AiHttp();
    try {
      final root = 'http://127.0.0.1:${server.port}';
      final result = await http.response(Uri.parse('$root/completed'), 'local-test-token', {'stream': true, 'store': false});
      expect(result['status'], 'completed');
      await expectLater(http.response(Uri.parse('$root/interrupted'), 'local-test-token', {}),
        throwsA(isA<AiPhotoException>().having((e) => e.code, 'code', 'incomplete')));
      await expectLater(http.response(Uri.parse('$root/limit'), 'local-test-token', {}),
        throwsA(isA<AiPhotoException>().having((e) => e.code, 'code', 'limit')));
      expect(requests, hasLength(3));
    } finally { http.cancel(); await subscription.cancel(); await server.close(force: true); }
  });

  test('OIDC claims reject another account, audience, nonce and expired identity', () {
    final now = DateTime.utc(2026, 10, 8);
    final s = now.millisecondsSinceEpoch ~/ 1000;
    final claims = {'iss': chatGptIssuer, 'sub': 'subject', 'aud': 'oaiapp_local_test', 'nonce': 'nonce', 'iat': s, 'exp': s + 3600};
    expect(aiIdClaims(fakeIdToken(claims), 'oaiapp_local_test', nonce: 'nonce', subject: 'subject', now: now)['sub'], 'subject');
    for (final change in [{'iss': 'https://example.com'}, {'aud': 'other'}, {'sub': 'other'}, {'nonce': 'other'}, {'exp': s}, {'iat': s + 20}, {'nbf': s + 20}]) {
      expect(() => aiIdClaims(fakeIdToken({...claims, ...change}), 'oaiapp_local_test', nonce: 'nonce', subject: 'subject', now: now), throwsA(isA<AiPhotoException>()));
    }
  });

  test('Each installation keeps its host ID and models follow the active account', () async {
    final connection = ChatGptConnection(http: ModelsHttp());
    await connection.initialize(); final host = connection.hostId;
    expect(connection.active!.sharing, true);
    expect((await connection.models()).single.slug, 'local-test-model');
    await connection.selectModel('local-test-model');
    final reopened = ChatGptConnection(http: ModelsHttp()); await reopened.initialize();
    expect(reopened.hostId, host); expect(reopened.active!.clientId, 'oaiapp_local_test');
    final revoked = await reopened.signOut(); expect(revoked, true);
    expect(reopened.active!.connected, false); expect(reopened.active!.clientId, 'oaiapp_local_test');
    expect(savedCredentials, isNot(contains('local-test-token')));
    expect(await ToolsDatabase.instance.loadTools(), isEmpty);
  });

  testWidgets('Photo analysis remains a draft until review; failed/cancelled requests do not create articles', (tester) async {
    final connection = ChatGptConnection(http: ModelsHttp());
    var analyses = 0;
    AiToolDraft? selected;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { selected = await Navigator.push<AiToolDraft>(context, MaterialPageRoute(builder: (_) => AiPhotoPage(
        connection: connection, picker: (_) async => XFile(photo.path), analyzer: (_, types, _) async {
          analyses++; return AiToolDraft.fromMap(draftData(), types);
        }))); }, child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir')); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai_gallery'))); await tester.pumpAndSettle();
    expect(analyses, 0); expect(await ToolsDatabase.instance.loadTools(), isEmpty);
    await tester.ensureVisible(find.byKey(const ValueKey('ai_analyze')));
    await tester.tap(find.byKey(const ValueKey('ai_analyze'))); await tester.pumpAndSettle();
    expect(analyses, 1); expect(await ToolsDatabase.instance.loadTools(), isEmpty);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('ai_review')), 250);
    await tester.tap(find.byKey(const ValueKey('ai_review'))); await tester.pumpAndSettle();
    expect(selected!.name, 'Taladro'); expect(await File(selected!.photoPath!).exists(), true);
    expect(await ToolsDatabase.instance.loadTools(), isEmpty); expect(tester.takeException(), isNull);
  });

  testWidgets('Cancellation ignores a late completed response and retains the photo', (tester) async {
    final result = Completer<AiToolDraft>();
    await tester.pumpWidget(MaterialApp(home: AiPhotoPage(connection: ChatGptConnection(http: ModelsHttp()),
      picker: (_) async => XFile(photo.path), analyzer: (_, _, _) => result.future)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai_gallery'))); await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('ai_analyze')));
    await tester.tap(find.byKey(const ValueKey('ai_analyze'))); await tester.pump();
    await tester.ensureVisible(find.text('Cancelar análisis'));
    await tester.tap(find.text('Cancelar análisis')); await tester.pumpAndSettle();
    result.complete(AiToolDraft.fromMap(draftData(), ['Herramienta eléctrica'])); await tester.pumpAndSettle();
    expect(find.text('Propuesta de ficha'), findsNothing);
    expect(find.text('Análisis cancelado. Puedes volver a intentarlo.'), findsOneWidget);
    expect(await ToolsDatabase.instance.loadTools(), isEmpty);
  });

  testWidgets('ChatGPT settings fit narrow screens and large text without exposing credentials', (tester) async {
    tester.view.physicalSize = const Size(320, 640); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: ChatGptSettingsPage(connection: ChatGptConnection(http: ModelsHttp())))));
    await tester.pumpAndSettle();
    expect(find.text('local-test-token'), findsNothing);
    await tester.scrollUntilVisible(find.text('Gestionar uso'), 250);
    expect(tester.takeException(), isNull);
  });
}
