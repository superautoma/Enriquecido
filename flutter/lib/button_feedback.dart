part of 'main_quill_integrated_test.dart';

const buttonFeedbackSettingsKey = 'button_feedback';
const buttonFeedbackChannel = MethodChannel('org.gestorherramientas/button_feedback');

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

class _ButtonFeedbackPageState extends State<ButtonFeedbackPage> {
  bool _saving = false;

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
            title: const Text('Vibración al pulsar'), subtitle: const Text('Un pulso corto y más marcado'),
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
        const Text('El sonido respeta el modo silencio y el volumen del teléfono. '
          'La vibración depende de los ajustes y del motor de vibración del dispositivo.',
          style: TextStyle(color: Color(0xFF687580))),
      ]))),
  );
}
