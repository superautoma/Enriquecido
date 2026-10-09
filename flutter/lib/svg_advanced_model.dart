part of 'svg_editor_model.dart';

const _advancedShapes = {
  'path',
  'rect',
  'circle',
  'ellipse',
  'line',
  'polygon',
  'polyline',
  'g',
};
String _av(double value) =>
    value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
String _matrixText(_Affine m) =>
    'matrix(${[m.a, m.b, m.c, m.d, m.e, m.f].map(_av).join(' ')})';
Offset _point(_Affine m, Offset p) =>
    Offset(m.a * p.dx + m.c * p.dy + m.e, m.b * p.dx + m.d * p.dy + m.f);
_Affine _inverse(_Affine m) {
  final det = m.a * m.d - m.b * m.c;
  if (det.abs() < 1e-12)
    _invalid(
      'La transformación es singular; no se puede editar en este espacio.',
    );
  return _Affine(
    m.d / det,
    -m.b / det,
    -m.c / det,
    m.a / det,
    (m.c * m.f - m.d * m.e) / det,
    (m.b * m.e - m.a * m.f) / det,
  );
}

Path _elementPath(XmlElement e) {
  double n(String k, [double fallback = 0]) =>
      e.getAttribute(k) == null ? fallback : _number(e.getAttribute(k)!);
  final path = Path();
  switch (e.name.local) {
    case 'path':
      final receiver = _SvgPath();
      writeSvgPathDataToPath(e.getAttribute('d'), receiver);
      if (_inheritPaint(e, 'fill-rule') == 'evenodd')
        receiver.path.fillType = PathFillType.evenOdd;
      return receiver.path;
    case 'rect':
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(n('x'), n('y'), n('width'), n('height')),
          Radius.elliptical(n('rx', n('ry')), n('ry', n('rx'))),
        ),
      );
    case 'circle':
      path.addOval(
        Rect.fromCircle(center: Offset(n('cx'), n('cy')), radius: n('r')),
      );
    case 'ellipse':
      path.addOval(
        Rect.fromCenter(
          center: Offset(n('cx'), n('cy')),
          width: 2 * n('rx'),
          height: 2 * n('ry'),
        ),
      );
    case 'line':
      path.moveTo(n('x1'), n('y1'));
      path.lineTo(n('x2'), n('y2'));
    case 'polygon':
    case 'polyline':
      final pts = _numbers(e.getAttribute('points') ?? '');
      if (pts.length >= 2) {
        path.moveTo(pts[0], pts[1]);
        for (var i = 2; i < pts.length; i += 2) {
          path.lineTo(pts[i], pts[i + 1]);
        }
        if (e.name.local == 'polygon') path.close();
      }
  }
  if (_inheritPaint(e, 'fill-rule') == 'evenodd')
    path.fillType = PathFillType.evenOdd;
  return path;
}

String? _ownPaint(XmlElement e, String name) {
  String? value = e.getAttribute(name);
  for (final part in (e.getAttribute('style') ?? '').split(';')) {
    final pair = part.split(':');
    if (pair.length == 2 && pair.first.trim() == name) value = pair.last.trim();
  }
  return value;
}

String? _inheritPaint(XmlElement e, String name) {
  XmlNode? p = e;
  while (p is XmlElement) {
    final value = _ownPaint(p, name);
    if (value != null) return value;
    p = p.parent;
  }
  return null;
}

class SvgVectorElement {
  const SvgVectorElement({
    required this.id,
    required this.type,
    required this.depth,
    required this.parentId,
    required this.hidden,
    required this.locked,
    required this.path,
    required this.bounds,
  });
  final String id, type;
  final String? parentId;
  final int depth;
  final bool hidden, locked;
  final Path path;
  final Rect bounds;
  String get label =>
      '${{'g': 'Grupo', 'rect': 'Rectángulo', 'circle': 'Círculo', 'ellipse': 'Elipse', 'line': 'Línea', 'polygon': 'Polígono', 'polyline': 'Polilínea', 'path': 'Trazado'}[type] ?? type} · ${id.replaceFirst('gestor_element_', '')}';
}

class SvgVectorHandle {
  const SvgVectorHandle(this.segment, this.point, this.position, this.control);
  final int segment, point;
  final Offset position;
  final bool control;
}

