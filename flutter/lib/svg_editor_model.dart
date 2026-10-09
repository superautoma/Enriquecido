import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:path_parsing/path_parsing.dart';
import 'package:xml/xml.dart';

part 'svg_advanced_model.dart';

// This module owns the supported SVG document. Phase 2 can add element commands
// without changing the storage keys or the global-edit history of phase 1.
const svgEditorMaxBytes = 512 * 1024;
const _svgNamespace = 'http://www.w3.org/2000/svg';
const _nodes = {
  'svg',
  'g',
  'path',
  'rect',
  'circle',
  'ellipse',
  'line',
  'polyline',
  'polygon',
  'title',
  'desc',
};
const _paint = {
  'fill',
  'stroke',
  'stroke-width',
  'stroke-linecap',
  'stroke-linejoin',
  'stroke-miterlimit',
  'fill-rule',
  'opacity',
  'fill-opacity',
  'stroke-opacity',
};
const _geometry = {
  'x',
  'y',
  'width',
  'height',
  'cx',
  'cy',
  'r',
  'rx',
  'ry',
  'x1',
  'y1',
  'x2',
  'y2',
};
final _numberPattern = RegExp(r'[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?');

Never _invalid(String message) => throw FormatException(message);
List<double> _numbers(String input) {
  final matches = _numberPattern.allMatches(input).toList();
  var end = 0;
  for (final match in matches) {
    if (!RegExp(r'^[\s,]*$').hasMatch(input.substring(end, match.start)))
      _invalid('Coordenadas SVG no compatibles.');
    end = match.end;
  }
  if (!RegExp(r'^[\s,]*$').hasMatch(input.substring(end)))
    _invalid('Coordenadas SVG no compatibles.');
  final values = matches.map((m) => double.parse(m[0]!)).toList();
  if (values.any((n) => !n.isFinite || n.abs() > 100000))
    _invalid('Geometría SVG fuera de los límites permitidos.');
  return values;
}

double _number(String input) {
  final values = _numbers(input);
  if (values.length != 1)
    _invalid('Se requiere una coordenada numérica sin unidades.');
  return values.single;
}

String? svgEditorHex(String input, {bool allowNone = true}) {
  final value = input.trim().toLowerCase();
  if (allowNone && value == 'none') return value;
  if (RegExp(r'^#[0-9a-f]{6}$').hasMatch(value)) return value;
  return null;
}

void _validatePaint(String name, String value) {
  if (name == 'fill' || name == 'stroke') {
    if (!RegExp(
      r'^(none|currentColor|transparent|[a-zA-Z]+|#[0-9a-fA-F]{3,8}|rgba?\([\d.,%\s]+\))$',
    ).hasMatch(value)) {
      _invalid('Color o referencia SVG no compatible.');
    }
  } else if (name == 'stroke-linecap') {
    if (!{'butt', 'round', 'square'}.contains(value))
      _invalid('Extremo de trazo no compatible.');
  } else if (name == 'stroke-linejoin') {
    if (!{'miter', 'round', 'bevel'}.contains(value))
      _invalid('Unión de trazo no compatible.');
  } else if (name == 'fill-rule') {
    if (!{'nonzero', 'evenodd'}.contains(value))
      _invalid('Relleno SVG no compatible.');
  } else {
    final n = _number(value);
    if (n < 0 ||
        (name.contains('opacity') && n > 1) ||
        (name == 'stroke-miterlimit' && n > 10))
      _invalid('Trazo u opacidad fuera de los límites.');
  }
}

