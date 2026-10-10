import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/app_security.dart';

void main() {
  testWidgets('El patrón registra puntos consecutivos y devuelve el recorrido', (tester) async {
    String? received;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: PatternPad(onComplete: (value) => received = value)))));
    final rect = tester.getRect(find.byType(PatternPad));
    // El widget está centrado: calcular los puntos de su lienzo de 248x248.
    final origin = Offset(rect.center.dx - 124, rect.center.dy - 124);
    Offset node(int row, int col) => origin + Offset((col + .5) * 248 / 3, (row + .5) * 248 / 3);
    final gesture = await tester.startGesture(node(0, 0));
    for (final point in [node(0, 1), node(0, 2), node(1, 2), node(2, 2)]) {
      await gesture.moveTo(point);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    expect(received, '01258');
  });

  testWidgets('No entrega patrones de menos de cuatro puntos', (tester) async {
    String? received;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: PatternPad(onComplete: (value) => received = value)))));
    final rect = tester.getRect(find.byType(PatternPad));
    final origin = Offset(rect.center.dx - 124, rect.center.dy - 124);
    final gesture = await tester.startGesture(origin + const Offset(42, 42));
    await gesture.moveTo(origin + const Offset(124, 42));
    await gesture.up();
    await tester.pump();
    expect(received, isNull);
  });
}
