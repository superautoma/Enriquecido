part of 'main_quill_integrated_test.dart';

Future<String> svgSourceForIcon(String key) async {
  if (!canOpenSvgEditor(key))
    throw const FormatException('Selecciona un icono SVG.');
  if (isElectricCollectionKey(key)) {
    return rootBundle.loadString(
      'assets/icons/electricos/${key.substring('electric_'.length)}.svg',
    );
  }
  final directory = await customIconsDirectory();
  final file = File(customIconPathFromKey(key));
  final resolved = await file.resolveSymbolicLinks();
  if (!p.isWithin(await directory.resolveSymbolicLinks(), resolved)) {
    throw const FormatException(
      'El icono debe estar dentro de la biblioteca de la aplicación.',
    );
  }
  if (await file.length() > svgEditorMaxBytes)
    throw const FormatException('El SVG supera 512 KiB.');
  return file.readAsString();
}

Future<String?> openSvgEditor(BuildContext context, String key) async {
  try {
    final source = await svgSourceForIcon(key);
    final document = SvgEditorDocument.parse(source);
    // Fail before navigation if geometry or rendering is not supported.
    await SvgStringLoader(document.export(const SvgEdits())).loadBytes(null);
    if (!context.mounted) return null;
    final groups = await loadCustomIconGroups([key]);
    if (!context.mounted) return null;
    return await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SvgEditorPage(
          document: document,
          originalKey: key,
          initialName: '${appIconLabel(key)} editado',
          initialGroup: iconCategoryForKey(key, groups),
        ),
      ),
    );
  } on FormatException catch (e) {
    if (context.mounted)
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('SVG no compatible'),
          content: Text(
            '${e.message}\nEl archivo original se conserva sin cambios.',
          ),
          actions: [
            TextButton(
              onPressed: withButtonFeedback(() => Navigator.pop(context)),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir este SVG. El original se conserva.'),
        ),
      );
  }
  return null;
}

