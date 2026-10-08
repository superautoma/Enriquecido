import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
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

class NetworkHttpOverrides extends HttpOverrides {}

class AuthHttp extends AiHttp {
  Map<String, String> authorization = {};
  bool grantUsage = true;
  Map<String, String>? exchanged;
  @override
  Future<Map<String, dynamic>> json(Uri uri, {String method = 'GET',
    Map<String, String> headers = const {}, String? body}) async {
    if (uri.path.endsWith('/openid-configuration')) return {
      'issuer': chatGptIssuer, 'jwks_uri': '$chatGptIssuer/.well-known/jwks.json'};
    if (uri.path.endsWith('/jwks.json')) return {'keys': []};
    exchanged = Uri.splitQueryString(body!);
    final s = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return {'access_token': 'new-local-test-token', 'refresh_token': 'new-local-test-refresh',
      'token_type': 'Bearer', 'expires_in': 3600,
      if (grantUsage) 'scope': 'openid email profile offline_access resource.invoke chatgpt.tokens.use.direct',
      'id_token': fakeIdToken({'iss': chatGptIssuer, 'sub': 'local-subject',
        'aud': exchanged!['client_id'], 'nonce': authorization['nonce'], 'iat': s, 'exp': s + 3600})};
  }
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
    await photo.writeAsBytes(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP8//8/AwMDEwMDAwMDAwAkBgMB/DXemwAAAABJRU5ErkJggg=='));
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
    await ToolsDatabase.instance.database;
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

  test('Photo drafts accept one complete JSON object in Markdown and retain invalid replies for review', () {
    final pliers = {...draftData(), 'name': 'Alicate de corte diagonal', 'type': 'Manual',
      'description': 'Alicate de corte con mangos rojos y amarillos.',
      'brand': '', 'model': '', 'serialNumber': '', 'voltage': '', 'labelText': '1000V'};
    Map<String, dynamic> response(String text) => {'status': 'completed', 'output': [
      {'type': 'message', 'content': [{'type': 'output_text', 'text': text}]}]};
    final json = jsonEncode(pliers);
    for (final text in [json, '\uFEFF$json', '```json\n$json\n```',
      'Esta es la propuesta:\n```json\n$json\n```\nRevisa los datos antes de guardar.']) {
      final draft = aiDraftFromResponse(response(text), ['Manual']);
      expect(draft.name, 'Alicate de corte diagonal'); expect(draft.type, 'Manual');
      expect(draft.serialNumber, isEmpty); expect(draft.voltage, isEmpty);
    }
    for (final text in [json.substring(0,json.length-1), '$json\n$json', '[$json]',
      '[$json] no es una ficha', jsonEncode({...pliers, 'quantity': 10}),
      jsonEncode({...pliers}..remove('identified')), 'Es un alicate de corte diagonal.']) {
      expect(() => aiDraftFromResponse(response(text), ['Manual']), throwsA(isA<AiPhotoException>()
        .having((e) => e.code, 'code', 'format').having((e) => e.responseText, 'reply', text)));
    }
    expect(() => aiDraftFromResponse({'status': 'completed', 'output': []}, ['Manual']),
      throwsA(isA<AiPhotoException>().having((e) => e.responseText, 'reply', isNull)));
  });

  test('Stream text is reconstructed only after completion, including done messages and refusals', () async {
    final json = jsonEncode(draftData());
    final chunks = [json.substring(0,20), json.substring(20,73), json.substring(73)];
    final deltas = [for (final part in chunks)
      <String, dynamic>{'type': 'response.output_text.delta', 'output_index': 1, 'content_index': 0, 'delta': part}];
    final done = <String, dynamic>{'type': 'response.completed', 'response': {'status': 'completed', 'output': []}};
    final result = await aiCompletedResponse(Stream.fromIterable([...deltas, done]));
    expect(aiDraftFromResponse(result, ['Herramienta eléctrica']).serialNumber, '000123');
    final snapshots = await aiCompletedResponse(Stream.fromIterable([
      {'type': 'response.output_text.delta', 'output_index': 0, 'delta': 'partial'},
      {'type': 'response.output_text.done', 'output_index': 0, 'text': json}, done]));
    expect(aiResponseText(snapshots), json);
    final message = await aiCompletedResponse(Stream.fromIterable([
      {'type': 'response.output_item.done', 'output_index': 1, 'item': (completedPhoto()['output'] as List).single}, done]));
    expect(aiResponseText(message), json);
    final channels = await aiCompletedResponse(Stream.fromIterable([
      {'type': 'response.output_item.added', 'output_index': 0, 'item': {'type': 'message', 'channel': 'commentary'}},
      {'type': 'response.output_text.delta', 'output_index': 0, 'delta': 'Voy a revisar la foto.'},
      ...deltas, done]));
    expect(aiResponseText(channels), json);
    final authoritative = await aiCompletedResponse(Stream.fromIterable([
      ...deltas, {'type': 'response.completed', 'response': completedPhoto()}]));
    expect(aiResponseText(authoritative), json);
    for (final ending in <Map<String,dynamic>>[
      {'type': 'response.failed', 'response': {'error': {'code': 'subscription_sharing_usage_limit_exceeded'}}},
      {'type': 'response.incomplete', 'response': {'status': 'incomplete'}},
    ]) {
      await expectLater(aiCompletedResponse(Stream.fromIterable([...deltas, ending])), throwsA(isA<AiPhotoException>()));
    }
    await expectLater(aiCompletedResponse(Stream.fromIterable(deltas)),
      throwsA(isA<AiPhotoException>().having((e) => e.code, 'code', 'incomplete')));
    for (final refusal in [
      <String, dynamic>{'type': 'response.refusal.done', 'refusal': 'No'},
      <String, dynamic>{'type': 'response.output_item.done', 'output_index': 2,
        'item': {'type': 'message', 'content': [{'type': 'refusal', 'refusal': 'No'}]}}
    ]) {
      await expectLater(aiCompletedResponse(Stream.fromIterable([...deltas, refusal, done])),
        throwsA(isA<AiPhotoException>().having((e) => e.code, 'code', 'photo')));
    }
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
      request.response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.write('data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': jsonEncode(draftData())})}\n\n');
      if (request.uri.path == '/completed') request.response.write('data: ${jsonEncode({'type': 'response.completed', 'response': completedPhoto()})}\n\n');
      if (request.uri.path == '/stream-only') request.response.write('data: ${jsonEncode({'type': 'response.completed', 'response': {'status': 'completed', 'output': []}})}\n\n');
      if (request.uri.path == '/limit') request.response.write('data: ${jsonEncode({'type': 'response.failed', 'response': {'error': {'code': 'subscription_sharing_usage_limit_exceeded'}}})}\n\n');
      await request.response.close();
    });
    final http = AiHttp(clientFactory: () => HttpOverrides.runWithHttpOverrides(
      HttpClient.new, NetworkHttpOverrides()));
    try {
      final root = 'http://127.0.0.1:${server.port}';
      final result = await http.response(Uri.parse('$root/completed'), 'local-test-token', {'stream': true, 'store': false});
      expect(result['status'], 'completed');
      final streamed = await http.response(Uri.parse('$root/stream-only'), 'local-test-token', {});
      expect(aiDraftFromResponse(streamed, ['Herramienta eléctrica']).name, 'Taladro');
      await expectLater(http.response(Uri.parse('$root/interrupted'), 'local-test-token', {}),
        throwsA(isA<AiPhotoException>().having((e) => e.code, 'code', 'incomplete')));
      await expectLater(http.response(Uri.parse('$root/limit'), 'local-test-token', {}),
        throwsA(isA<AiPhotoException>().having((e) => e.code, 'code', 'limit')));
      expect(requests, hasLength(4));
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

  test('Browser authorization binds the loopback callback, issued client and PKCE before enabling use', () async {
    final http = AuthHttp();
    final connection = ChatGptConnection(http: http);
    var checkedSignature = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(toolAiChannel, (call) async {
      if (call.method == 'read') return savedCredentials;
      if (call.method == 'write') { savedCredentials = (call.arguments as Map)['value'] as String; return null; }
      if (call.method == 'verifySignature') { checkedSignature = true; return true; }
      if (call.method == 'openBrowser') {
        final url = Uri.parse((call.arguments as Map)['url'] as String);
        expect(url.origin, chatGptIssuer);
        http.authorization = url.queryParameters;
        expect(http.authorization['client_id'], 'dynamic_agent_client');
        expect(http.authorization['resource'], chatGptResource);
        expect(http.authorization['code_challenge_method'], 'S256');
        final callback = Uri.parse(http.authorization['redirect_uri']!).replace(queryParameters: {
          'code': 'local-test-code', 'state': http.authorization['state']!, 'client_id': 'oaiapp_new_test'});
        final client = HttpOverrides.runWithHttpOverrides(HttpClient.new, NetworkHttpOverrides());
        try { final response = await (await client.getUrl(callback)).close(); expect(response.statusCode, 200); await response.drain<void>(); }
        finally { client.close(force: true); }
      }
      return null;
    });
    await connection.signIn(addAccount: true);
    expect(checkedSignature, true); expect(connection.active!.clientId, 'oaiapp_new_test');
    expect(connection.active!.sharing, true); expect(connection.profiles, hasLength(2));
    expect(http.exchanged!['client_id'], 'oaiapp_new_test');
    expect(http.exchanged!['redirect_uri'], http.authorization['redirect_uri']);
    expect(http.exchanged!['code_verifier'], isNotEmpty);
    expect(base64UrlEncode(crypto.sha256.convert(utf8.encode(http.exchanged!['code_verifier']!)).bytes).replaceAll('=', ''),
      http.authorization['code_challenge']);
    final original = connection.profiles.first;
    expect(original.clientId, 'oaiapp_local_test'); expect(original.accessToken, 'local-test-token');
    // Reauthorization without explicit usage scopes must not inherit the old grant.
    http.grantUsage = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(toolAiChannel, (call) async {
      if (call.method == 'read') return savedCredentials;
      if (call.method == 'write') { savedCredentials = (call.arguments as Map)['value'] as String; return null; }
      if (call.method == 'verifySignature') return true;
      if (call.method == 'openBrowser') {
        final url = Uri.parse((call.arguments as Map)['url'] as String);
        http.authorization = url.queryParameters;
        expect(http.authorization['client_id'], 'oaiapp_new_test');
        expect(http.authorization.containsKey('agent_name_hint'), false);
        final callback = Uri.parse(http.authorization['redirect_uri']!).replace(queryParameters: {
          'code': 'local-test-code', 'state': http.authorization['state']!});
        final client = HttpOverrides.runWithHttpOverrides(HttpClient.new, NetworkHttpOverrides());
        try { await (await (await client.getUrl(callback)).close()).drain<void>(); }
        finally { client.close(force: true); }
      }
      return null;
    });
    await connection.signIn();
    expect(connection.active!.connected, true); expect(connection.active!.sharing, false);
    await expectLater(connection.authorizedProfile(), throwsA(isA<AiPhotoException>().having((e) => e.code, 'code', 'permission')));
  });

  testWidgets('Photo analysis remains a draft until review; failed/cancelled requests do not create articles', (tester) async {
    final connection = ChatGptConnection(http: ModelsHttp());
    var analyses = 0;
    AiToolDraft? selected;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { selected = await Navigator.push<AiToolDraft>(context, MaterialPageRoute(builder: (_) => AiPhotoPage(
        connection: connection, typeOptions: defaultFieldOptions('type'),
        picker: (_) async => XFile(photo.path), analyzer: (_, types, _) async {
          analyses++; return AiToolDraft.fromMap(draftData(), types);
        }))); }, child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir')); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai_gallery'))); await tester.pumpAndSettle();
    expect(analyses, 0); expect(await tester.runAsync(() => ToolsDatabase.instance.loadTools()), isEmpty);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('ai_analyze')), 250);
    await tester.tap(find.byKey(const ValueKey('ai_analyze'))); await tester.pumpAndSettle();
    expect(analyses, 1); expect(await tester.runAsync(() => ToolsDatabase.instance.loadTools()), isEmpty);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('ai_review')), 250);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('ai_review')));
      for (var i = 0; i < 50 && selected == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(selected!.name, 'Taladro');
    expect(await tester.runAsync(() => File(selected!.photoPath!).exists()), true);
    expect(await tester.runAsync(() => ToolsDatabase.instance.loadTools()), isEmpty); expect(tester.takeException(), isNull);
  });

  testWidgets('Cancellation ignores a late completed response and retains the photo', (tester) async {
    final result = Completer<AiToolDraft>();
    await tester.pumpWidget(MaterialApp(home: AiPhotoPage(connection: ChatGptConnection(http: ModelsHttp()), typeOptions: defaultFieldOptions('type'),
      picker: (_) async => XFile(photo.path), analyzer: (_, _, _) => result.future)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai_gallery'))); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('ai_analyze')), 250);
    await tester.tap(find.byKey(const ValueKey('ai_analyze'))); await tester.pump();
    await tester.scrollUntilVisible(find.text('Cancelar análisis'), 150);
    await tester.tap(find.text('Cancelar análisis')); await tester.pumpAndSettle();
    result.complete(AiToolDraft.fromMap(draftData(), ['Herramienta eléctrica'])); await tester.pumpAndSettle();
    expect(find.text('Propuesta de ficha'), findsNothing);
    expect(find.text('Análisis cancelado. Puedes volver a intentarlo.'), findsOneWidget);
    expect(await tester.runAsync(() => ToolsDatabase.instance.loadTools()), isEmpty);
  });

  testWidgets('A format failure shows the completed reply without creating an article; another photo clears it', (tester) async {
    const reply = 'Es un alicate de corte diagonal.';
    await tester.pumpWidget(MaterialApp(home: AiPhotoPage(connection: ChatGptConnection(http: ModelsHttp()),
      typeOptions: defaultFieldOptions('type'), picker: (_) async => XFile(photo.path),
      analyzer: (_, _, _) async => throw const AiPhotoException('No se pudo preparar la ficha.', code: 'format', responseText: reply))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai_gallery'))); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('ai_analyze')), 250);
    await tester.tap(find.byKey(const ValueKey('ai_analyze'))); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('ai_response')), 200);
    await tester.tap(find.text('Ver respuesta de ChatGPT')); await tester.pumpAndSettle();
    expect(find.text(reply), findsOneWidget); expect(find.text('Propuesta de ficha'), findsNothing);
    expect(await tester.runAsync(() => ToolsDatabase.instance.loadTools()), isEmpty);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('ai_gallery')), -250);
    await tester.tap(find.byKey(const ValueKey('ai_gallery'))); await tester.pumpAndSettle();
    expect(find.text('Ver respuesta de ChatGPT'), findsNothing); expect(find.text(reply), findsNothing);
    expect(tester.takeException(), isNull);
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