// Checks run before parsing/rendering, including during import. No XML entity
// expansion, network, embedded images, CSS selectors or executable nodes.
XmlDocument validateSvgSource(String source) {
  if (utf8.encode(source).length > svgEditorMaxBytes)
    _invalid('El SVG supera 512 KiB.');
  if (RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(source))
    _invalid('DOCTYPE y entidades no están permitidos.');
  XmlDocument document;
  try {
    document = XmlDocument.parse(source);
  } catch (_) {
    _invalid('El SVG no es XML válido.');
  }
  final root = document.rootElement;
  if (root.name.local != 'svg' || root.name.prefix != null)
    _invalid('El documento debe ser un SVG.');
  var count = 0;
  var pathChars = 0;
  void visit(XmlElement element, int depth) {
    if (++count > 1500 || depth > 24)
      _invalid('El SVG contiene demasiados elementos o niveles.');
    if (!_nodes.contains(element.name.local) || element.name.prefix != null)
      _invalid(
        'Elemento ${element.name.local} no compatible con el editor básico.',
      );
    if (element != root && element.name.local == 'svg')
      _invalid('SVG anidado no compatible.');
    for (final node in element.children) {
      if (node is XmlProcessing || node is XmlCDATA)
        _invalid('Instrucciones XML no permitidas.');
      if (node is XmlText &&
          node.value.trim().isNotEmpty &&
          !{'title', 'desc'}.contains(element.name.local))
        _invalid('Texto gráfico no compatible.');
    }
    for (final a in element.attributes) {
      final name = a.name.qualified;
      final value = a.value;
      if (name == 'xmlns' && value == _svgNamespace) continue;
      if (a.name.prefix != null)
        _invalid('Atributos con espacio de nombres no compatibles.');
      if (name == 'id') {
        if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_.-]{0,100}$').hasMatch(value))
          _invalid('Identificador SVG no válido.');
      } else if (name == 'display' && {'none', 'inline'}.contains(value)) {
        continue;
      } else if (name == 'data-gestor-locked' && value == '1') {
        continue;
      } else if (name == 'data-gestor-svg' && element == root && value == '1') {
        continue;
      } else if (name == 'viewBox' && element == root) {
        final n = _numbers(value);
        if (n.length != 4 || n[2] <= 0 || n[3] <= 0)
          _invalid('viewBox no válido.');
      } else if (_geometry.contains(name)) {
        final n = _number(value);
        if ({'width', 'height', 'r', 'rx', 'ry'}.contains(name) && n < 0)
          _invalid('Dimensión SVG negativa.');
      } else if (name == 'd' && element.name.local == 'path') {
        pathChars += value.length;
        if (pathChars > 120000 ||
            _numberPattern.allMatches(value).length > 12000)
          _invalid('Trazado SVG demasiado complejo.');
        if (!RegExp(r'^[MmZzLlHhVvCcSsQqTtAa0-9eE.,\s+\-]*$').hasMatch(value))
          _invalid('Trazado SVG no compatible.');
        if (_numberPattern
            .allMatches(value)
            .any(
              (m) =>
                  !double.parse(m[0]!).isFinite ||
                  double.parse(m[0]!).abs() > 100000,
            ))
          _invalid('Trazado fuera de límites.');
        try {
          writeSvgPathDataToPath(value, _SvgPath());
        } catch (_) {
          _invalid('Trazado SVG no válido.');
        }
      } else if (name == 'points') {
        final n = _numbers(value);
        if (n.length > 12000 || n.length.isOdd)
          _invalid('Puntos SVG no válidos.');
      } else if (_paint.contains(name)) {
        _validatePaint(name, value);
      } else if (name == 'transform') {
        _Affine.parse(value);
      } else if (name == 'style') {
        for (final entry
            in value.split(';').where((s) => s.trim().isNotEmpty)) {
          final pair = entry.split(':');
          if (pair.length != 2 || !_paint.contains(pair[0].trim()))
            _invalid('CSS complejo no compatible.');
          _validatePaint(pair[0].trim(), pair[1].trim());
        }
      } else if (name == 'version' &&
          element == root &&
          {'1.0', '1.1'}.contains(value)) {
        continue;
      } else if (name == 'preserveAspectRatio' &&
          element == root &&
          {'xMidYMid meet', 'xMidYMid', 'none'}.contains(value)) {
        continue;
      } else {
        _invalid(
          'Atributo $name no compatible; no se ha modificado el archivo.',
        );
      }
    }
    for (final child in element.childElements) {
      visit(child, depth + 1);
    }
  }

  for (final node in document.children) {
    if (node is XmlDoctype || (node is XmlProcessing && node.target != 'xml'))
      _invalid('Instrucciones XML no permitidas.');
  }
  visit(root, 0);
  return document;
}

class _SvgPath extends PathProxy {
  final Path path = Path();
  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
  @override
  void lineTo(double x, double y) => path.lineTo(x, y);
  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);
  @override
  void close() => path.close();
}