class _VectorSegment {
  _VectorSegment(this.command, this.points);
  final String command;
  final List<Offset> points;
  _VectorSegment copy() => _VectorSegment(command, List.of(points));
}

class _VectorPath extends PathProxy {
  final segments = <_VectorSegment>[];
  @override
  void moveTo(double x, double y) =>
      segments.add(_VectorSegment('M', [Offset(x, y)]));
  @override
  void lineTo(double x, double y) =>
      segments.add(_VectorSegment('L', [Offset(x, y)]));
  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => segments.add(
    _VectorSegment('C', [Offset(x1, y1), Offset(x2, y2), Offset(x3, y3)]),
  );
  @override
  void close() => segments.add(_VectorSegment('Z', []));
  String get data => segments
      .map(
        (s) =>
            '${s.command}${s.points.map((p) => '${_av(p.dx)} ${_av(p.dy)}').join(' ')}',
      )
      .join(' ');
}

/// Mutations are validated against the same import/rendering limits before commit.
/// XML snapshots keep arbitrary original attribute spelling and unedited path data.
class SvgVectorDocument {
  SvgVectorDocument(String source) : original = source {
    final xml = validateSvgSource(source);
    final ids = <String>{};
    for (final e in xml.descendants.whereType<XmlElement>()) {
      final id = e.getAttribute('id');
      if (id != null && !ids.add(id))
        _invalid('Hay identificadores repetidos; el original se conserva.');
    }
    var serial = 1;
    for (final e in xml.descendants.whereType<XmlElement>().where(
      (e) => _advancedShapes.contains(e.name.local),
    )) {
      if (e.getAttribute('id') == null) {
        String id;
        do {
          id = 'gestor_element_${serial++}';
        } while (ids.contains(id));
        e.setAttribute('id', id);
        ids.add(id);
      }
    }
    _source = xml.toXmlString();
    _initial = _source;
    _history.add(_source);
  }
  final String original;
  late String _source, _initial;
  final _history = <String>[];
  int _index = 0;
  String? _gesture;
  final selection = <String>{};
  int _nextId = 1;
  late final _originalElements = {
    for (final e
        in validateSvgSource(_initial).descendants
            .whereType<XmlElement>()
            .where((e) => e.getAttribute('id') != null))
      e.getAttribute('id')!: e,
  };
  String get source => _source;
  bool get dirty => _source != _initial;
  bool get canUndo => _gesture == null && _index > 0;
  bool get canRedo => _gesture == null && _index + 1 < _history.length;
  String? _cachedSource;
  XmlDocument? _cachedXml;
  List<SvgVectorElement>? _cachedElements;
  XmlDocument get _xml {
    if (_cachedSource != _source) {
      _cachedXml = validateSvgSource(_source);
      _cachedSource = _source;
      _cachedElements = null;
    }
    return _cachedXml!;
  }

  XmlElement _find(XmlDocument xml, String id) =>
      xml.descendants.whereType<XmlElement>().firstWhere(
        (e) => e.getAttribute('id') == id,
        orElse: () => throw const FormatException('El elemento ya no existe.'),
      );
  _Affine _world(XmlElement element, {bool includeSelf = true}) {
    final chain = <XmlElement>[];
    XmlNode? e = includeSelf ? element : element.parent;
    while (e is XmlElement) {
      chain.add(e);
      e = e.parent;
    }
    var matrix = const _Affine();
    for (final item in chain.reversed) {
      matrix = matrix.times(
        _Affine.parse(item.getAttribute('transform') ?? ''),
      );
    }
    return matrix;
  }

  bool _flag(XmlElement e, String name, String value) {
    XmlNode? p = e;
    while (p is XmlElement) {
      if (p.getAttribute(name) == value) return true;
      p = p.parent;
    }
    return false;
  }