// All writes are to a new unique path. Register metadata only after the SVG is
// validated and atomically renamed; restore the previous metadata on failure.
Future<String> saveSvgEditorCopy(
  SvgEditorDocument document,
  SvgEdits edits, {
  required String name,
  required String group,
}) async {
  final label = name.trim();
  if (label.isEmpty || label.length > 80 || !iconGroups.contains(group))
    throw const FormatException('Revisa el nombre y el grupo.');
  final source = document.export(edits);
  await SvgStringLoader(source).loadBytes(null);
  final directory = await customIconsDirectory();
  final safe = label
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
      .substring(
        0,
        math.min(50, label.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_').length),
      );
  var counter = 0;
  late File destination;
  do {
    destination = File(
      p.join(
        directory.path,
        'svg_edit_${safe}_${DateTime.now().microsecondsSinceEpoch}_${counter++}.svg',
      ),
    );
  } while (await destination.exists());
  final temporary = File('${destination.path}.tmp');
  final names = await iconNamesFile(), settings = await iconSettingsFile();
  final previous = <File, List<int>?>{};
  for (final file in [names, settings]) {
    previous[file] = await file.exists() ? await file.readAsBytes() : null;
  }
  try {
    await temporary.writeAsString(source, flush: true);
    validateSvgSource(await temporary.readAsString());
    await temporary.rename(destination.path);
    final key = 'custom:${destination.path}';
    await saveCustomIconGroup(key, group);
    await saveIconName(key, label);
    return key;
  } catch (_) {
    for (final file in [
      temporary,
      destination,
      File('${destination.path}.group.json'),
    ]) {
      if (await file.exists()) await file.delete();
    }
    for (final entry in previous.entries) {
      if (entry.value == null) {
        if (await entry.key.exists()) await entry.key.delete();
      } else {
        final temp = File('${entry.key.path}.rollback');
        await temp.writeAsBytes(entry.value!, flush: true);
        await temp.rename(entry.key.path);
      }
    }
    for (final file in [
      File('${names.path}.tmp'),
      File('${settings.path}.tmp'),
    ]) {
      if (await file.exists()) await file.delete();
    }
    await loadIconNames();
    await loadIconSettings();
    rethrow;
  }
}

class SvgEditorPage extends StatefulWidget {
  const SvgEditorPage({
    super.key,
    required this.document,
    required this.originalKey,
    required this.initialName,
    this.initialGroup = 'Mis iconos',
  });
  final SvgEditorDocument document;
  final String originalKey, initialName, initialGroup;
  @override
  State<SvgEditorPage> createState() => _SvgEditorPageState();
}

class _SvgEditorPageState extends State<SvgEditorPage> {
  final _history = SvgEditHistory();
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _group;
  bool _busy = false, _showCircle = true;
  String? _error;
  int _revision = 0;
  String? _fillInput, _strokeInput, _backgroundInput;
  bool get _dirty =>
      _history.current.fill != null ||
      _history.current.stroke != null ||
      _history.current.background != null ||
      _history.current.strokeWidth != null ||
      _history.current.fit ||
      _history.current.scale != 1 ||
      _history.current.x != 0 ||
      _history.current.y != 0 ||
      _history.current.rotation != 0 ||
      [
        _fillInput,
        _strokeInput,
        _backgroundInput,
      ].any((v) => v != null && v.isNotEmpty && svgEditorHex(v) == null) ||
      _name.text != widget.initialName ||
      _group != widget.initialGroup;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _group = iconGroups.contains(widget.initialGroup)
        ? widget.initialGroup
        : 'Mis iconos';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _change(SvgEdits state) => setState(() {
    _history.push(state);
    _error = null;
  });
  void _historyAction(VoidCallback action) => setState(() {
    action();
    _revision++;
    _fillInput = _history.current.fill;
    _strokeInput = _history.current.stroke;
    _backgroundInput = _history.current.background;
    _error = null;
  });
  Future<void> _leave() async {
    if (_busy) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Descartar cambios'),
          content: const Text(
            'La copia no se ha guardado. El SVG original no se modifica.',
          ),
          actions: [
            TextButton(
              onPressed: withButtonFeedback(
                () => Navigator.pop(context, false),
              ),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              onPressed: withButtonFeedback(() => Navigator.pop(context, true)),
              child: const Text('Descartar'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    // Fields are validated even when scrolled offscreen.
    for (final v in [_fillInput, _strokeInput, _backgroundInput]) {
      if (v != null && v.trim().isNotEmpty && svgEditorHex(v) == null) {
        setState(() => _error = 'Utiliza #RRGGBB o none.');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final key = await saveSvgEditorCopy(
        widget.document,
        _history.current,
        name: _name.text,
        group: _group,
      );
      if (mounted) Navigator.pop(context, key);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException ? '${e.message}' : 'No se pudo guardar. El original y las asignaciones se conservan.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _color(
    String title,
    String id,
    String? value,
    void Function(String) apply,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        key: ValueKey('$id-$_revision'),
        initialValue: value ?? '',
        decoration: InputDecoration(
          labelText: title,
          hintText: 'Conservar; #RRGGBB o none',
        ),
        validator: (v) =>
            v == null || v.trim().isEmpty || svgEditorHex(v) != null
            ? null
            : 'Utiliza #RRGGBB o none',
        onChanged: (v) {
          if (id == 'fill') _fillInput = v;
          if (id == 'stroke') _strokeInput = v;
          if (id == 'background') _backgroundInput = v;
          final hex = svgEditorHex(v);
          if (v.trim().isEmpty) {
            _change(
              _history.current.copyWith(
                clearFill: id == 'fill',
                clearStroke: id == 'stroke',
                clearBackground: id == 'background',
              ),
            );
          } else if (hex != null)
            apply(hex);
          else
            setState(() {});
        },
      ),
      Wrap(
        spacing: 4,
        children: [
          for (final hex in [
            '#000000',
            '#ffffff',
            '#e53935',
            '#1976d2',
            '#23836d',
            'none',
          ])
            IconButton(
              tooltip: '$title $hex',
              icon: hex == 'none'
                  ? const Icon(Icons.block)
                  : Icon(
                      Icons.circle,
                      color: Color(
                        int.parse('ff${hex.substring(1)}', radix: 16),
                      ),
                    ),
              onPressed: withButtonFeedback(
                () => setState(() {
                  apply(hex);
                  _revision++;
                  _fillInput = _history.current.fill;
                  _strokeInput = _history.current.stroke;
                  _backgroundInput = _history.current.background;
                }),
              ),
            ),
        ],
      ),
    ],
  );
  Widget _slider(
    String label,
    String id,
    double value,
    double min,
    double max,
    void Function(double) apply,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label: ${value.toStringAsFixed(1)}'),
      Slider(
        key: ValueKey(id),
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: 200,
        onChanged: withControlFeedback(apply),
      ),
    ],
  );
  Widget _preview(String source, double size, {bool circle = false}) =>
      SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            color: circle ? const Color(0xffeaf2fb) : Colors.white,
          ),
          child: Center(
            child: SizedBox.square(
              dimension: circle ? size * .70 : size,
              child: SvgPicture.string(source, fit: BoxFit.contain),
            ),
          ),
        ),
      );
  @override
  Widget build(BuildContext context) {
    String? source;
    try {
      source = widget.document.export(_history.current);
    } on FormatException catch (e) {
      _error = '${e.message}';
    }
    final state = _history.current;
    return PopScope(
      canPop: !_busy && !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Editor SVG'),
          leading: BackButton(onPressed: withButtonFeedback(_leave)),
          actions: [
            IconButton(
              tooltip: 'Deshacer',
              onPressed: withButtonFeedback(
                _history.canUndo ? () => _historyAction(_history.undo) : null,
              ),
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Rehacer',
              onPressed: withButtonFeedback(
                _history.canRedo ? () => _historyAction(_history.redo) : null,
              ),
              icon: const Icon(Icons.redo),
            ),
          ],
        ),
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: _busy,
            child: Form(
              key: _form,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Se guardará un nuevo archivo. El original y los iconos asignados se conservan.',
                    ),
                    TextFormField(
                      key: const ValueKey('svg_name'),
                      controller: _name,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del nuevo icono',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Escribe un nombre'
                          : null,
                      onChanged: (_) => setState(() {}),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _group,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Grupo'),
                      items: [
                        for (final g in iconGroups)
                          DropdownMenuItem(value: g, child: Text(g)),
                      ],
                      onChanged: withControlFeedback((g) {
                        if (g != null) setState(() => _group = g);
                      }),
                      onTap: () => ButtonFeedbackController.instance.tap(),
                      enableFeedback: false,
                    ),
                    const SizedBox(height: 12),
                    if (source != null) ...[
                      Center(child: _preview(source, 180, circle: _showCircle)),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mostrar círculo del botón'),
                        value: _showCircle,
                        onChanged: withControlFeedback(
                          (v) => setState(() => _showCircle = v),
                        ),
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          for (final size in [24.0, 48.0, 80.0])
                            Column(
                              children: [
                                _preview(source, size, circle: true),
                                Text('${size.toInt()} px'),
                              ],
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (widget.document.multicolor)
                      const Text(
                        'SVG multicolor: cambiar relleno o trazo sustituye ese color en todas las formas, salvo el fondo identificado.',
                      ),
                    _color(
                      'Relleno',
                      'fill',
                      state.fill,
                      (v) => _change(_history.current.copyWith(fill: v)),
                    ),
                    _color(
                      'Color de línea',
                      'stroke',
                      state.stroke,
                      (v) => _change(_history.current.copyWith(stroke: v)),
                    ),
                    _color(
                      'Fondo SVG (círculo)',
                      'background',
                      state.background,
                      (v) => _change(_history.current.copyWith(background: v)),
                    ),
                    _slider(
                      'Grosor del trazo',
                      'svg_width',
                      state.strokeWidth ?? 1,
                      0,
                      20,
                      (v) => _change(_history.current.copyWith(strokeWidth: v)),
                    ),
                    _slider(
                      'Tamaño / escala',
                      'svg_scale',
                      state.scale,
                      .1,
                      3,
                      (v) => _change(_history.current.copyWith(scale: v)),
                    ),
                    _slider(
                      'Posición X',
                      'svg_x',
                      state.x,
                      -100,
                      100,
                      (v) => _change(_history.current.copyWith(x: v)),
                    ),
                    _slider(
                      'Posición Y',
                      'svg_y',
                      state.y,
                      -100,
                      100,
                      (v) => _change(_history.current.copyWith(y: v)),
                    ),
                    _slider(
                      'Rotación',
                      'svg_rotation',
                      state.rotation,
                      -180,
                      180,
                      (v) => _change(_history.current.copyWith(rotation: v)),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: withButtonFeedback(
                            () => _change(
                              _history.current.copyWith(
                                fit: true,
                                scale: 1,
                                x: 0,
                                y: 0,
                                rotation: 0,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.center_focus_strong),
                          label: const Text('Centrar y ajustar'),
                        ),
                        OutlinedButton(
                          onPressed: withButtonFeedback(
                            () => _historyAction(_history.reset),
                          ),
                          child: const Text('Restablecer'),
                        ),
                      ],
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _error!,
                          key: const ValueKey('svg_error'),
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey('svg_save'),
                      onPressed: withButtonFeedback(_busy ? null : _save),
                      icon: const Icon(Icons.save_as_outlined),
                      label: Text(
                        _busy ? 'Guardando…' : 'Guardar como nuevo SVG',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
