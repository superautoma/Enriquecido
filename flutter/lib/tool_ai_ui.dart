part of 'main_quill_integrated_test.dart';

class ChatGptSettingsPage extends StatefulWidget {
  const ChatGptSettingsPage({super.key, this.connection});
  final ChatGptConnection? connection;
  @override
  State<ChatGptSettingsPage> createState() => _ChatGptSettingsPageState();
}

class _ChatGptSettingsPageState extends State<ChatGptSettingsPage> {
  ChatGptConnection get connection => widget.connection ?? ChatGptConnection.instance;
  bool _loading = true, _busy = false;
  String? _error;
  List<ChatGptModel> _models = [];

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    try {
      await connection.initialize();
      final models = connection.active?.sharing == true ? await connection.models() : <ChatGptModel>[];
      if (!mounted) return;
      final saved = connection.active?.model ?? '';
      if (models.isNotEmpty && !models.any((m) => m.slug == saved)) {
        await connection.selectModel(models.first.slug);
      }
      if (mounted) setState(() { _models = models; _error = null; });
    } catch (error) {
      if (mounted) setState(() => _error = aiErrorText(error));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _connect({bool add = false}) async {
    setState(() { _busy = true; _error = null; });
    try {
      await connection.signIn(addAccount: add);
      if (!mounted) return;
      if (connection.active?.sharing == true && connection.active?.values['welcome_shown'] != true) {
        await showDialog<void>(context: context, builder: (context) => AlertDialog(
          title: const Text('Usando tu plan de ChatGPT'),
          content: const Text('Los análisis de fotos usarán el uso disponible de tu plan o tus créditos de ChatGPT. Puedes consultar y ajustar los límites en Gestionar uso.'),
          actions: [TextButton(onPressed: withButtonFeedback(() => Navigator.pop(context)), child: const Text('Entendido'))]));
        await connection.markWelcomeShown();
      }
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = aiErrorText(error));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _logout() async {
    setState(() { _busy = true; _error = null; });
    try {
      final revoked = await connection.signOut();
      if (mounted) setState(() {
        _models = [];
        if (!revoked) _error = 'La sesión se cerró en este móvil, pero no se confirmó la desconexión en el servicio. Puedes desconectar la aplicación desde Gestionar uso.';
      });
    } catch (error) { if (mounted) setState(() => _error = aiErrorText(error)); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _usage() async {
    try { await connection.openUsage(); }
    catch (error) { if (mounted) setState(() => _error = aiErrorText(error)); }
  }

  @override
  void dispose() { if (_busy) connection.cancelSignIn(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final profile = connection.active;
    return Scaffold(appBar: AppBar(title: const Text('Conexión con ChatGPT', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(child: _loading ? const Center(child: CircularProgressIndicator()) :
        ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Usa ChatGPT para preparar fichas desde fotografías.', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 8),
          const Text('Conecta una cuenta con un plan compatible. El inicio de sesión y la autorización se realizan en el navegador de OpenAI.'),
          const SizedBox(height: 18),
          if (connection.profiles.isNotEmpty) DropdownButtonFormField<String>(
            key: ValueKey('chatgpt_account_${profile?.clientId}'), initialValue: profile?.clientId,
            isExpanded: true, decoration: const InputDecoration(labelText: 'Cuenta de ChatGPT'),
            items: [for (var i = 0; i < connection.profiles.length; i++)
              DropdownMenuItem(value: connection.profiles[i].clientId,
                child: Text('${connection.profiles[i].email.isEmpty ? 'Conexión' : connection.profiles[i].email} · ${i + 1}',
                  maxLines: 1, overflow: TextOverflow.ellipsis))],
            onChanged: _busy ? null : withControlFeedback((value) async {
              if (value == null) return;
              setState(() { _busy = true; _models = []; });
              try { await connection.select(value); await _refresh(); }
              catch (error) { if (mounted) setState(() => _error = aiErrorText(error)); }
              finally { if (mounted) setState(() => _busy = false); }
            })),
          const SizedBox(height: 12),
          if (profile?.sharing == true) const ListTile(contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle_outline, color: Colors.green),
            title: Text('Usando tu plan de ChatGPT'), subtitle: Text('Cuenta conectada y uso del plan autorizado'))
          else if (profile?.connected == true) const Text('La cuenta está conectada, pero falta autorizar el uso de su plan. Pulsa Continuar con ChatGPT para revisarlo.')
          else const Text('ChatGPT todavía no está conectado.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(key: const ValueKey('chatgpt_connect'),
            onPressed: withButtonFeedback(_busy ? null : () => _connect()),
            icon: const Icon(Icons.login), label: const Text('Continuar con ChatGPT')),
          if (connection.profiles.isNotEmpty) TextButton.icon(
            onPressed: withButtonFeedback(_busy ? null : () => _connect(add: true)),
            icon: const Icon(Icons.person_add_alt_1), label: const Text('Añadir otra cuenta')),
          if (_busy) ...[
            const LinearProgressIndicator(), const SizedBox(height: 8),
            const Text('Completa la conexión en el navegador y vuelve a la aplicación.'),
            TextButton(onPressed: withButtonFeedback(connection.cancelSignIn), child: const Text('Cancelar conexión')),
          ],
          if (_models.isNotEmpty) ...[
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(key: ValueKey('chatgpt_model_${profile?.model}'),
              initialValue: _models.any((m) => m.slug == profile?.model) ? profile?.model : null,
              isExpanded: true, decoration: const InputDecoration(labelText: 'Modelo disponible'),
              items: _models.map((m) => DropdownMenuItem(value: m.slug,
                child: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _busy ? null : withControlFeedback((value) async {
                if (value == null) return;
                try { await connection.selectModel(value); if (mounted) setState(() {}); }
                catch (error) { if (mounted) setState(() => _error = aiErrorText(error)); }
              })),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: withButtonFeedback(_usage),
            icon: const Icon(Icons.open_in_new), label: const Text('Gestionar uso')),
          if (profile?.connected == true) TextButton.icon(
            onPressed: withButtonFeedback(_busy ? null : _logout),
            icon: const Icon(Icons.logout), label: const Text('Cerrar sesión en esta cuenta')),
          TextButton.icon(onPressed: withButtonFeedback(_busy ? null : _refresh),
            icon: const Icon(Icons.refresh), label: const Text('Actualizar conexión')),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, key: const ValueKey('chatgpt_error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ])));
  }
}

class AiPhotoPage extends StatefulWidget {
  const AiPhotoPage({super.key, this.connection, this.picker, this.analyzer, this.typeOptions});
  final ChatGptConnection? connection;
  final Future<XFile?> Function(ImageSource)? picker;
  final Future<AiToolDraft> Function(File, List<String>, AiHttp)? analyzer;
  final List<FieldOption>? typeOptions;
  @override
  State<AiPhotoPage> createState() => _AiPhotoPageState();
}

class _AiPhotoPageState extends State<AiPhotoPage> {
  ChatGptConnection get connection => widget.connection ?? ChatGptConnection.instance;
  XFile? _photo;
  AiToolDraft? _draft;
  AiHttp? _analysisHttp;
  bool _loading = true, _busy = false;
  String? _error;
  String _errorCode = '';
  String? _responseText;
  List<String> _types = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      await connection.initialize();
      final options = widget.typeOptions ?? await ToolsDatabase.instance.loadFieldOptions('type');
      if (mounted) setState(() {
        _types = (options.isEmpty ? defaultFieldOptions('type') : options).map((o) => o.label).toSet().toList();
        _error = null;
      });
    } catch (error) { if (mounted) setState(() => _error = aiErrorText(error)); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _settings() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ChatGptSettingsPage(connection: connection)));
    if (mounted) await _load();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() { _busy = true; _error = null; _errorCode = ''; _responseText = null; });
    try {
      final photo = await (widget.picker?.call(source) ?? ImagePicker().pickImage(
        source: source, imageQuality: 88, maxWidth: 1800, maxHeight: 1800, requestFullMetadata: false));
      if (photo != null && mounted) setState(() { _photo = photo; _draft = null; });
    } catch (_) {
      if (mounted) setState(() => _error = source == ImageSource.camera ?
        'No se pudo abrir la cámara. Revisa el permiso o elige una foto de la galería.' :
        'No se pudo abrir la fotografía. Prueba otra imagen.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<AiToolDraft> _analyze(File photo, List<String> types, AiHttp http) async {
    final profile = await connection.authorizedProfile();
    final models = await connection.models();
    final model = models.where((m) => m.slug == profile.model).firstOrNull;
    if (model == null) throw const AiPhotoException('Elige un modelo disponible en Conexión con ChatGPT.', code: 'permission');
    if (await photo.length() > 5 * 1024 * 1024) throw const AiPhotoException('La foto es demasiado grande. Usa otra imagen de menos de 5 MB.', code: 'photo');
    final bytes = await photo.readAsBytes();
    final mime = aiImageMime(bytes);
    final response = await http.response(Uri.parse('$chatGptResource/responses'), profile.accessToken,
      aiPhotoRequest(model.slug, bytes, mime, types));
    return aiDraftFromResponse(response, types);
  }

  Future<void> _run() async {
    if (_photo == null || _busy) return;
    setState(() { _busy = true; _draft = null; _error = null; _errorCode = ''; _responseText = null; });
    final http = AiHttp(); _analysisHttp = http;
    try {
      final draft = await (widget.analyzer ?? _analyze)(File(_photo!.path), _types, http);
      if (mounted && identical(_analysisHttp, http)) setState(() => _draft = draft);
    } catch (error) {
      if (mounted && identical(_analysisHttp, http)) setState(() {
        _error = aiErrorText(error); _errorCode = error is AiPhotoException ? error.code : '';
        _responseText = error is AiPhotoException ? error.responseText : null;
      });
    } finally {
      http.cancel();
      if (identical(_analysisHttp, http)) {
        _analysisHttp = null; if (mounted) setState(() => _busy = false);
      }
    }
  }

  void _cancel() {
    _analysisHttp?.cancel(); _analysisHttp = null;
    setState(() { _busy = false; _responseText = null; _error = 'Análisis cancelado. Puedes volver a intentarlo.'; });
  }

  Future<void> _review() async {
    final draft = _draft, photo = _photo;
    if (draft == null || photo == null || _busy) return;
    setState(() => _busy = true);
    File? stored;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final directory = Directory(p.join(docs.path, 'tool_images'));
      await directory.create(recursive: true);
      final mime = aiImageMime(await File(photo.path).readAsBytes());
      final extension = mime == 'image/png' ? '.png' : mime == 'image/webp' ? '.webp' : '.jpg';
      stored = await File(photo.path).copy(p.join(directory.path, 'ai_photo_${DateTime.now().microsecondsSinceEpoch}$extension'));
      if (!mounted) { await stored.delete(); return; }
      Navigator.of(context).pop(draft.withPhoto(stored.path));
    } catch (_) {
      if (stored != null && await stored.exists()) await stored.delete();
      if (mounted) setState(() => _error = 'No se pudo conservar la fotografía. Comprueba el espacio disponible.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  void dispose() { _analysisHttp?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Crear ficha con IA')),
    body: SafeArea(child: _loading ? const Center(child: CircularProgressIndicator()) :
      ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Fotografía una herramienta y su etiqueta.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Procura que el texto esté enfocado. Los datos desconocidos se dejarán vacíos; podrás corregir la propuesta antes de guardarla.'),
        const SizedBox(height: 12),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.account_circle_outlined),
          title: Text(connection.active?.sharing == true ? 'Usando tu plan de ChatGPT' : 'Conecta ChatGPT para analizar fotos'),
          subtitle: connection.active?.sharing == true ? Text(connection.active!.email.isEmpty ? 'Cuenta conectada' : connection.active!.email) : null),
        OutlinedButton.icon(onPressed: withButtonFeedback(_busy ? null : _settings),
          icon: const Icon(Icons.manage_accounts_outlined), label: Text(connection.active?.sharing == true ? 'Conexión con ChatGPT' : 'Conectar ChatGPT')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(key: const ValueKey('ai_camera'), onPressed: withButtonFeedback(_busy ? null : () => _pick(ImageSource.camera)),
            icon: const Icon(Icons.camera_alt_outlined), label: const Text('Tomar foto')),
          OutlinedButton.icon(key: const ValueKey('ai_gallery'), onPressed: withButtonFeedback(_busy ? null : () => _pick(ImageSource.gallery)),
            icon: const Icon(Icons.photo_library_outlined), label: const Text('Elegir foto')),
        ]),
        if (_photo != null) ...[
          const SizedBox(height: 16),
          ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_photo!.path),
            height: 220, fit: BoxFit.contain, cacheWidth: 1000,
            errorBuilder: (_, _, _) => const SizedBox(height: 100, child: Center(child: Text('No se pudo mostrar la fotografía'))))),
          const SizedBox(height: 12),
          const Text('Al pulsar Analizar, esta foto se enviará a OpenAI y consumirá el uso disponible de tu plan o tus créditos de ChatGPT.'),
          const SizedBox(height: 12),
          FilledButton.icon(key: const ValueKey('ai_analyze'),
            onPressed: withButtonFeedback(_busy || connection.active?.sharing != true ? null : _run),
            icon: const Icon(Icons.auto_awesome_outlined), label: Text(_draft == null ? 'Analizar con ChatGPT' : 'Volver a analizar')),
        ],
        if (_busy && _analysisHttp != null) ...[
          const SizedBox(height: 16), const LinearProgressIndicator(), const SizedBox(height: 8),
          const Text('ChatGPT está preparando la propuesta…'),
          TextButton(onPressed: withButtonFeedback(_cancel), child: const Text('Cancelar análisis')),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_error!, key: const ValueKey('ai_photo_error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_responseText != null) ExpansionTile(key: const ValueKey('ai_response'), tilePadding: EdgeInsets.zero,
          title: const Text('Ver respuesta de ChatGPT'),
          children: [Padding(padding: const EdgeInsets.only(bottom: 16), child: SelectableText(_responseText!))]),
        if (_errorCode == 'limit') FilledButton(onPressed: withButtonFeedback(() async {
          try { await connection.openUsage(); } catch (error) { if (mounted) setState(() => _error = aiErrorText(error)); }
        }), child: const Text('Gestionar uso')),
        if (_draft != null) ...[
          const SizedBox(height: 16),
          const Text('Propuesta de ficha', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final field in <String, String>{'Nombre': _draft!.name, 'Tipo': _draft!.type,
            'Marca': _draft!.brand, 'Modelo / referencia': _draft!.model,
            'Número de serie': _draft!.serialNumber, 'Tensión': _draft!.voltage,
            'Descripción': _draft!.description}.entries)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(field.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(field.value.isEmpty ? 'Sin identificar' : field.value)])),
          if (_draft!.warnings.isNotEmpty) Text(_draft!.warnings.join('\n')),
          if (_draft!.labelText.isNotEmpty) ExpansionTile(tilePadding: EdgeInsets.zero,
            title: const Text('Texto leído en la etiqueta'), children: [SelectableText(_draft!.labelText)]),
          const SizedBox(height: 12),
          const Text('La herramienta aún no está guardada. Revisa también la cantidad, el estado y la ubicación en la siguiente pantalla.'),
          const SizedBox(height: 12),
          FilledButton.icon(key: const ValueKey('ai_review'), onPressed: withButtonFeedback(_busy ? null : _review),
            icon: const Icon(Icons.edit_outlined), label: const Text('Revisar ficha')),
        ],
      ])));
}
