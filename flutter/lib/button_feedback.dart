part of 'main_quill_integrated_test.dart';

const buttonFeedbackSettingsKey = 'button_feedback';
const buttonFeedbackChannel = MethodChannel('org.gestorherramientas/button_feedback');

class ButtonVibrationStatus {
  const ButtonVibrationStatus({this.hasMotor, this.permissionGranted,
    this.touchEnabled, this.version, this.result});

  final bool? hasMotor;
  final bool? permissionGranted;
  final bool? touchEnabled;
  final int? version;
  final String? result;

  factory ButtonVibrationStatus.fromMap(Map<Object?, Object?> map) => ButtonVibrationStatus(
    hasMotor: map['hasVibrator'] is bool ? map['hasVibrator'] as bool : null,
    permissionGranted: map['permissionGranted'] is bool ? map['permissionGranted'] as bool : null,
    touchEnabled: map['touchFeedbackEnabled'] is bool ? map['touchFeedbackEnabled'] as bool : null,
    version: map['appVersion'] is int ? map['appVersion'] as int : null,
    result: map['status'] is String ? map['status'] as String : null);

  String get message {
    if (hasMotor == false || result == 'no_motor') {
      return 'Este dispositivo no tiene motor de vibración disponible.';
    }
    if (permissionGranted == false || result == 'permission_denied') {
      return 'Android no permite vibrar a esta instalación. Revisa los ajustes del móvil.';
    }
    if (touchEnabled == false || result == 'system_disabled') {
      return 'Android tiene desactivada la respuesta táctil. Actívala en los ajustes del móvil.';
    }
    if (result == 'requested') {
      return 'Prueba de un segundo enviada. Si no la notas, revisa la intensidad de vibración en los ajustes del móvil.';
    }
    if (result == 'unavailable') {
      return 'No se pudo acceder a la vibración. Pulsa «Comprobar de nuevo» o actualiza la aplicación.';
    }
    if (hasMotor == true && permissionGranted == true) return 'Motor de vibración detectado.';
    return 'No se pudo comprobar la vibración. Pulsa «Comprobar de nuevo» o actualiza la aplicación.';
  }
}

class ButtonFeedbackPreferences {
  const ButtonFeedbackPreferences({this.sound = true, this.vibration = true});

  final bool sound;
  final bool vibration;

  ButtonFeedbackPreferences copyWith({bool? sound, bool? vibration}) =>
      ButtonFeedbackPreferences(sound: sound ?? this.sound,
        vibration: vibration ?? this.vibration);

  Map<String, Object?> toMap() => {'sound': sound, 'vibration': vibration};

  factory ButtonFeedbackPreferences.fromMap(Map<String, dynamic> map) =>
      ButtonFeedbackPreferences(sound: map['sound'] is bool ? map['sound'] as bool : true,
        vibration: map['vibration'] is bool ? map['vibration'] as bool : true);
}

class ButtonFeedbackController extends ValueNotifier<ButtonFeedbackPreferences> {
  ButtonFeedbackController() : super(const ButtonFeedbackPreferences());

  static final instance = ButtonFeedbackController();
  Future<void>? _write;
  bool _tapQueued = false;

  Future<void> load() async {
    final pendingWrite = _write;
    if (pendingWrite != null) await pendingWrite;
    final rows = await (await ToolsDatabase.instance.database).query('management_settings',
      where: 'key=?', whereArgs: [buttonFeedbackSettingsKey]);
    try {
      final saved = rows.isEmpty ? null : jsonDecode(rows.single['value'] as String);
      value = saved is Map<String, dynamic>
          ? ButtonFeedbackPreferences.fromMap(saved) : const ButtonFeedbackPreferences();
    } on FormatException {
      value = const ButtonFeedbackPreferences();
    }
  }