class _Affine {
  const _Affine([
    this.a = 1,
    this.b = 0,
    this.c = 0,
    this.d = 1,
    this.e = 0,
    this.f = 0,
  ]);
  final double a, b, c, d, e, f;
  _Affine times(_Affine m) => _Affine(
    a * m.a + c * m.b,
    b * m.a + d * m.b,
    a * m.c + c * m.d,
    b * m.c + d * m.d,
    a * m.e + c * m.f + e,
    b * m.e + d * m.f + f,
  );
  Float64List get matrix =>
      Float64List.fromList([a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1]);
  static _Affine parse(String source) {
    var result = const _Affine();
    final pattern = RegExp(r'([a-zA-Z]+)\s*\(([^)]*)\)');
    var end = 0;
    var operations = 0;
    for (final m in pattern.allMatches(source)) {
      if (++operations > 16 ||
          !RegExp(r'^[\s,]*$').hasMatch(source.substring(end, m.start)))
        _invalid('Transformación SVG no compatible.');
      end = m.end;
      final n = _numbers(m[2]!);
      _Affine next;
      switch (m[1]) {
        case 'matrix':
          if (n.length != 6) _invalid('Matriz SVG no válida.');
          next = _Affine(n[0], n[1], n[2], n[3], n[4], n[5]);
        case 'translate':
          if (n.isEmpty || n.length > 2) _invalid('Posición SVG no válida.');
          next = _Affine(1, 0, 0, 1, n[0], n.length == 2 ? n[1] : 0);
        case 'scale':
          if (n.isEmpty || n.length > 2) _invalid('Escala SVG no válida.');
          next = _Affine(n[0], 0, 0, n.length == 2 ? n[1] : n[0]);
        case 'rotate':
          if (n.length != 1 && n.length != 3)
            _invalid('Rotación SVG no válida.');
          final r = n[0] * math.pi / 180, cs = math.cos(r), sn = math.sin(r);
          next = _Affine(cs, sn, -sn, cs);
          if (n.length == 3)
            next = _Affine(
              1,
              0,
              0,
              1,
              n[1],
              n[2],
            ).times(next).times(_Affine(1, 0, 0, 1, -n[1], -n[2]));
        default:
          _invalid('Transformación ${m[1]} no compatible.');
      }
      result = result.times(next);
      if ([
        result.a,
        result.b,
        result.c,
        result.d,
        result.e,
        result.f,
      ].any((v) => !v.isFinite || v.abs() > 100000))
        _invalid('Transformación fuera de límites.');
    }
    if (!RegExp(r'^[\s,]*$').hasMatch(source.substring(end)))
      _invalid('Transformación SVG no válida.');
    return result;
  }
}

class SvgEdits {
  const SvgEdits({
    this.fill,
    this.stroke,
    this.strokeWidth,
    this.background,
    this.scale = 1,
    this.x = 0,
    this.y = 0,
    this.rotation = 0,
    this.fit = false,
  });
  final String? fill, stroke;
  final String? background;
  final double? strokeWidth;
  final double scale, x, y, rotation;
  final bool fit;
  SvgEdits copyWith({
    String? fill,
    String? stroke,
    double? strokeWidth,
    String? background,
    double? scale,
    double? x,
    double? y,
    double? rotation,
    bool? fit,
    bool clearFill = false,
    bool clearStroke = false,
    bool clearBackground = false,
  }) => SvgEdits(
    fill: clearFill ? null : fill ?? this.fill,
    stroke: clearStroke ? null : stroke ?? this.stroke,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    background: clearBackground ? null : background ?? this.background,
    scale: scale ?? this.scale,
    x: x ?? this.x,
    y: y ?? this.y,
    rotation: rotation ?? this.rotation,
    fit: fit ?? this.fit,
  );
}

class SvgEditHistory {
  final List<SvgEdits> _states = [const SvgEdits()];
  int _index = 0;
  SvgEdits get current => _states[_index];
  bool get canUndo => _index > 0;
  bool get canRedo => _index + 1 < _states.length;
  void push(SvgEdits state) {
    _states.removeRange(_index + 1, _states.length);
    _states.add(state);
    _index++;
    if (_states.length > 101) {
      _states.removeAt(0);
      _index--;
    }
  }

  void undo() {
    if (canUndo) _index--;
  }

  void redo() {
    if (canRedo) _index++;
  }

  void reset() => push(const SvgEdits());
}

class SvgEditorDocument {
  SvgEditorDocument._(this.original, this._xml);
  factory SvgEditorDocument.parse(String source) =>
      SvgEditorDocument._(source, validateSvgSource(source));
  final String original;
  final XmlDocument _xml;
  bool get multicolor {
    final colors = <String>{};
    for (final e in _xml.descendants.whereType<XmlElement>()) {
      for (final key in ['fill', 'stroke']) {
        final value = e.getAttribute(key);
        if (value != null && value != 'none') colors.add(value);
      }
      for (final entry in (e.getAttribute('style') ?? '').split(';')) {
        final pair = entry.split(':');
        if (pair.length == 2 &&
            {'fill', 'stroke'}.contains(pair[0].trim()) &&
            pair[1].trim() != 'none') {
          colors.add(pair[1].trim());
        }
      }
    }
    return colors.length > 1;
  }