  String? attribute(String id, String name) =>
      _inheritPaint(_find(_xml, id), name);
  List<SvgVectorElement> get elements {
    final xml = _xml;
    if (_cachedElements != null) return _cachedElements!;
    final result = <SvgVectorElement>[];
    void walk(XmlElement e, int depth, String? parent) {
      final id = e.getAttribute('id');
      if (_advancedShapes.contains(e.name.local)) {
        final path = Path();
        void geometry(XmlElement item) {
          if (item.name.local == 'g') {
            for (final child in item.childElements) {
              geometry(child);
            }
          } else if (_advancedShapes.contains(item.name.local)) {
            path.addPath(
              _elementPath(item).transform(_world(item).matrix),
              Offset.zero,
            );
          }
        }

        geometry(e);
        result.add(
          SvgVectorElement(
            id: id!,
            type: e.name.local,
            depth: depth,
            parentId: parent,
            hidden: _flag(e, 'display', 'none'),
            locked: _flag(e, 'data-gestor-locked', '1'),
            path: path,
            bounds: path.getBounds(),
          ),
        );
        parent = id;
        depth++;
      }
      for (final child in e.childElements) {
        walk(child, depth, parent);
      }
    }

    walk(xml.rootElement, 0, null);
    return _cachedElements = List.unmodifiable(result);
  }

  Rect get viewport {
    final root = _xml.rootElement;
    final box = root.getAttribute('viewBox');
    final n = box == null
        ? [
            0.0,
            0.0,
            _number(root.getAttribute('width') ?? '100'),
            _number(root.getAttribute('height') ?? '100'),
          ]
        : _numbers(box);
    return Rect.fromLTWH(n[0], n[1], n[2], n[3]);
  }

  Rect get visibleBounds {
    Rect? bounds;
    for (final e in elements.where((e) => e.type != 'g' && !e.hidden)) {
      bounds = bounds == null ? e.bounds : bounds.expandToInclude(e.bounds);
    }
    return bounds ?? viewport;
  }

  String? hitTest(Offset point, {double tolerance = 2}) {
    final xml = _xml;
    for (final e in elements.reversed.where(
      (e) => e.type != 'g' && !e.hidden && !e.locked,
    )) {
      final element = _find(xml, e.id);
      final width = _number(_inheritPaint(element, 'stroke-width') ?? '1');
      final radius = math.max(tolerance, width / 2);
      if (!e.bounds.inflate(radius).contains(point)) continue;
      final fill = _inheritPaint(element, 'fill') ?? 'black';
      if (e.type != 'line' &&
          fill != 'none' &&
          fill != 'transparent' &&
          e.path.contains(point))
        return e.id;
      if ((_inheritPaint(element, 'stroke') ?? 'none') == 'none' &&
          e.type != 'line')
        continue;
      for (final metric in e.path.computeMetrics()) {
        // Bounded sampling handles thin open paths without selecting an entire bbox.
        final count = (metric.length / math.max(tolerance, .01)).ceil().clamp(
          1,
          1000,
        );
        for (var i = 0; i <= count; i++) {
          final tangent = metric.getTangentForOffset(metric.length * i / count);
          if (tangent != null && (tangent.position - point).distance <= radius)
            return e.id;
        }
      }
    }
    return null;
  }

  void select(String? id, {bool additive = false}) {
    if (!additive) selection.clear();
    if (id == null) return;
    final e = elements.firstWhere((e) => e.id == id);
    if (e.locked) return;
    if (additive && selection.contains(id)) {
      selection.remove(id);
    } else {
      selection.add(id);
    }
  }

  void _prune() {
    final ids = elements.map((e) => e.id).toSet();
    selection.removeWhere((id) => !ids.contains(id));
  }

  void _push() {
    if (_history[_index] == _source) return;
    _history.removeRange(_index + 1, _history.length);
    _history.add(_source);
    _index++;
    while (_history.length > 101 ||
        (_history.length > 2 &&
            _history.fold<int>(0, (size, s) => size + utf8.encode(s).length) >
                8 * 1024 * 1024)) {
      _history.removeAt(0);
      _index--;
    }
  }

  void undo() {
    if (canUndo) {
      _source = _history[--_index];
      _prune();
    }
  }

  void redo() {
    if (canRedo) {
      _source = _history[++_index];
      _prune();
    }
  }

  void beginGesture() {
    if (_gesture != null) _invalid('Ya hay una operación en curso.');
    _gesture = _source;
  }

  void finishGesture({bool cancel = false}) {
    if (_gesture == null) return;
    if (cancel) _source = _gesture!;
    _gesture = null;
    if (!cancel) _push();
    _prune();
  }

