import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:gestor_herramientas/svg_editor_model.dart';
import 'package:flutter_svg/flutter_svg.dart';

const advancedSource =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><g id="layer" transform="translate(5 10) rotate(20)"><rect id="red" x="10" y="10" width="20" height="15" fill="#ff0000"/><path id="curve" d="M 20 40 Q 40 10 60 40 T 90 40" fill="none" stroke="#0000ff"/></g><circle id="green" cx="70" cy="70" r="10" fill="#00ff00"/></svg>''';
XmlElement element(String source, String id) => XmlDocument.parse(source)
    .descendants
    .whereType<XmlElement>()
    .firstWhere((e) => e.getAttribute('id') == id);
void closeRect(Rect a, Rect b) {
  expect(a.left, closeTo(b.left, 1e-4));
  expect(a.top, closeTo(b.top, 1e-4));
  expect(a.right, closeTo(b.right, 1e-4));
  expect(a.bottom, closeTo(b.bottom, 1e-4));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Original path, multicolor and nested matrices round trip unchanged without edits',
    () async {
      final doc = SvgVectorDocument(advancedSource);
      expect(doc.dirty, isFalse);
      expect(doc.elements.length, 4);
      expect(
        element(doc.export(), 'curve').getAttribute('d'),
        element(advancedSource, 'curve').getAttribute('d'),
      );
      expect(element(doc.export(), 'red').getAttribute('fill'), '#ff0000');
      expect(
        element(doc.export(), 'layer').getAttribute('transform'),
        'translate(5 10) rotate(20)',
      );
      final reopened = SvgVectorDocument(doc.export());
      for (final e in doc.elements) {
        closeRect(
          reopened.elements.firstWhere((c) => c.id == e.id).bounds,
          e.bounds,
        );
      }
      await SvgStringLoader(doc.export()).loadBytes(null);
    },
  );
  test(
    'Per-element paint and world-space moves preserve other elements and group inheritance',
    () {
      final doc = SvgVectorDocument(advancedSource);
      final red = doc.elements.firstWhere((e) => e.id == 'red').bounds,
          green = doc.elements.last.bounds;
      doc.select('red');
      doc.transformSelection(dx: 7, dy: -3);
      closeRect(
        doc.elements.firstWhere((e) => e.id == 'red').bounds,
        red.shift(const Offset(7, -3)),
      );
      closeRect(doc.elements.last.bounds, green);
      doc.paintSelection('fill', '#abcdef');
      expect(element(doc.source, 'red').getAttribute('fill'), '#abcdef');
      expect(element(doc.source, 'green').getAttribute('fill'), '#00ff00');
      doc.paintSelection('fill', null);
      expect(doc.attribute('red', 'fill'), '#ff0000');
      doc.undo();
      expect(doc.attribute('red', 'fill'), '#abcdef');
      doc.redo();
      expect(doc.attribute('red', 'fill'), '#ff0000');
    },
  );
  test('Group and child selected together receive exactly one transform', () {
    final doc = SvgVectorDocument(advancedSource),
        before = SvgVectorDocument(advancedSource);
    doc.select('layer');
    doc.select('red', additive: true);
    doc.transformSelection(dx: 10);
    closeRect(
      doc.elements.firstWhere((e) => e.id == 'red').bounds,
      before.elements
          .firstWhere((e) => e.id == 'red')
          .bounds
          .shift(const Offset(10, 0)),
    );
  });
  test(
    'Create every supported shape, duplicate fresh ids, order, remove and undo',
    () async {
      final doc = SvgVectorDocument(advancedSource);
      for (final type in [
        'rect',
        'circle',
        'ellipse',
        'line',
        'polygon',
        'path',
      ]) {
        final id = doc.create(type);
        expect(doc.elements.last.id, id);
        expect(doc.elements.last.type, type);
      }
      final size = doc.elements.length;
      doc.duplicate();
      expect(doc.elements.length, size + 1);
      final ids = doc.elements.map((e) => e.id);
      expect(ids.toSet().length, ids.length);
      final copy = doc.selection.single;
      doc.reorder(false);
      expect(doc.elements.last.id, isNot(copy));
      doc.deleteSelection();
      expect(doc.elements.length, size);
      doc.undo();
      expect(doc.elements.length, size + 1);
      await SvgStringLoader(doc.export()).loadBytes(null);
    },
  );
  test(
    'Group and ungroup preserve exact world geometry and inherited color',
    () {
      final doc = SvgVectorDocument(advancedSource);
      doc.select('red');
      doc.select('curve', additive: true);
      final before = doc.elements
          .where((e) => e.id == 'red' || e.id == 'curve')
          .map((e) => e.bounds)
          .toList();
      doc.groupSelection();
      expect(doc.selection.length, 1);
      doc.transformSelection(rotation: 30, sx: 1.5, sy: .5);
      final transformed = doc.elements
          .where((e) => e.id == 'red' || e.id == 'curve')
          .map((e) => e.bounds)
          .toList();
      doc.ungroup();
      final after = doc.elements
          .where((e) => e.id == 'red' || e.id == 'curve')
          .toList();
      for (var i = 0; i < after.length; i++) {
        closeRect(after[i].bounds, transformed[i]);
      }
      expect(after.first.bounds, isNot(before.first));
      expect(doc.attribute('red', 'fill'), '#ff0000');
    },
  );
  test('Opacity-composited groups cannot be ungrouped silently', () {
    final doc = SvgVectorDocument(
      advancedSource.replaceAll('id="layer"', 'id="layer" opacity="0.5"'),
    );
    doc.select('layer');
    final before = doc.source;
    expect(doc.ungroup, throwsFormatException);
    expect(doc.source, before);
  });
  test(
    'Hidden and locked layers persist and blocked operations are atomic',
    () {
      final doc = SvgVectorDocument(advancedSource);
      doc.toggleHidden('layer');
      expect(doc.elements.firstWhere((e) => e.id == 'red').hidden, isTrue);
      doc.toggleHidden('layer');
      doc.toggleLocked('red');
      doc.select('layer');
      final before = doc.source;
      expect(() => doc.transformSelection(dx: 5), throwsFormatException);
      expect(doc.source, before);
      expect(doc.deleteSelection, throwsFormatException);
      doc.toggleLocked('red');
      doc.transformSelection(dx: 5);
      doc.toggleHidden('green');
      doc.toggleLocked('layer');
      final reopen = SvgVectorDocument(doc.export());
      expect(reopen.elements.last.hidden, isTrue);
      expect(reopen.elements.firstWhere((e) => e.id == 'curve').locked, isTrue);
    },
  );
  test(
    'Drag snapshots coalesce to one undo and cancellation restores every coordinate',
    () {
      final doc = SvgVectorDocument(advancedSource);
      doc.select('red');
      final before = doc.source;
      doc.beginGesture();
      for (var i = 0; i < 15; i++) {
        doc.transformSelection(dx: 1, record: false);
      }
      doc.finishGesture();
      expect(doc.canUndo, isTrue);
      doc.undo();
      expect(doc.source, before);
      expect(doc.canUndo, isFalse);
      doc.redo();
      final committed = doc.source;
      doc.beginGesture();
      doc.transformSelection(dy: 4, record: false);
      doc.finishGesture(cancel: true);
      expect(doc.source, committed);
    },
  );
  test(
    'Quadratic smooth paths normalize only on node edits with equivalent geometry',
    () {
      final doc = SvgVectorDocument(advancedSource);
      final before = doc.elements.firstWhere((e) => e.id == 'curve').bounds;
      final handles = doc.handles('curve');
      expect(element(doc.source, 'curve').getAttribute('d'), contains('Q'));
      final h = handles.last;
      doc.moveHandle('curve', h.segment, h.point, h.position);
      closeRect(doc.elements.firstWhere((e) => e.id == 'curve').bounds, before);
      expect(element(doc.source, 'curve').getAttribute('d'), contains('C'));
      expect(
        element(doc.source, 'curve').getAttribute('d'),
        isNot(contains('Q')),
      );
    },
  );
  test(
    'Cubic subdivision preserves curve geometry; moving world controls respects inverse transforms',
    () {
      final doc = SvgVectorDocument(advancedSource);
      final length = doc.elements
          .firstWhere((e) => e.id == 'curve')
          .path
          .computeMetrics()
          .fold<double>(0, (n, m) => n + m.length);
      final originalHandles = doc.handles('curve');
      doc.insertNode('curve', 1);
      final after = doc.elements.firstWhere((e) => e.id == 'curve');
      final splitHandles = doc.handles('curve');
      Offset cubic(Offset a, Offset b, Offset c, Offset d, double t) {
        final u = 1 - t;
        return a * (u * u * u) +
            b * (3 * u * u * t) +
            c * (3 * u * t * t) +
            d * (t * t * t);
      }

      final a = originalHandles[0].position,
          b = originalHandles[1].position,
          c = originalHandles[2].position,
          d = originalHandles[3].position;
      for (var i = 0; i <= 100; i++) {
        final t = i / 100.0;
        final expected = cubic(a, b, c, d, t);
        final actual = t <= .5
            ? cubic(
                splitHandles[0].position,
                splitHandles[1].position,
                splitHandles[2].position,
                splitHandles[3].position,
                t * 2,
              )
            : cubic(
                splitHandles[3].position,
                splitHandles[4].position,
                splitHandles[5].position,
                splitHandles[6].position,
                t * 2 - 1,
              );
        expect((actual - expected).distance, lessThan(1e-6));
      }
      expect(
        after.path.computeMetrics().fold<double>(0, (n, m) => n + m.length),
        closeTo(length, .2),
      );
      final h = doc.handles('curve').firstWhere((h) => h.control);
      final moved = h.position + const Offset(5, -7);
      doc.moveHandle('curve', h.segment, h.point, moved);
      final restored = doc
          .handles('curve')
          .firstWhere((n) => n.segment == h.segment && n.point == h.point);
      expect(restored.position.dx, closeTo(moved.dx, 1e-4));
      expect(restored.position.dy, closeTo(moved.dy, 1e-4));
    },
  );
  test(
    'Arcs stay verbatim and node conversion is refused without changing document',
    () {
      const d = 'M 10 10 A 15 20 30 0 1 70 70';
      final doc = SvgVectorDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path id="arc" d="$d"/></svg>',
      );
      expect(doc.nodesEditable('arc'), isFalse);
      expect(() => doc.handles('arc'), throwsFormatException);
      doc.select('arc');
      doc.transformSelection(dx: 5);
      expect(element(doc.export(), 'arc').getAttribute('d'), d);
    },
  );
  test(
    'Alignment and independent scaling use canvas and nested coordinate spaces',
    () {
      final doc = SvgVectorDocument(advancedSource);
      doc.select('red');
      doc.align('horizontal');
      expect(
        doc.elements.firstWhere((e) => e.id == 'red').bounds.center.dx,
        closeTo(50, 1e-4),
      );
      doc.align('vertical');
      expect(
        doc.elements.firstWhere((e) => e.id == 'red').bounds.center.dy,
        closeTo(50, 1e-4),
      );
      final before = doc.elements.firstWhere((e) => e.id == 'red').bounds;
      doc.transformSelection(sx: 2, sy: .5);
      final after = doc.elements.firstWhere((e) => e.id == 'red').bounds;
      expect(after.width, closeTo(before.width * 2, 1e-4));
      expect(after.height, closeTo(before.height * .5, 1e-4));
    },
  );
  test(
    'Hit testing picks frontmost shape, open strokes and skips hidden/locked items',
    () {
      final doc = SvgVectorDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect id="back" x="10" y="10" width="40" height="40"/><circle id="front" cx="30" cy="30" r="10"/><line id="wire" x1="60" y1="60" x2="90" y2="60" stroke="#000000"/></svg>',
      );
      expect(doc.hitTest(const Offset(30, 30)), 'front');
      doc.toggleHidden('front');
      expect(doc.hitTest(const Offset(30, 30)), 'back');
      doc.toggleLocked('back');
      expect(doc.hitTest(const Offset(30, 30)), isNull);
      expect(doc.hitTest(const Offset(75, 61), tolerance: 2), 'wire');
    },
  );
  test(
    'Export includes transformed stroke and inline styles without cropping',
    () {
      final doc = SvgVectorDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><line id="line" x1="0" y1="0" x2="80" y2="0" style="stroke:#000000;stroke-width:20"/></svg>',
      );
      doc.select('line');
      doc.transformSelection(dx: -40, dy: 130, rotation: 45);
      final exported = SvgVectorDocument(doc.export());
      final b = exported.elements.single.bounds;
      expect(exported.viewport.contains(b.topLeft), isTrue);
      expect(exported.viewport.contains(b.bottomRight), isTrue);
      expect(exported.viewport.top, lessThan(b.top - 10));
    },
  );
  test(
    'Duplicate ids, unsafe flags, singular transforms and invalid edits do not change originals',
    () {
      expect(
        () => SvgVectorDocument(
          advancedSource.replaceAll('id="green"', 'id="red"'),
        ),
        throwsFormatException,
      );
      expect(
        () => validateSvgSource(
          advancedSource.replaceAll(
            'id="green"',
            'id="green" data-gestor-locked="false"',
          ),
        ),
        throwsFormatException,
      );
      final doc = SvgVectorDocument(advancedSource);
      doc.select('red');
      final original = doc.source;
      expect(() => doc.transformSelection(dx: 1e8), throwsFormatException);
      expect(doc.source, original);
      expect(
        () => doc.paintSelection('stroke-width', '21'),
        throwsFormatException,
      );
      expect(doc.source, original);
      final singular = SvgVectorDocument(
        advancedSource.replaceAll('translate(5 10) rotate(20)', 'scale(0)'),
      );
      singular.select('red');
      expect(() => singular.transformSelection(dx: 1), throwsFormatException);
    },
  );
  test('Ordering ignores whitespace and moves multiselection as a block', () {
    final doc = SvgVectorDocument(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">\n<rect id="a" width="10" height="10"/>\n<rect id="b" width="10" height="10"/>\n<rect id="c" width="10" height="10"/>\n</svg>',
    );
    doc.select('b');
    doc.select('a', additive: true);
    doc.reorder(true);
    expect(doc.elements.map((e) => e.id), ['c', 'a', 'b']);
    doc.undo();
    expect(doc.elements.map((e) => e.id), ['a', 'b', 'c']);
    doc.select('b');
    doc.reorder(false);
    expect(doc.elements.map((e) => e.id), ['b', 'a', 'c']);
  });
  test(
    'New identities never reuse deleted original identities or restore their paint',
    () {
      final doc = SvgVectorDocument(
        advancedSource.replaceAll('id="red"', 'id="gestor_element_1"'),
      );
      doc.select('gestor_element_1');
      doc.deleteSelection();
      final id = doc.create('rect');
      expect(id, isNot('gestor_element_1'));
      doc.paintSelection('fill', null);
      expect(element(doc.source, id).getAttribute('fill'), isNull);
      doc.deleteSelection();
      expect(doc.create('rect'), isNot(id));
      doc.undo();
      doc.undo();
      expect(doc.elements.any((e) => e.id == id), isTrue);
    },
  );
  test(
    'Closing and opening a cubic contour is undoable and preserves other shapes',
    () {
      final doc = SvgVectorDocument(advancedSource);
      final original = doc.source;
      doc.toggleClosed('curve');
      expect(doc.pathClosed('curve'), isTrue);
      expect(
        element(doc.source, 'red').toXmlString(),
        element(original, 'red').toXmlString(),
      );
      doc.undo();
      expect(doc.source, original);
      doc.redo();
      doc.toggleClosed('curve');
      expect(doc.pathClosed('curve'), isFalse);
      final reopened = SvgVectorDocument(doc.export());
      expect(reopened.pathClosed('curve'), isFalse);
      expect(
        () => SvgVectorDocument(
          advancedSource.replaceAll(
            'M 20 40 Q 40 10 60 40 T 90 40',
            'M0 0L10 10M20 20L30 30',
          ),
        ).toggleClosed('curve'),
        throwsFormatException,
      );
    },
  );
  test(
    'Inherited lock and visibility cannot accidentally toggle a child flag',
    () {
      final doc = SvgVectorDocument(advancedSource);
      doc.toggleLocked('layer');
      final locked = doc.source;
      expect(() => doc.toggleLocked('red'), throwsFormatException);
      expect(doc.source, locked);
      doc.toggleLocked('layer');
      doc.toggleHidden('layer');
      final hidden = doc.source;
      expect(() => doc.toggleHidden('red'), throwsFormatException);
      expect(doc.source, hidden);
      doc.toggleHidden('layer');
      expect(doc.elements.where((e) => e.hidden || e.locked), isEmpty);
    },
  );
}