  Future<void> update(ButtonFeedbackPreferences preferences) {
    final previous = value;
    value = preferences;
    final pendingWrite = _write;
    Future<void> persist() async {
      if (pendingWrite != null) await pendingWrite;
      await (await ToolsDatabase.instance.database).insert('management_settings',
        {'key': buttonFeedbackSettingsKey, 'value': jsonEncode(preferences.toMap())},
        conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final operation = persist();
    late final Future<void> queuedWrite;
    queuedWrite = operation.catchError((Object error) {
      if (identical(value, preferences)) value = previous;
    }).whenComplete(() {
      if (identical(_write, queuedWrite)) _write = null;
    });
    _write = queuedWrite;
    return operation;
  }

  void tap() {
    // A callback passed through two widgets still produces a single response.
    // Run the action immediately; never wait for audio or haptics.
    if (_tapQueued) return;
    final preferences = value;
    if (!preferences.sound && !preferences.vibration) return;
    _tapQueued = true;
    scheduleMicrotask(() {
      _tapQueued = false;
      unawaited(_play(preferences));
    });
  }

  Future<void> _play(ButtonFeedbackPreferences preferences) async {
    try {
      await buttonFeedbackChannel.invokeMethod<void>('tap', preferences.toMap());
    } on MissingPluginException {
      // Native Android plays the bundled short click. Keep other platforms usable.
      try {
        if (preferences.sound) await SystemSound.play(SystemSoundType.click);
        if (preferences.vibration) await HapticFeedback.selectionClick();
      } on Exception {
        // An unavailable effect must not interrupt a button's action.
      }
    } on PlatformException {
      // Audio/haptics can be unavailable without affecting the action.
    }
  }

  Future<ButtonVibrationStatus> checkVibration() => _vibrationRequest('vibrationStatus');

  Future<ButtonVibrationStatus> testVibration() => _vibrationRequest('testVibration');

  Future<ButtonVibrationStatus> _vibrationRequest(String method) async {
    try {
      final status = await buttonFeedbackChannel.invokeMapMethod<Object?, Object?>(method)
        .timeout(const Duration(seconds: 4));
      return status == null ? const ButtonVibrationStatus(result: 'unavailable')
        : ButtonVibrationStatus.fromMap(status);
    } on Exception {
      return const ButtonVibrationStatus(result: 'unavailable');
    }
  }

  Future<bool> openVibrationSettings() async {
    try {
      return await buttonFeedbackChannel.invokeMethod<bool>('openVibrationSettings') ?? false;
    } on Exception {
      return false;
    }
  }
}

VoidCallback? withButtonFeedback(VoidCallback? callback) => callback == null ? null : () {
  ButtonFeedbackController.instance.tap();
  callback();
};

ValueChanged<T>? withControlFeedback<T>(ValueChanged<T>? callback) => callback == null ? null : (value) {
  ButtonFeedbackController.instance.tap();
  callback(value);
};

class ButtonFeedbackPage extends StatefulWidget {
  const ButtonFeedbackPage({super.key});

  @override
  State<ButtonFeedbackPage> createState() => _ButtonFeedbackPageState();
}

class _ButtonFeedbackPageState extends State<ButtonFeedbackPage> with WidgetsBindingObserver {
  bool _saving = false;
  bool _testing = false;
  ButtonVibrationStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshStatus());
  }

  Future<void> _refreshStatus() async {
    final status = await ButtonFeedbackController.instance.checkVibration();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _testVibration() async {
    setState(() => _testing = true);
    final status = await ButtonFeedbackController.instance.testVibration();
    if (mounted) setState(() { _status = status; _testing = false; });
  }

  Future<void> _openSettings() async {
    final opened = await ButtonFeedbackController.instance.openVibrationSettings();
    if (!opened && mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Abre los ajustes del móvil y busca «Vibración» o «Respuesta táctil».')));
  }

  Future<void> _update(ButtonFeedbackPreferences preferences) async {
    setState(() => _saving = true);
    try {
      await ButtonFeedbackController.instance.update(preferences);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el ajuste. Inténtalo de nuevo.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sonido y vibración'),
      leading: BackButton(onPressed: withButtonFeedback(() => Navigator.maybePop(context)))),
    body: SafeArea(child: ValueListenableBuilder<ButtonFeedbackPreferences>(
      valueListenable: ButtonFeedbackController.instance,
      builder: (context, preferences, _) => ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Column(children: [
          SwitchListTile(key: const ValueKey('button_sound'),
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Sonido al pulsar'), subtitle: const Text('Un clic corto y discreto'),
            value: preferences.sound,
            onChanged: _saving ? null : withControlFeedback<bool>((value) =>
              _update(preferences.copyWith(sound: value)))),
          const Divider(height: 1),
          SwitchListTile(key: const ValueKey('button_vibration'),
            secondary: const Icon(Icons.vibration_outlined),
            title: const Text('Vibración al pulsar'), subtitle: const Text('Un pulso compatible con el motor del móvil'),
            value: preferences.vibration,
            onChanged: _saving ? null : withControlFeedback<bool>((value) =>
              _update(preferences.copyWith(vibration: value)))),
        ])),
        const SizedBox(height: 20),
        FilledButton.icon(key: const ValueKey('test_button_feedback'),
          style: const ButtonStyle(enableFeedback: false),
          onPressed: withButtonFeedback(() {}), icon: const Icon(Icons.touch_app_outlined),
          label: const Text('Probar botón')),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Comprobar vibración', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_status?.message ?? 'Comprobando el motor de vibración…',
              key: const ValueKey('vibration_status')),
            if (_status?.version != null) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text('Versión instalada: ${_status!.version}', style: const TextStyle(fontSize: 12))),
            const SizedBox(height: 12),
            OutlinedButton.icon(key: const ValueKey('test_vibration'),
              style: const ButtonStyle(enableFeedback: false),
              onPressed: _testing ? null : _testVibration,
              icon: const Icon(Icons.vibration_outlined), label: Text(_testing ? 'Probando…' : 'Probar vibración (1 segundo)')),
            TextButton.icon(key: const ValueKey('vibration_system_settings'),
              onPressed: _openSettings, icon: const Icon(Icons.settings_outlined),
              label: const Text('Ajustes del móvil')),
            TextButton(key: const ValueKey('refresh_vibration_status'),
              onPressed: _refreshStatus, child: const Text('Comprobar de nuevo')),
          ]))),
        const SizedBox(height: 16),
        const Text('El sonido respeta el modo silencio y el volumen del teléfono. '
          'La vibración depende de los ajustes y del motor de vibración del dispositivo.',
          style: TextStyle(color: Color(0xFF687580))),
      ]))),
  );
}