  void _mutate(void Function(XmlDocument) operation, {bool record = true}) {
    final doc = _xml.copy();
    operation(doc);
    final next = doc.toXmlString();
    validateSvgSource(next);
    // Reject cumulative singular/oversized nested transforms before storing.
    for (final e in doc.descendants.whereType<XmlElement>().where(
      (e) => _advancedShapes.contains(e.name.local),
    )) {
      final m = _world(e);
      if ([
        m.a,
        m.b,
        m.c,
        m.d,
        m.e,
        m.f,
      ].any((n) => !n.isFinite || n.abs() > 100000))
        _invalid('Transformación acumulada fuera de límites.');
    }
    for (final e in doc.descendants.whereType<XmlElement>().where(
      (e) => _advancedShapes.contains(e.name.local) && e.name.local != 'g',
    )) {
      final b = _elementPath(e).transform(_world(e).matrix).getBounds();
      if ([
        b.left,
        b.top,
        b.right,
        b.bottom,
      ].any((v) => !v.isFinite || v.abs() > 100000))
        _invalid('La forma queda fuera de los límites del editor.');
    }
    _source = next;
    if (record && _gesture == null) _push();
    _prune();
  }

  List<XmlElement> _selected(XmlDocument doc) {
    final chosen = selection.map((id) => _find(doc, id)).toList();
    return chosen.where((e) {
      if (e.descendants.whereType<XmlElement>().any(
        (c) => _flag(c, 'data-gestor-locked', '1'),
      ))
        _invalid('El grupo contiene elementos bloqueados.');
      if (_flag(e, 'data-gestor-locked', '1'))
        _invalid('Desbloquea el elemento antes de modificarlo.');
      XmlNode? p = e.parent;
      while (p is XmlElement) {
        if (chosen.contains(p)) return false;
        p = p.parent;
      }
      return true;
    }).toList();
  }

  void transformSelection({
    double dx = 0,
    double dy = 0,
    double rotation = 0,
    double sx = 1,
    double sy = 1,
    bool record = true,
  }) {
    if ([dx, dy, rotation, sx, sy].any((v) => !v.isFinite) ||
        sx <= 0 ||
        sy <= 0 ||
        sx > 10 ||
        sy > 10 ||
        rotation.abs() > 360)
      _invalid('Transformación no válida.');
    final chosen = elements.where((e) => selection.contains(e.id)).toList();
    if (chosen.isEmpty) return;
    Rect bounds = chosen.first.bounds;
    for (final e in chosen.skip(1)) {
      bounds = bounds.expandToInclude(e.bounds);
    }
    final c = bounds.center;
    final r = rotation * math.pi / 180;
    final delta = _Affine(1, 0, 0, 1, dx + c.dx, dy + c.dy)
        .times(_Affine(math.cos(r), math.sin(r), -math.sin(r), math.cos(r)))
        .times(_Affine(sx, 0, 0, sy))
        .times(_Affine(1, 0, 0, 1, -c.dx, -c.dy));
    _mutate((doc) {
      for (final e in _selected(doc)) {
        final parent = _world(e, includeSelf: false);
        final matrix = _inverse(parent)
            .times(delta)
            .times(parent)
            .times(_Affine.parse(e.getAttribute('transform') ?? ''));
        e.setAttribute('transform', _matrixText(matrix));
      }
    }, record: record);
  }

  void paintSelection(String property, String? value) {
    if (!{'fill', 'stroke', 'stroke-width'}.contains(property))
      _invalid('Propiedad no editable.');
    if (value != null) _validatePaint(property, value);
    if (property == 'stroke-width' && value != null && _number(value) > 20)
      _invalid('El grosor permitido es de 0 a 20.');
    _mutate((doc) {
      for (final e in _selected(doc)) {
        final targets = e.name.local == 'g'
            ? [
                e,
                ...e.descendants.whereType<XmlElement>().where(
                  (c) => _advancedShapes.contains(c.name.local),
                ),
              ]
            : [e];
        if (targets.any((e) => _flag(e, 'data-gestor-locked', '1')))
          _invalid('El grupo contiene elementos bloqueados.');
        for (final target in targets) {
          final styles = (target.getAttribute('style') ?? '')
              .split(';')
              .where(
                (s) =>
                    s.trim().isNotEmpty &&
                    s.split(':').first.trim() != property,
              )
              .join(';');
          if (styles.isEmpty) {
            target.removeAttribute('style');
          } else {
            target.setAttribute('style', styles);
          }
          if (value == null) {
            final original = _originalElements[target.getAttribute('id')];
            final restored = original == null
                ? null
                : _inheritPaint(original, property) ??
                      (property == 'fill'
                          ? 'black'
                          : property == 'stroke'
                          ? 'none'
                          : '1');
            if (restored == null) {
              target.removeAttribute(property);
            } else {
              target.setAttribute(property, restored);
            }
          } else {
            target.setAttribute(property, value);
          }
        }
      }
    });
  }