  String export(SvgEdits edits) {
    if (edits.scale < .1 ||
        edits.scale > 3 ||
        edits.x.abs() > 100 ||
        edits.y.abs() > 100 ||
        edits.rotation.abs() > 180 ||
        [
          edits.scale,
          edits.x,
          edits.y,
          edits.rotation,
        ].any((v) => !v.isFinite) ||
        (edits.strokeWidth != null &&
            (!edits.strokeWidth!.isFinite ||
                edits.strokeWidth! < 0 ||
                edits.strokeWidth! > 20)))
      _invalid('Ajustes fuera de los límites.');
    for (final c in [edits.fill, edits.stroke, edits.background]) {
      if (c != null && svgEditorHex(c) == null)
        _invalid('Utiliza #RRGGBB o none.');
    }
    final root = _xml.rootElement.copy();
    // Normalize supported inline CSS before edits so its precedence stays clear.
    for (final e in [root, ...root.descendants.whereType<XmlElement>()]) {
      final style = e.getAttribute('style');
      if (style != null) {
        for (final item in style.split(';').where((s) => s.trim().isNotEmpty)) {
          final pair = item.split(':');
          e.setAttribute(pair[0].trim(), pair[1].trim());
        }
        e.removeAttribute('style');
      }
      var background = false;
      XmlNode? ancestor = e;
      while (ancestor is XmlElement) {
        if (ancestor.getAttribute('id') == 'fondo' ||
            ancestor.getAttribute('id') == 'svg_editor_background')
          background = true;
        ancestor = ancestor.parent;
      }
      if (!background &&
          !{'svg', 'g', 'title', 'desc'}.contains(e.name.local)) {
        if (edits.fill != null) e.setAttribute('fill', edits.fill);
        if (edits.stroke != null) e.setAttribute('stroke', edits.stroke);
        if (edits.strokeWidth != null)
          e.setAttribute('stroke-width', '${edits.strokeWidth}');
      }
    }
    // Editor-generated backgrounds stay on the canvas when a saved copy is
    // reopened. Do not include them in art bounds or transform them again.
    String? previousBackground;
    for (final element
        in root.descendants
            .whereType<XmlElement>()
            .where(
              (e) =>
                  e.name.local == 'circle' &&
                  e.getAttribute('id') == 'svg_editor_background',
            )
            .toList()) {
      previousBackground ??= element.getAttribute('fill');
      element.parent?.children.remove(element);
    }
    final outputBackground = edits.background ?? previousBackground;
    final v = root.getAttribute('viewBox');
    final values = v == null
        ? [
            0.0,
            0.0,
            _number(root.getAttribute('width') ?? '100'),
            _number(root.getAttribute('height') ?? '100'),
          ]
        : _numbers(v);
    final viewport = Rect.fromLTWH(values[0], values[1], values[2], values[3]);
    if (viewport.width <= 0 || viewport.height <= 0)
      _invalid('El SVG no tiene un tamaño válido.');
    final content = XmlElement(XmlName.parts('g'));
    // Root inherited paint/transform belongs to the drawing, not the new canvas.
    for (final a in root.attributes.toList()) {
      if (_paint.contains(a.name.local) || a.name.local == 'transform') {
        content.setAttribute(a.name.local, a.value);
        root.removeAttribute(a.name.local);
      }
    }
    content.children.addAll(root.children.map((n) => n.copy()).toList());
    root.children.clear();
    Rect? bounds;
    void walk(
      XmlElement e,
      _Affine parent,
      double inheritedStroke,
      double inheritedMiter,
    ) {
      final matrix = parent.times(
        _Affine.parse(e.getAttribute('transform') ?? ''),
      );
      final stroke = e.getAttribute('stroke-width') == null
          ? inheritedStroke
          : _number(e.getAttribute('stroke-width')!);
      final miter = e.getAttribute('stroke-miterlimit') == null
          ? inheritedMiter
          : _number(e.getAttribute('stroke-miterlimit')!);
      final path = Path();
      double n(String key, [double fallback = 0]) => e.getAttribute(key) == null
          ? fallback
          : _number(e.getAttribute(key)!);
      switch (e.name.local) {
        case 'path':
          final proxy = _SvgPath();
          writeSvgPathDataToPath(e.getAttribute('d'), proxy);
          path.addPath(proxy.path, Offset.zero);
        case 'rect':
          path.addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(n('x'), n('y'), n('width'), n('height')),
              Radius.elliptical(n('rx'), n('ry', n('rx'))),
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
          final points = _numbers(e.getAttribute('points') ?? '');
          if (points.length >= 2) {
            path.moveTo(points[0], points[1]);
            for (var i = 2; i < points.length; i += 2) {
              path.lineTo(points[i], points[i + 1]);
            }
            if (e.name.local == 'polygon') path.close();
          }
      }
      if (!{'g', 'title', 'desc'}.contains(e.name.local)) {
        final raw = path.getBounds();
        // Conservative allowance includes miter joins, transformed strokes and
        // Bézier control bounds; overestimating is safer than clipping artwork.
        final allowance =
            stroke *
            .5 *
            miter *
            math.sqrt(
              matrix.a * matrix.a +
                  matrix.b * matrix.b +
                  matrix.c * matrix.c +
                  matrix.d * matrix.d,
            );
        final b = path.transform(matrix.matrix).getBounds().inflate(allowance);
        if (raw.width > 0 || raw.height > 0)
          bounds = bounds == null ? b : bounds!.expandToInclude(b);
      }
      for (final child in e.childElements) {
        walk(child, matrix, stroke, miter);
      }
    }

    walk(content, const _Affine(), 1, 4);
    if (bounds == null)
      _invalid('El SVG no contiene formas editables visibles.');
    final b = bounds!;
    if ([
      b.left,
      b.top,
      b.right,
      b.bottom,
    ].any((v) => !v.isFinite || v.abs() > 10000000))
      _invalid('Dibujo fuera de los límites permitidos.');
    final base = edits.fit
        ? 80 / math.max(b.width, b.height)
        : 100 / math.max(viewport.width, viewport.height);
    final center = edits.fit ? b.center : viewport.center;
    final r = edits.rotation * math.pi / 180;
    final scale = base * edits.scale;
    final transform = _Affine(1, 0, 0, 1, 50 + edits.x, 50 + edits.y)
        .times(_Affine(math.cos(r), math.sin(r), -math.sin(r), math.cos(r)))
        .times(_Affine(scale, 0, 0, scale))
        .times(_Affine(1, 0, 0, 1, -center.dx, -center.dy));
    final wrapper = XmlElement(
      XmlName.parts('g'),
      [
        XmlAttribute(
          XmlName.parts('transform'),
          'matrix(${transform.a} ${transform.b} ${transform.c} ${transform.d} ${transform.e} ${transform.f})',
        ),
      ],
      [content],
    );
    final boxPath = Path()..addRect(b);
    final transformed = boxPath.transform(transform.matrix).getBounds();
    final canvas = const Rect.fromLTWH(
      0,
      0,
      100,
      100,
    ).expandToInclude(transformed.inflate(2));
    final side = math.max(canvas.width, canvas.height);
    final output = Rect.fromCenter(
      center: canvas.center,
      width: side,
      height: side,
    );
    root.setAttribute('xmlns', _svgNamespace);
    root.setAttribute(
      'viewBox',
      '${output.left} ${output.top} ${output.width} ${output.height}',
    );
    root.setAttribute('width', '100');
    root.setAttribute('height', '100');
    root.setAttribute('preserveAspectRatio', 'xMidYMid meet');
    root.setAttribute('data-gestor-svg', '1');
    if (edits.background != null) {
      for (final element
          in content.descendants
              .whereType<XmlElement>()
              .where((e) => e.getAttribute('id') == 'svg_editor_background')
              .toList()) {
        element.parent?.children.remove(element);
      }
    }
    if (outputBackground != null && outputBackground != 'none')
      root.children.add(
        XmlElement(XmlName.parts('circle'), [
          XmlAttribute(XmlName.parts('id'), 'svg_editor_background'),
          XmlAttribute(XmlName.parts('cx'), '${output.center.dx}'),
          XmlAttribute(XmlName.parts('cy'), '${output.center.dy}'),
          XmlAttribute(XmlName.parts('r'), '${side * .49}'),
          XmlAttribute(XmlName.parts('fill'), outputBackground),
        ]),
      );
    root.children.add(wrapper);
    final result = root.toXmlString();
    validateSvgSource(result);
    return result;
  }
}
