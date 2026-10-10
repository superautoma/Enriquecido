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

  test('Instalaciones antiguas conservan la protección por defecto', () {
    expect(AppSecurityService.protectionFromStoredValue(true, null), isTrue);
    expect(AppSecurityService.protectionFromStoredValue(true, 'yes'), isTrue);
    expect(AppSecurityService.protectionFromStoredValue(true, 'no'), isFalse);
    expect(AppSecurityService.protectionFromStoredValue(false, 'yes'), isFalse);
  });

  test('El bloqueo manual se desactiva al pausar la protección', () async {
    final service = AppSecurityService.instance;
    final oldEnabled = service.enabled;
    final oldActive = service.protectionActive;
    final oldLocked = service.locked;
    final oldBackground = service.backgroundAt;
    final oldTimeout = service.lockAfterMinutes;
    try {
      service.enabled = true;
      service.protectionActive = false;
      service.locked = false;
      service.lock();
      expect(service.locked, isFalse);
      service.markBackground();
      expect(service.backgroundAt, isNull);
      service.backgroundAt = DateTime.now().subtract(const Duration(minutes: 20));
      await service.resumeFromBackground();
      expect(service.locked, isFalse);
      service.protectionActive = true;
      service.lock();
      expect(service.locked, isTrue);
    } finally {
      service.enabled = oldEnabled;
      service.protectionActive = oldActive;
      service.locked = oldLocked;
      service.backgroundAt = oldBackground;
      service.lockAfterMinutes = oldTimeout;
    }
  });
}