  String _fresh(XmlDocument doc) {
    final ids = doc.descendants
        .whereType<XmlElement>()
        .map((e) => e.getAttribute('id'))
        .toSet();
    String id;
    do {
      id = 'gestor_element_${_nextId++}';
    } while (ids.contains(id) || _originalElements.containsKey(id));
    return id;
  }

  String create(String type) {
    if (!{
      'rect',
      'circle',
      'ellipse',
      'line',
      'polygon',
      'path',
    }.contains(type))
      _invalid('Forma no compatible.');
    late String id;
    _mutate((doc) {
      id = _fresh(doc);
      final e = XmlElement(XmlName.parts(type));
      e.setAttribute('id', id);
      e.setAttribute('fill', type == 'line' ? 'none' : '#009688');
      e.setAttribute('stroke', '#263238');
      e.setAttribute('stroke-width', '1');
      final v = viewport,
          c = v.center,
          size = math.min(v.width, v.height) * .25;
      final attrs = switch (type) {
        'rect' => {
          'x': _av(c.dx - size / 2),
          'y': _av(c.dy - size / 2),
          'width': _av(size),
          'height': _av(size),
        },
        'circle' => {'cx': _av(c.dx), 'cy': _av(c.dy), 'r': _av(size / 2)},
        'ellipse' => {
          'cx': _av(c.dx),
          'cy': _av(c.dy),
          'rx': _av(size / 2),
          'ry': _av(size / 3),
        },
        'line' => {
          'x1': _av(c.dx - size / 2),
          'y1': _av(c.dy),
          'x2': _av(c.dx + size / 2),
          'y2': _av(c.dy),
        },
        'polygon' => {
          'points':
              '${_av(c.dx)},${_av(c.dy - size / 2)} ${_av(c.dx + size / 2)},${_av(c.dy + size / 2)} ${_av(c.dx - size / 2)},${_av(c.dy + size / 2)}',
        },
        _ => {
          'd':
              'M ${_av(c.dx - size / 2)} ${_av(c.dy)} C ${_av(c.dx - size / 4)} ${_av(c.dy - size)} ${_av(c.dx + size / 4)} ${_av(c.dy + size)} ${_av(c.dx + size / 2)} ${_av(c.dy)}',
        },
      };
      for (final entry in attrs.entries) {
        e.setAttribute(entry.key, entry.value);
      }
      doc.rootElement.children.add(e);
    });
    select(id);
    return id;
  }

  void duplicate() {
    final newIds = <String>[];
    _mutate((doc) {
      for (final e in _selected(doc)) {
        final copy = e.copy();
        e.parent!.children.insert(e.parent!.children.indexOf(e) + 1, copy);
        for (final item in [
          copy,
          ...copy.descendants.whereType<XmlElement>(),
        ]) {
          if (item.getAttribute('id') != null) {
            final id = _fresh(doc);
            item.setAttribute('id', id);
            if (item == copy) newIds.add(id);
          }
        }
      }
    });
    selection
      ..clear()
      ..addAll(newIds);
  }

