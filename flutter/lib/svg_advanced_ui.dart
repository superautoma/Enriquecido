part of 'main_quill_integrated_test.dart';

class SvgAdvancedPage extends StatefulWidget {
  const SvgAdvancedPage({
    super.key,
    required this.source,
    required this.initialName,
    required this.initialGroup,
  });
  final String source, initialName, initialGroup;
  @override
  State<SvgAdvancedPage> createState() => _SvgAdvancedPageState();
}

class _SvgAdvancedPageState extends State<SvgAdvancedPage> {
  late SvgVectorDocument _doc;
  late TextEditingController _name;
  late String _group;
  final _view = TransformationController();
  late Rect _canvas;
  String _mode = 'Seleccionar';
  bool _grid = false,
      _snap = false,
      _multiple = false,
      _busy = false,
      _guides = false;
  String? _error;
  SvgVectorHandle? _handle;
  Offset? _dragStart;
  int? _pointer;
  Offset? _pointerStart;
  bool _pointerMoved = false;
  SvgVectorHandle? _dragHandle;
  final _form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    _doc = SvgVectorDocument(widget.source);
    _name = TextEditingController(text: widget.initialName);
    _group = widget.initialGroup;
    _fit();
  }

  @override
  void dispose() {
    _name.dispose();
    _view.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _doc.dirty ||
      _name.text != widget.initialName ||
      _group != widget.initialGroup;
  String? get _single =>
      _doc.selection.length == 1 ? _doc.selection.single : null;
  List<SvgVectorHandle> get _handles =>
      _single != null && _doc.nodesEditable(_single!)
      ? _doc.handles(_single!)
      : [];
  void _fit() {
    final b = _doc.visibleBounds.expandToInclude(_doc.viewport);
    final size = math.max(b.width, b.height) * 1.2;
    _canvas = Rect.fromCenter(center: b.center, width: size, height: size);
    _view.value = Matrix4.identity();
  }

  void _act(VoidCallback action) {
    try {
      setState(() {
        action();
        _error = null;
        _handle = null;
      });
    } on FormatException catch (e) {
      setState(() => _error = '${e.message}');
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Descartar edición avanzada?'),
          content: const Text(
            'Los originales se conservan. Los cambios sin guardar se descartarán.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Seguir editando'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
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
    setState(() => _busy = true);
    try {
      final source = _doc.export();
      final key = await saveSvgEditorCopy(
        SvgEditorDocument.parse(source),
        const SvgEdits(),
        name: _name.text,
        group: _group,
        preparedSource: source,
      );
      if (mounted) Navigator.pop(context, key);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException
              ? '${e.message}'
              : 'No se pudo guardar. El original se conserva.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paint(String property, String title) async {
    if (_doc.selection.isEmpty) return;
    final current = _doc.attribute(_doc.selection.first, property);
    final selected = await showSvgColorSelector(
      context,
      title: 'Color: $title',
      initialValue: current != null && svgEditorHex(current) != null
          ? current
          : null,
    );
    if (mounted && selected != null)
      _act(
        () => _doc.paintSelection(property, selected.isEmpty ? null : selected),
      );
  }

  Future<void> _transform() async {
    if (_doc.selection.isEmpty) return;
    final fields = [
      TextEditingController(text: '0'),
      TextEditingController(text: '0'),
      TextEditingController(text: '0'),
      TextEditingController(text: '1'),
      TextEditingController(text: '1'),
    ];
    final key = GlobalKey<FormState>();
    final result = await showDialog<List<double>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transformar selección'),
        content: SingleChildScrollView(
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 5; i++)
                  TextFormField(
                    key: ValueKey('advanced_transform_$i'),
                    controller: fields[i],
                    decoration: InputDecoration(
                      labelText: [
                        'Mover X',
                        'Mover Y',
                        'Giro (grados)',
                        'Escala X',
                        'Escala Y',
                      ][i],
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: (text) {
                      final value = double.tryParse(
                        (text ?? '').replaceAll(',', '.'),
                      );
                      if (value == null ||
                          !value.isFinite ||
                          value.abs() > 100000 ||
                          (i >= 3 && (value <= 0 || value > 10)) ||
                          (i == 2 && value.abs() > 360))
                        return 'Valor fuera de límites';
                      return null;
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate())
                Navigator.pop(
                  context,
                  fields
                      .map((f) => double.parse(f.text.replaceAll(',', '.')))
                      .toList(),
                );
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    // Controllers are kept alive until the dialog's exit animation finishes.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    for (final field in fields) {
      field.dispose();
    }
    if (mounted && result != null)
      _act(
        () => _doc.transformSelection(
          dx: result[0],
          dy: result[1],
          rotation: result[2],
          sx: result[3],
          sy: result[4],
        ),
      );
  }

  Future<void> _width() async {
    final field = TextEditingController(
      text: _single == null
          ? '1'
          : _doc.attribute(_single!, 'stroke-width') ?? '1',
    );
    final key = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Grosor de la selección'),
        content: Form(
          key: key,
          child: TextFormField(
            controller: field,
            decoration: const InputDecoration(labelText: 'Grosor de 0 a 20'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (text) {
              final n = double.tryParse((text ?? '').replaceAll(',', '.'));
              return n != null && n.isFinite && n >= 0 && n <= 20
                  ? null
                  : 'Utiliza un valor de 0 a 20';
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate())
                Navigator.pop(context, field.text.replaceAll(',', '.'));
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    field.dispose();
    if (mounted && value != null)
      _act(() => _doc.paintSelection('stroke-width', value));
  }

  Offset _world(Offset pixel, double size) => Offset(
    _canvas.left + pixel.dx * _canvas.width / size,
    _canvas.top + pixel.dy * _canvas.height / size,
  );
  double get _gridStep => math.max(5.0, _canvas.width / 60);
  List<double> get _guideX => [
    _doc.viewport.left,
    _doc.viewport.center.dx,
    _doc.viewport.right,
    ..._doc.elements
        .where(
          (e) => !e.hidden && e.type != 'g' && !_doc.selection.contains(e.id),
        )
        .take(50)
        .expand((e) => [e.bounds.left, e.bounds.center.dx, e.bounds.right]),
  ];
  List<double> get _guideY => [
    _doc.viewport.top,
    _doc.viewport.center.dy,
    _doc.viewport.bottom,
    ..._doc.elements
        .where(
          (e) => !e.hidden && e.type != 'g' && !_doc.selection.contains(e.id),
        )
        .take(50)
        .expand((e) => [e.bounds.top, e.bounds.center.dy, e.bounds.bottom]),
  ];
  double _guide(double value, List<double> guides) {
    double best = value, distance = _canvas.width / 320 * 8;
    for (final guide in guides) {
      if ((guide - value).abs() < distance) {
        best = guide;
        distance = (guide - value).abs();
      }
    }
    return best;
  }

  Offset _snapped(Offset p) {
    if (_snap)
      p = Offset(
        (p.dx / _gridStep).round() * _gridStep,
        (p.dy / _gridStep).round() * _gridStep,
      );
    if (_guides) p = Offset(_guide(p.dx, _guideX), _guide(p.dy, _guideY));
    return p;
  }

  void _start(DragStartDetails details, double size) {
    if (_mode == 'Vista' || _mode == 'Seleccionar') return;
    final p = _world(details.localPosition, size);
    if (_mode == 'Nodos') {
      final handles = _handles;
      if (handles.isEmpty) return;
      final nearest = handles.reduce(
        (a, b) => (a.position - p).distance < (b.position - p).distance ? a : b,
      );
      if ((nearest.position - p).distance > _canvas.width / size * 20) return;
      _dragHandle = nearest;
      _handle = nearest;
    } else if (_doc.selection.isEmpty) {
      final id = _doc.hitTest(p, tolerance: _canvas.width / size * 8);
      if (id == null) return;
      _doc.select(id);
    }
    _dragStart = p;
    _doc.beginGesture();
    setState(() {});
  }

  void _update(DragUpdateDetails details, double size) {
    if (_dragStart == null) return;
    try {
      final p = _snapped(_world(details.localPosition, size));
      if (_mode == 'Nodos' && _dragHandle != null) {
        _doc.moveHandle(
          _single!,
          _dragHandle!.segment,
          _dragHandle!.point,
          p,
          record: false,
        );
      } else {
        var delta = p - _dragStart!;
        if (_guides) {
          final shapes = _doc.elements
              .where((e) => _doc.selection.contains(e.id))
              .toList();
          if (shapes.isNotEmpty) {
            Rect b = shapes.first.bounds;
            for (final shape in shapes.skip(1)) {
              b = b.expandToInclude(shape.bounds);
            }
            b = b.shift(delta);
            double nearest(List<double> values, List<double> guides) {
              double adjustment = 0, limit = _canvas.width / 320 * 8;
              for (final value in values) {
                final candidate = _guide(value, guides) - value;
                if (candidate != 0 && candidate.abs() < limit) {
                  adjustment = candidate;
                  limit = candidate.abs();
                }
              }
              return adjustment;
            }

            delta += Offset(
              nearest([b.left, b.center.dx, b.right], _guideX),
              nearest([b.top, b.center.dy, b.bottom], _guideY),
            );
          }
        }
        _doc.transformSelection(dx: delta.dx, dy: delta.dy, record: false);
        _dragStart = p;
      }
      setState(() => _error = null);
    } on FormatException catch (e) {
      setState(() => _error = '${e.message}');
    }
  }

  void _end({bool cancel = false}) {
    if (_dragStart == null) return;
    _doc.finishGesture(cancel: cancel);
    _dragStart = null;
    _dragHandle = null;
    setState(() {});
  }

  Widget _button(
    String label,
    IconData icon,
    VoidCallback action, {
    bool enabled = true,
  }) => OutlinedButton.icon(
    onPressed: enabled ? withButtonFeedback(() => _act(action)) : null,
    icon: Icon(icon),
    label: Text(label),
  );
  Widget _canvasWidget() => LayoutBuilder(
    builder: (context, box) {
      final size = math.min(box.maxWidth, 320.0);
      void tapAt(Offset pixel) {
        final p = _world(pixel, size);
        if (_mode == 'Nodos' && _handles.isNotEmpty) {
          final h = _handles.reduce(
            (a, b) =>
                (a.position - p).distance < (b.position - p).distance ? a : b,
          );
          if ((h.position - p).distance <= _canvas.width / size * 20) {
            setState(() => _handle = h);
            return;
          }
        }
        _act(
          () => _doc.select(
            _doc.hitTest(p, tolerance: _canvas.width / size * 8),
            additive: _multiple,
          ),
        );
      }

      final surface = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _mode == 'Seleccionar' ? (d) => tapAt(d.localPosition) : null,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.white),
              SvgPicture.string(
                _doc.renderSource(_canvas),
                fit: BoxFit.contain,
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: _SvgSelectionPainter(
                    canvasBounds: _canvas,
                    elements: _doc.elements
                        .where((e) => _doc.selection.contains(e.id))
                        .toList(),
                    handles: _mode == 'Nodos' ? _handles : [],
                    active: _handle,
                    grid: _grid,
                    guideX: _guides ? _guideX : [],
                    guideY: _guides ? _guideY : [],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      // Editing gets its own gesture arena; the viewer handles gestures only in
      // Vista mode. Keep its matrix when switching so zoom never changes geometry.
      return Center(
        child: SizedBox.square(
          key: const ValueKey('advanced_canvas'),
          dimension: size,
          child: _mode == 'Vista'
              ? InteractiveViewer(
                  transformationController: _view,
                  minScale: .5,
                  maxScale: 8,
                  boundaryMargin: const EdgeInsets.all(320),
                  child: surface,
                )
              : ClipRect(
                  child: Transform(
                    transform: _view.value,
                    child: _mode == 'Mover' || _mode == 'Nodos'
                        ? RawGestureDetector(
                            gestures: {
                              EagerGestureRecognizer:
                                  GestureRecognizerFactoryWithHandlers<
                                    EagerGestureRecognizer
                                  >(EagerGestureRecognizer.new, (_) {}),
                            },
                            child: Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (e) {
                                if (_pointer != null) return;
                                _pointer = e.pointer;
                                _pointerStart = e.localPosition;
                                _pointerMoved = false;
                                _start(
                                  DragStartDetails(
                                    localPosition: e.localPosition,
                                  ),
                                  size,
                                );
                              },
                              onPointerMove: (e) {
                                if (_pointer != e.pointer) return;
                                if ((e.localPosition - _pointerStart!)
                                        .distance >
                                    3)
                                  _pointerMoved = true;
                                if (_pointerMoved)
                                  _update(
                                    DragUpdateDetails(
                                      globalPosition: e.position,
                                      localPosition: e.localPosition,
                                    ),
                                    size,
                                  );
                              },
                              onPointerUp: (e) {
                                if (_pointer != e.pointer) return;
                                _end();
                                _pointer = null;
                                if (!_pointerMoved) tapAt(e.localPosition);
                              },
                              onPointerCancel: (e) {
                                if (_pointer != e.pointer) return;
                                _end(cancel: true);
                                _pointer = null;
                              },
                              child: surface,
                            ),
                          )
                        : surface,
                  ),
                ),
        ),
      );
    },
  );

  Widget _tools() {
    final selected = _doc.selection.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final mode in ['Seleccionar', 'Mover', 'Nodos', 'Vista'])
              ChoiceChip(
                label: Text(mode),
                selected: _mode == mode,
                onSelected: withControlFeedback(
                  (_) => setState(() {
                    _mode = mode;
                    _handle = null;
                  }),
                ),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('Rejilla'),
              selected: _grid,
              onSelected: withControlFeedback((v) => setState(() => _grid = v)),
            ),
            FilterChip(
              label: const Text('Ajuste a rejilla'),
              selected: _snap,
              onSelected: withControlFeedback((v) => setState(() => _snap = v)),
            ),
            FilterChip(
              label: const Text('Ajuste a guías'),
              selected: _guides,
              onSelected: withControlFeedback(
                (v) => setState(() => _guides = v),
              ),
            ),
            FilterChip(
              label: const Text('Selección múltiple'),
              selected: _multiple,
              onSelected: withControlFeedback(
                (v) => setState(() => _multiple = v),
              ),
            ),
            TextButton(
              onPressed: () => setState(_fit),
              child: const Text('Encuadrar lienzo'),
            ),
          ],
        ),
        Text('${_doc.selection.length} elementos seleccionados'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: selected ? withButtonFeedback(_transform) : null,
              icon: const Icon(Icons.transform),
              label: const Text('Transformar'),
            ),
            OutlinedButton.icon(
              onPressed: selected
                  ? withButtonFeedback(
                      () => _paint('fill', 'Relleno de selección'),
                    )
                  : null,
              icon: const Icon(Icons.format_color_fill),
              label: const Text('Relleno de selección'),
            ),
            OutlinedButton.icon(
              onPressed: selected
                  ? withButtonFeedback(
                      () => _paint('stroke', 'Trazo de selección'),
                    )
                  : null,
              icon: const Icon(Icons.border_color),
              label: const Text('Trazo de selección'),
            ),
            OutlinedButton(
              onPressed: selected ? withButtonFeedback(_width) : null,
              child: const Text('Grosor'),
            ),
            _button('Duplicar', Icons.copy, _doc.duplicate, enabled: selected),
            _button(
              'Eliminar selección',
              Icons.delete_outline,
              _doc.deleteSelection,
              enabled: selected,
            ),
            _button(
              'Traer adelante',
              Icons.flip_to_front,
              () => _doc.reorder(true),
              enabled: selected,
            ),
            _button(
              'Enviar atrás',
              Icons.flip_to_back,
              () => _doc.reorder(false),
              enabled: selected,
            ),
            _button(
              'Agrupar',
              Icons.folder_open,
              _doc.groupSelection,
              enabled: _doc.selection.length > 1,
            ),
            _button(
              'Desagrupar',
              Icons.folder_off,
              _doc.ungroup,
              enabled:
                  _single != null &&
                  _doc.elements.any((e) => e.id == _single && e.type == 'g'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in {
              'rect': 'Nuevo rectángulo',
              'circle': 'Nuevo círculo',
              'ellipse': 'Nueva elipse',
              'line': 'Nueva línea',
              'polygon': 'Nuevo polígono',
              'path': 'Nuevo trazado',
            }.entries)
              _button(entry.value, Icons.add, () => _doc.create(entry.key)),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Alinear selección con el lienzo'),
        Wrap(
          spacing: 6,
          children: [
            for (final entry in {
              'left': 'Izquierda',
              'horizontal': 'Centro X',
              'right': 'Derecha',
              'top': 'Arriba',
              'vertical': 'Centro Y',
              'bottom': 'Abajo',
            }.entries)
              _button(
                entry.value,
                Icons.align_horizontal_center,
                () => _doc.align(entry.key),
                enabled: selected,
              ),
          ],
        ),
        if (_doc.selection.length > 1) ...[
          const Text('Alinear cada forma con la primera seleccionada'),
          Wrap(
            spacing: 6,
            children: [
              for (final axis in ['horizontal', 'vertical'])
                _button(
                  axis == 'horizontal'
                      ? 'Alinear centros X'
                      : 'Alinear centros Y',
                  Icons.align_horizontal_center,
                  () => _alignOthers(axis),
                ),
            ],
          ),
        ],
      ],
    );
  }

  void _alignOthers(String axis) {
    final ids = List<String>.of(_doc.selection), reference = ids.first;
    _doc.beginGesture();
    try {
      for (final id in ids.skip(1)) {
        _doc.select(id);
        _doc.align(axis, referenceId: reference);
      }
      _doc.finishGesture();
      _doc.selection
        ..clear()
        ..addAll(ids);
    } catch (_) {
      _doc.finishGesture(cancel: true);
      _doc.selection
        ..clear()
        ..addAll(ids);
      rethrow;
    }
  }

  Widget _tree() => ListView(
    children: [
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Orden de dibujo: los elementos de abajo se dibujan encima. Los grupos conservan sus transformaciones.',
        ),
      ),
      for (final e in _doc.elements)
        ListTile(
          key: ValueKey('advanced_element_${e.id}'),
          contentPadding: EdgeInsets.only(
            left: 12 + math.min(e.depth, 8) * 12.0,
            right: 4,
          ),
          leading: Checkbox(
            value: _doc.selection.contains(e.id),
            onChanged: e.locked
                ? null
                : withControlFeedback(
                    (_) => _act(() => _doc.select(e.id, additive: true)),
                  ),
          ),
          title: Text(e.label),
          subtitle: Text(
            '${e.hidden ? 'Oculto · ' : ''}${e.locked ? 'Bloqueado' : 'Editable'}',
          ),
          onTap: e.locked
              ? null
              : withButtonFeedback(
                  () => _act(() => _doc.select(e.id, additive: _multiple)),
                ),
          trailing: Wrap(
            children: [
              IconButton(
                tooltip: e.hidden ? 'Mostrar elemento' : 'Ocultar elemento',
                icon: Icon(e.hidden ? Icons.visibility_off : Icons.visibility),
                onPressed: withButtonFeedback(
                  () => _act(() => _doc.toggleHidden(e.id)),
                ),
              ),
              IconButton(
                tooltip: e.locked
                    ? 'Desbloquear elemento'
                    : 'Bloquear elemento',
                icon: Icon(e.locked ? Icons.lock : Icons.lock_open),
                onPressed: withButtonFeedback(
                  () => _act(() => _doc.toggleLocked(e.id)),
                ),
              ),
            ],
          ),
        ),
    ],
  );
  Future<void> _nodeCoordinates() async {
    final h = _handle;
    if (h == null || _single == null) return;
    final id = _single!;
    final x = TextEditingController(text: h.position.dx.toStringAsFixed(3)),
        y = TextEditingController(text: h.position.dy.toStringAsFixed(3));
    final key = GlobalKey<FormState>();
    final p = await showDialog<Offset>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(h.control ? 'Manejador Bézier' : 'Nodo'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in {'X': x, 'Y': y}.entries)
                TextFormField(
                  key: ValueKey('advanced_node_${entry.key}'),
                  controller: entry.value,
                  decoration: InputDecoration(labelText: entry.key),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (text) {
                    final v = double.tryParse(
                      (text ?? '').replaceAll(',', '.'),
                    );
                    return v != null && v.isFinite && v.abs() <= 100000
                        ? null
                        : 'Coordenada no válida';
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate())
                Navigator.pop(
                  context,
                  Offset(
                    double.parse(x.text.replaceAll(',', '.')),
                    double.parse(y.text.replaceAll(',', '.')),
                  ),
                );
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    x.dispose();
    y.dispose();
    if (mounted && p != null)
      _act(() => _doc.moveHandle(id, h.segment, h.point, _snapped(p)));
  }

  Widget _nodesPanel() {
    final id = _single;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (id == null)
            const Text(
              'Selecciona un trazado, una línea, un polígono o una polilínea.',
            )
          else if (!_doc.nodesEditable(id))
            const Text(
              'Los arcos conservan sus comandos originales. Las formas cerradas básicas se editan con Transformar; sus nodos no se convierten automáticamente.',
            )
          else ...[
            const Text(
              'Nodos y manejadores en coordenadas del lienzo. Puedes elegirlos aquí o arrastrarlos en modo Nodos.',
            ),
            OutlinedButton(
              onPressed: _handle == null
                  ? null
                  : withButtonFeedback(_nodeCoordinates),
              child: const Text('Editar coordenadas'),
            ),
            Wrap(
              spacing: 8,
              children: [
                _button(
                  'Insertar nodo',
                  Icons.add_circle_outline,
                  () => _doc.insertNode(id, _handle!.segment),
                  enabled:
                      _handle != null &&
                      !_handle!.control &&
                      _handle!.segment > 0,
                ),
                _button(
                  'Eliminar nodo',
                  Icons.remove_circle_outline,
                  () => _doc.deleteNode(id, _handle!.segment),
                  enabled:
                      _handle != null &&
                      !_handle!.control &&
                      _handle!.segment > 0,
                ),
              ],
            ),
            if (_doc.elements.firstWhere((e) => e.id == id).type == 'path')
              _button(
                _doc.pathClosed(id) ? 'Abrir trazado' : 'Cerrar trazado',
                Icons.polyline,
                () => _doc.toggleClosed(id),
              ),
            for (final h in _handles)
              ListTile(
                key: ValueKey('advanced_handle_${h.segment}_${h.point}'),
                selected:
                    _handle?.segment == h.segment && _handle?.point == h.point,
                leading: Icon(
                  h.control ? Icons.control_point : Icons.circle_outlined,
                ),
                title: Text(
                  '${h.control ? 'Manejador' : 'Nodo'} ${h.segment}.${h.point}',
                ),
                subtitle: Text(
                  'X ${h.position.dx.toStringAsFixed(2)} · Y ${h.position.dy.toStringAsFixed(2)}',
                ),
                onTap: withButtonFeedback(() => setState(() => _handle = h)),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_dirty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SVG avanzado'),
          leading: BackButton(onPressed: withButtonFeedback(_leave)),
          actions: [
            IconButton(
              tooltip: 'Deshacer',
              icon: const Icon(Icons.undo),
              onPressed: _busy
                  ? null
                  : withButtonFeedback(
                      _doc.canUndo ? () => _act(_doc.undo) : null,
                    ),
            ),
            IconButton(
              tooltip: 'Rehacer',
              icon: const Icon(Icons.redo),
              onPressed: _busy
                  ? null
                  : withButtonFeedback(
                      _doc.canRedo ? () => _act(_doc.redo) : null,
                    ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Lienzo'),
              Tab(text: 'Elementos'),
              Tab(text: 'Nodos'),
            ],
          ),
        ),
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: _busy,
            child: Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Column(children: [_canvasWidget(), _tools()]),
                      ),
                      _tree(),
                      _nodesPanel(),
                    ],
                  ),
                ),
                Form(
                  key: _form,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('advanced_name'),
                            controller: _name,
                            maxLength: 80,
                            decoration: const InputDecoration(
                              labelText: 'Nombre de la copia',
                            ),
                            validator: (text) =>
                                text == null || text.trim().isEmpty
                                ? 'Escribe un nombre'
                                : null,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Grupo de la copia',
                          icon: const Icon(Icons.folder_outlined),
                          onPressed: withButtonFeedback(() async {
                            final group = await showDialog<String>(
                              context: context,
                              builder: (context) => SimpleDialog(
                                title: const Text('Grupo de la copia'),
                                children: [
                                  for (final g in iconGroups)
                                    SimpleDialogOption(
                                      onPressed: () =>
                                          Navigator.pop(context, g),
                                      child: Text(g),
                                    ),
                                ],
                              ),
                            );
                            if (mounted && group != null)
                              setState(() => _group = group);
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    key: const ValueKey('advanced_save'),
                    onPressed: _busy ? null : withButtonFeedback(_save),
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_as),
                    label: const Text('Guardar SVG avanzado como copia'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SvgSelectionPainter extends CustomPainter {
  _SvgSelectionPainter({
    required this.canvasBounds,
    required this.elements,
    required this.handles,
    required this.active,
    required this.grid,
    required this.guideX,
    required this.guideY,
  });
  final Rect canvasBounds;
  final List<SvgVectorElement> elements;
  final List<SvgVectorHandle> handles;
  final SvgVectorHandle? active;
  final bool grid;
  final List<double> guideX, guideY;
  Offset _screen(Offset p, Size size) => Offset(
    (p.dx - canvasBounds.left) * size.width / canvasBounds.width,
    (p.dy - canvasBounds.top) * size.height / canvasBounds.height,
  );
  @override
  void paint(Canvas canvas, Size size) {
    if (grid) {
      final pen = Paint()
        ..color = const Color(0xffdce9e6)
        ..strokeWidth = .5;
      final step = math.max(5.0, canvasBounds.width / 60);
      for (
        double x = (canvasBounds.left / step).ceil() * step;
        x < canvasBounds.right;
        x += step
      ) {
        final p = _screen(Offset(x, canvasBounds.top), size);
        canvas.drawLine(p, Offset(p.dx, size.height), pen);
      }
      for (
        double y = (canvasBounds.top / step).ceil() * step;
        y < canvasBounds.bottom;
        y += step
      ) {
        final p = _screen(Offset(canvasBounds.left, y), size);
        canvas.drawLine(p, Offset(size.width, p.dy), pen);
      }
    }
    final guidePaint = Paint()
      ..color = const Color(0x55795948)
      ..strokeWidth = 1;
    for (final x in guideX) {
      final p = _screen(Offset(x, canvasBounds.top), size);
      canvas.drawLine(p, Offset(p.dx, size.height), guidePaint);
    }
    for (final y in guideY) {
      final p = _screen(Offset(canvasBounds.left, y), size);
      canvas.drawLine(p, Offset(size.width, p.dy), guidePaint);
    }
    final selection = Paint()
      ..color = const Color(0xff00897b)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final e in elements) {
      final top = _screen(e.bounds.topLeft, size),
          bottom = _screen(e.bounds.bottomRight, size);
      canvas.drawRect(Rect.fromPoints(top, bottom).inflate(3), selection);
    }
    final line = Paint()
      ..color = const Color(0xff607d8b)
      ..strokeWidth = 1;
    for (var i = 0; i < handles.length; i++) {
      final h = handles[i], p = _screen(h.position, size);
      if (h.control) {
        final anchors = handles.where((a) => !a.control).toList();
        SvgVectorHandle? anchor;
        if (h.point == 0) {
          final previous = anchors.where((a) => a.segment < h.segment);
          if (previous.isNotEmpty) anchor = previous.last;
        } else {
          final same = anchors.where((a) => a.segment == h.segment);
          if (same.isNotEmpty) anchor = same.first;
        }
        if (anchor != null)
          canvas.drawLine(p, _screen(anchor.position, size), line);
      }
      final chosen = active?.segment == h.segment && active?.point == h.point;
      canvas.drawCircle(
        p,
        chosen ? 7 : 5,
        Paint()
          ..color = h.control
              ? const Color(0xffffb300)
              : const Color(0xff009688),
      );
      canvas.drawCircle(
        p,
        chosen ? 7 : 5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SvgSelectionPainter oldDelegate) => true;
}