  void deleteSelection() => _mutate((doc) {
    for (final e in _selected(doc)) {
      if (e.descendants.whereType<XmlElement>().any(
        (c) => _flag(c, 'data-gestor-locked', '1'),
      ))
        _invalid('El grupo contiene elementos bloqueados.');
      e.parent!.children.remove(e);
    }
  });
  void reorder(bool forward) => _mutate((doc) {
    final selected = _selected(doc);
    final order = doc.descendants.whereType<XmlElement>().toList();
    selected.sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    final selectedIds = selected.map((e) => e.getAttribute('id')).toSet();
    // Move adjacent selected shapes as a block and ignore XML whitespace.
    final ordered = forward ? selected.reversed : selected;
    for (final e in ordered) {
      final siblings = e.parent!.children;
      final drawable = siblings
          .whereType<XmlElement>()
          .where((n) => _advancedShapes.contains(n.name.local))
          .toList();
      final i = drawable.indexOf(e);
      final next = forward ? i + 1 : i - 1;
      if (next >= 0 &&
          next < drawable.length &&
          !selectedIds.contains(drawable[next].getAttribute('id'))) {
        final target = drawable[next];
        siblings.remove(e);
        final index = siblings.indexOf(target);
        siblings.insert(forward ? index + 1 : index, e);
      }
    }
  });
  void toggleHidden(String id) => _mutate((doc) {
    final e = _find(doc, id);
    if (e.parent is XmlElement &&
        _flag(e.parent! as XmlElement, 'display', 'none'))
      _invalid('Muestra primero el grupo padre.');
    if (_flag(e, 'data-gestor-locked', '1'))
      _invalid('Desbloquea el elemento.');
    if (e.getAttribute('display') == 'none') {
      e.removeAttribute('display');
    } else {
      e.setAttribute('display', 'none');
    }
  });
  void toggleLocked(String id) => _mutate((doc) {
    final e = _find(doc, id);
    if (e.parent is XmlElement &&
        _flag(e.parent! as XmlElement, 'data-gestor-locked', '1'))
      _invalid('Desbloquea primero el grupo padre.');
    if (e.getAttribute('data-gestor-locked') == '1') {
      e.removeAttribute('data-gestor-locked');
    } else {
      e.setAttribute('data-gestor-locked', '1');
    }
  });
  void groupSelection() {
    String? id;
    _mutate((doc) {
      final list = _selected(doc);
      if (list.length < 2) _invalid('Selecciona al menos dos elementos.');
      final parent = list.first.parent!;
      list.sort(
        (a, b) =>
            parent.children.indexOf(a).compareTo(parent.children.indexOf(b)),
      );
      final drawable = parent.childElements
          .where((e) => _advancedShapes.contains(e.name.local))
          .toList();
      final positions = list.map(drawable.indexOf).toList();
      if (positions.last - positions.first + 1 != positions.length)
        _invalid('Selecciona formas consecutivas de la misma capa.');
      if (list.any((e) => e.parent != parent))
        _invalid('Agrupa elementos de la misma capa.');
      id = _fresh(doc);
      final group = XmlElement(XmlName.parts('g'));
      group.setAttribute('id', id);
      final index = parent.children.indexOf(list.first);
      for (final e in list) {
        parent.children.remove(e);
      }
      parent.children.insert(index, group);
      group.children.addAll(list);
    });
    select(id);
  }

  void ungroup() => _mutate((doc) {
    for (final group in _selected(doc)) {
      if (group.name.local != 'g') _invalid('Selecciona un grupo.');
      if (_number(_ownPaint(group, 'opacity') ?? '1') != 1)
        _invalid(
          'Este grupo usa opacidad compuesta: se conserva para evitar cambios de aspecto.',
        );
      final parent = group.parent!, index = parent.children.indexOf(group);
      final children = group.children.toList();
      final groupMatrix = _Affine.parse(group.getAttribute('transform') ?? '');
      for (final child in children.whereType<XmlElement>()) {
        if (!_advancedShapes.contains(child.name.local)) continue;
        child.setAttribute(
          'transform',
          _matrixText(
            groupMatrix.times(
              _Affine.parse(child.getAttribute('transform') ?? ''),
            ),
          ),
        );
        for (final property in _paint) {
          if (_ownPaint(child, property) == null &&
              _ownPaint(group, property) != null)
            child.setAttribute(property, _ownPaint(group, property)!);
        }
        if (group.getAttribute('display') == 'none')
          child.setAttribute('display', 'none');
      }
      group.children.clear();
      parent.children.remove(group);
      parent.children.insertAll(index, children);
    }
  });
  void align(String axis, {String? referenceId}) {
    final selected = elements.where((e) => selection.contains(e.id)).toList();
    if (selected.isEmpty) return;
    Rect box = selected.first.bounds;
    for (final e in selected.skip(1)) {
      box = box.expandToInclude(e.bounds);
    }
    final target = referenceId == null
        ? viewport
        : elements.firstWhere((e) => e.id == referenceId).bounds;
    final dx = switch (axis) {
      'left' => target.left - box.left,
      'right' => target.right - box.right,
      'horizontal' => target.center.dx - box.center.dx,
      _ => 0.0,
    };
    final dy = switch (axis) {
      'top' => target.top - box.top,
      'bottom' => target.bottom - box.bottom,
      'vertical' => target.center.dy - box.center.dy,
      _ => 0.0,
    };
    transformSelection(dx: dx, dy: dy);
  }

  bool nodesEditable(String id) {
    final e = _find(_xml, id);
    return (e.name.local == 'path' &&
            !RegExp('[Aa]').hasMatch(e.getAttribute('d') ?? '')) ||
        {'line', 'polyline', 'polygon'}.contains(e.name.local);
  }

  _VectorPath _nodes(XmlElement e) {
    final p = _VectorPath();
    if (e.name.local == 'path') {
      if (RegExp('[Aa]').hasMatch(e.getAttribute('d') ?? ''))
        _invalid('Los arcos se conservan: sus nodos no son editables.');
      writeSvgPathDataToPath(e.getAttribute('d'), p);
    } else if (e.name.local == 'line') {
      p.moveTo(
        _number(e.getAttribute('x1') ?? '0'),
        _number(e.getAttribute('y1') ?? '0'),
      );
      p.lineTo(
        _number(e.getAttribute('x2') ?? '0'),
        _number(e.getAttribute('y2') ?? '0'),
      );
    } else if ({'polygon', 'polyline'}.contains(e.name.local)) {
      final n = _numbers(e.getAttribute('points') ?? '');
      if (n.length >= 2) {
        p.moveTo(n[0], n[1]);
        for (var i = 2; i < n.length; i += 2) {
          p.lineTo(n[i], n[i + 1]);
        }
        if (e.name.local == 'polygon') p.close();
      }
    } else {
      _invalid(
        'Esta forma no tiene nodos editables; usa sus transformaciones.',
      );
    }
    return p;
  }

  List<SvgVectorHandle> handles(String id) {
    final e = _find(_xml, id);
    final m = _world(e);
    final segments = _nodes(e).segments;
    return [
      for (var i = 0; i < segments.length; i++)
        for (var j = 0; j < segments[i].points.length; j++)
          SvgVectorHandle(
            i,
            j,
            _point(m, segments[i].points[j]),
            segments[i].command == 'C' && j < 2,
          ),
    ];
  }

  void _setNodes(XmlElement e, _VectorPath nodes) {
    if (e.name.local == 'path') {
      e.setAttribute('d', nodes.data);
    } else if (e.name.local == 'line') {
      if (nodes.segments.length != 2) _invalid('Una línea tiene dos nodos.');
      final a = nodes.segments[0].points.single,
          b = nodes.segments[1].points.single;
      for (final a in {
        'x1': a.dx,
        'y1': a.dy,
        'x2': b.dx,
        'y2': b.dy,
      }.entries) {
        e.setAttribute(a.key, _av(a.value));
      }
    } else {
      e.setAttribute(
        'points',
        nodes.segments
            .where((s) => s.points.isNotEmpty)
            .map((s) => '${_av(s.points.last.dx)},${_av(s.points.last.dy)}')
            .join(' '),
      );
    }
  }

  void moveHandle(
    String id,
    int segment,
    int point,
    Offset world, {
    bool record = true,
  }) => _mutate((doc) {
    final e = _find(doc, id);
    if (_flag(e, 'data-gestor-locked', '1'))
      _invalid('Desbloquea el elemento.');
    final path = _nodes(e);
    final local = _point(_inverse(_world(e)), world);
    final s = path.segments[segment];
    final delta = local - s.points[point];
    s.points[point] = local;
    // Moving an anchor carries its adjoining control handles, preserving tangents.
    if (!(s.command == 'C' && point < 2)) {
      if (s.command == 'C') s.points[1] += delta;
      if (segment + 1 < path.segments.length &&
          path.segments[segment + 1].command == 'C')
        path.segments[segment + 1].points[0] += delta;
    }
    _setNodes(e, path);
  }, record: record);
  void insertNode(String id, int segment) => _mutate((doc) {
    final e = _find(doc, id);
    if (_flag(e, 'data-gestor-locked', '1'))
      _invalid('Desbloquea el elemento.');
    if (e.name.local == 'line')
      _invalid('Una línea conserva sus dos extremos.');
    final p = _nodes(e);
    if (segment <= 0 || segment >= p.segments.length)
      _invalid('Selecciona un segmento después del inicio.');
    final current = p.segments[segment], previous = p.segments[segment - 1];
    if (previous.points.isEmpty) _invalid('Selecciona un segmento continuo.');
    final a = previous.points.last;
    if (current.command == 'L') {
      p.segments.insert(
        segment,
        _VectorSegment('L', [(a + current.points.last) / 2]),
      );
    } else if (current.command == 'C') {
      final b = current.points[0], c = current.points[1], d = current.points[2];
      final ab = (a + b) / 2, bc = (b + c) / 2, cd = (c + d) / 2;
      final abc = (ab + bc) / 2, bcd = (bc + cd) / 2, mid = (abc + bcd) / 2;
      p.segments[segment] = _VectorSegment('C', [ab, abc, mid]);
      p.segments.insert(segment + 1, _VectorSegment('C', [bcd, cd, d]));
    } else {
      _invalid('Este segmento no admite inserción.');
    }
    _setNodes(e, p);
  });
  bool pathClosed(String id) {
    final e = _find(_xml, id);
    return e.name.local == 'path' &&
        RegExp(r'[Zz]\s*$').hasMatch(e.getAttribute('d') ?? '');
  }

  void toggleClosed(String id) => _mutate((doc) {
    final e = _find(doc, id);
    if (e.name.local != 'path') _invalid('Selecciona un trazado.');
    if (_flag(e, 'data-gestor-locked', '1'))
      _invalid('Desbloquea el elemento.');
    final nodes = _nodes(e);
    if (nodes.segments.where((s) => s.command == 'M').length != 1)
      _invalid('El cierre se edita en trazados de un solo contorno.');
    if (nodes.segments.last.command == 'Z') {
      nodes.segments.removeLast();
    } else {
      nodes.close();
    }
    _setNodes(e, nodes);
  });

  void deleteNode(String id, int segment) => _mutate((doc) {
    final e = _find(doc, id);
    if (_flag(e, 'data-gestor-locked', '1'))
      _invalid('Desbloquea el elemento.');
    if (e.name.local == 'line')
      _invalid('Una línea conserva sus dos extremos.');
    final p = _nodes(e);
    if (segment <= 0 ||
        segment >= p.segments.length ||
        p.segments[segment].points.isEmpty)
      _invalid('No se puede eliminar el inicio o el cierre.');
    final anchors = p.segments.where((s) => s.points.isNotEmpty).length;
    if (anchors <= 2 || (e.name.local == 'polygon' && anchors <= 3))
      _invalid('La forma necesita sus nodos mínimos.');
    p.segments.removeAt(segment);
    _setNodes(e, p);
  });
  String renderSource(Rect canvas) {
    final doc = _xml.copy();
    doc.rootElement.setAttribute(
      'viewBox',
      '${_av(canvas.left)} ${_av(canvas.top)} ${_av(canvas.width)} ${_av(canvas.height)}',
    );
    doc.rootElement.setAttribute('width', '100');
    doc.rootElement.setAttribute('height', '100');
    doc.rootElement.setAttribute('preserveAspectRatio', 'xMidYMid meet');
    return doc.toXmlString();
  }

  String export() {
    final doc = _xml.copy();
    var bounds = viewport;
    for (final e in elements.where((e) => e.type != 'g' && !e.hidden)) {
      final element = _find(doc, e.id);
      final stroke = _number(_inheritPaint(element, 'stroke-width') ?? '1');
      final miter = _number(_inheritPaint(element, 'stroke-miterlimit') ?? '4');
      final m = _world(element);
      final margin =
          stroke *
              .5 *
              miter *
              math.sqrt(m.a * m.a + m.b * m.b + m.c * m.c + m.d * m.d) +
          2;
      bounds = bounds.expandToInclude(e.bounds.inflate(margin));
    }
    final size = math.max(bounds.width, bounds.height), center = bounds.center;
    bounds = Rect.fromCenter(center: center, width: size, height: size);
    final root = doc.rootElement;
    root.setAttribute(
      'viewBox',
      '${_av(bounds.left)} ${_av(bounds.top)} ${_av(bounds.width)} ${_av(bounds.height)}',
    );
    root.setAttribute('width', '100');
    root.setAttribute('height', '100');
    root.setAttribute('preserveAspectRatio', 'xMidYMid meet');
    root.setAttribute('data-gestor-svg', '1');
    final output = doc.toXmlString();
    validateSvgSource(output);
    return output;
  }
}
