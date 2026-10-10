// Local, single-owner app access protection. No accounts or cloud services.
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AppSecurityService extends ChangeNotifier {
  AppSecurityService._();
  static final AppSecurityService instance = AppSecurityService._();
  static const _store = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  final _auth = LocalAuthentication();
  bool ready = false;
  bool enabled = false;
  bool locked = false;
  bool biometricEnabled = false;
  bool hasPin = false;
  bool hasPattern = false;
  String username = '';
  String? error;
  int lockAfterMinutes = 5;
  DateTime? backgroundAt;
  int _failures = 0;
  DateTime? _blockedUntil;

  Future<void> initialize() async {
    if (ready) return;
    try {
      // 'configured' is written last, after the first credentials are saved.
      enabled = (await _store.read(key: 'access_configured')) == 'yes';
      username = await _store.read(key: 'access_username') ?? '';
      hasPin = (await _store.read(key: 'access_pin')) != null;
      hasPattern = (await _store.read(key: 'access_pattern')) != null;
      biometricEnabled = (await _store.read(key: 'access_biometric')) == 'yes';
      lockAfterMinutes = int.tryParse(await _store.read(key: 'access_timeout') ?? '') ?? 5;
      _failures = int.tryParse(await _store.read(key: 'access_failures') ?? '') ?? 0;
      final block = int.tryParse(await _store.read(key: 'access_block_until') ?? '');
      _blockedUntil = block == null ? null : DateTime.fromMillisecondsSinceEpoch(block);
      locked = enabled;
    } catch (_) {
      // Never reveal the inventory if the configured secure vault is unreadable.
      error = 'No se pudo abrir el almacén seguro de Android. No se han borrado tus herramientas.';
      locked = true;
    }
    ready = true;
    notifyListeners();
  }

  static Future<String> _digest(String secret) async {
    final rand = Random.secure();
    final salt = List<int>.generate(16, (_) => rand.nextInt(256));
    final pbkdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 120000, bits: 256);
    final key = await pbkdf.deriveKeyFromPassword(password: secret, nonce: salt);
    return '${base64UrlEncode(salt)}.${base64UrlEncode(await key.extractBytes())}';
  }

  static Future<bool> _matches(String secret, String? encoded) async {
    if (encoded == null) return false;
    final parts = encoded.split('.');
    if (parts.length != 2) return false;
    try {
      final salt = base64Url.decode(base64Url.normalize(parts[0]));
      final wanted = base64Url.decode(base64Url.normalize(parts[1]));
      final pbkdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 120000, bits: 256);
      final key = await pbkdf.deriveKeyFromPassword(password: secret, nonce: salt);
      final actual = await key.extractBytes();
      if (actual.length != wanted.length) return false;
      var difference = 0;
      for (var i = 0; i < actual.length; i++) { difference |= actual[i] ^ wanted[i]; }
      return difference == 0;
    } catch (_) { return false; }
  }

  Future<void> configure(String user, String password) async {
    if (enabled) throw StateError('Ya hay un propietario configurado');
    if (user.trim().length < 3 || password.length < 10) {
      throw ArgumentError('Usuario de 3 caracteres y contraseña de al menos 10 caracteres');
    }
    final record = await _digest(password);
    await _store.write(key: 'access_username', value: user.trim());
    await _store.write(key: 'access_password', value: record);
    await _store.write(key: 'access_timeout', value: '5');
    await _store.write(key: 'access_configured', value: 'yes');
    username = user.trim();
    enabled = true;
    locked = false;
    notifyListeners();
  }

  String? get temporaryLockMessage {
    if (_blockedUntil == null || DateTime.now().isAfter(_blockedUntil!)) return null;
    final seconds = _blockedUntil!.difference(DateTime.now()).inSeconds + 1;
    return 'Demasiados intentos. Espera $seconds segundos.';
  }

  Future<bool> _verify(String key, String value, {bool applyRateLimit = true}) async {
    if (applyRateLimit && temporaryLockMessage != null) return false;
    final good = await _matches(value, await _store.read(key: key));
    if (!applyRateLimit) return good;
    if (good) {
      _failures = 0;
      _blockedUntil = null;
      await _store.delete(key: 'access_block_until');
    } else {
      _failures++;
      if (_failures >= 5) {
        _blockedUntil = DateTime.now().add(Duration(seconds: _failures >= 10 ? 300 : 30));
        await _store.write(key: 'access_block_until', value: _blockedUntil!.millisecondsSinceEpoch.toString());
      }
    }
    await _store.write(key: 'access_failures', value: _failures.toString());
    return good;
  }

  Future<bool> validatePassword(String password) => _verify('access_password', password);
  Future<bool> login(String user, String password) async {
    if (user.trim().toLowerCase() != username.toLowerCase()) {
      if (temporaryLockMessage == null) await _verify('access_password', '', applyRateLimit: true);
      return false;
    }
    final good = await validatePassword(password);
    if (good) unlock();
    return good;
  }
  Future<bool> unlockWithPin(String pin) async {
    if (!hasPin) return false;
    final good = await _verify('access_pin', pin);
    if (good) unlock();
    return good;
  }
  Future<bool> unlockWithPattern(String pattern) async {
    if (!hasPattern) return false;
    final good = await _verify('access_pattern', pattern);
    if (good) unlock();
    return good;
  }
  Future<bool> unlockWithBiometrics() async {
    if (!biometricEnabled || temporaryLockMessage != null) return false;
    try {
      final good = await _auth.authenticate(
        localizedReason: 'Desbloquear Gestor de Herramientas',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (good) unlock();
      return good;
    } on PlatformException { return false; }
  }

  void unlock() {
    locked = false;
    backgroundAt = null;
    notifyListeners();
  }
  void lock() {
    if (!enabled) return;
    locked = true;
    notifyListeners();
  }
  Future<void> resumeFromBackground() async {
    final started = backgroundAt;
    backgroundAt = null;
    if (!enabled || started == null) return;
    if (lockAfterMinutes == 0 || DateTime.now().difference(started) >= Duration(minutes: lockAfterMinutes)) lock();
  }
  void markBackground() { if (enabled) backgroundAt ??= DateTime.now(); }

  Future<void> changePassword(String newPassword) async {
    if (newPassword.length < 10) throw ArgumentError('Mínimo 10 caracteres');
    await _store.write(key: 'access_password', value: await _digest(newPassword));
  }
  Future<void> savePin(String? pin) async {
    if (pin == null) {
      await _store.delete(key: 'access_pin');
    } else {
      if (!RegExp(r'^\d{6,}$').hasMatch(pin)) throw ArgumentError('El PIN debe tener al menos seis cifras');
      await _store.write(key: 'access_pin', value: await _digest(pin));
    }
    hasPin = pin != null;
    notifyListeners();
  }
  Future<void> savePattern(String? pattern) async {
    if (pattern == null) {
      await _store.delete(key: 'access_pattern');
    } else {
      if (pattern.length < 4 || pattern.split('').toSet().length != pattern.length ||
          !RegExp(r'^[0-8]+$').hasMatch(pattern)) throw ArgumentError('El patrón debe unir al menos cuatro puntos');
      await _store.write(key: 'access_pattern', value: await _digest(pattern));
    }
    hasPattern = pattern != null;
    notifyListeners();
  }
  Future<bool> canUseBiometrics() async {
    try { return await _auth.canCheckBiometrics && (await _auth.getAvailableBiometrics()).isNotEmpty; }
    on PlatformException { return false; }
  }
  Future<void> setBiometrics(bool active) async {
    if (active && !await canUseBiometrics()) throw StateError('El móvil no tiene biometría configurada');
    await _store.write(key: 'access_biometric', value: active ? 'yes' : 'no');
    biometricEnabled = active;
    notifyListeners();
  }
  Future<void> setTimeoutMinutes(int minutes) async {
    if (![0, 1, 5, 15].contains(minutes)) return;
    await _store.write(key: 'access_timeout', value: minutes.toString());
    lockAfterMinutes = minutes;
    notifyListeners();
  }
}

class AppSecurityGate extends StatefulWidget {
  const AppSecurityGate({super.key, required this.child});
  final Widget child;
  @override State<AppSecurityGate> createState() => _AppSecurityGateState();
}
class _AppSecurityGateState extends State<AppSecurityGate> with WidgetsBindingObserver {
  final security = AppSecurityService.instance;
  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    security.addListener(_refresh);
    security.initialize();
  }
  void _refresh() { if (mounted) setState(() {}); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) security.markBackground();
    if (state == AppLifecycleState.resumed) security.resumeFromBackground();
  }
  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    security.removeListener(_refresh);
    super.dispose();
  }
  @override Widget build(BuildContext context) {
    if (!security.ready) return const Material(child: Center(child: CircularProgressIndicator()));
    if (security.error != null) return Material(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(security.error!, textAlign: TextAlign.center))));
    return Stack(children: [
      Offstage(offstage: security.locked, child: widget.child),
      if (security.locked) const Positioned.fill(child: SecurityUnlockPage()),
    ]);
  }
}

class SecurityUnlockPage extends StatefulWidget {
  const SecurityUnlockPage({super.key});
  @override State<SecurityUnlockPage> createState() => _SecurityUnlockPageState();
}
class _SecurityUnlockPageState extends State<SecurityUnlockPage> {
  final user = TextEditingController();
  final pass = TextEditingController();
  final pin = TextEditingController();
  String method = 'password';
  bool busy = false;
  String message = '';
  @override void initState() { super.initState(); user.text = AppSecurityService.instance.username; }
  @override void dispose() { user.dispose(); pass.dispose(); pin.dispose(); super.dispose(); }
  Future<void> _submit([String? pattern]) async {
    if (busy) return;
    setState(() { busy = true; message = ''; });
    try {
      final security = AppSecurityService.instance;
      final success = method == 'password'
          ? await security.login(user.text, pass.text)
          : method == 'pin' ? await security.unlockWithPin(pin.text)
          : await security.unlockWithPattern(pattern ?? '');
      if (mounted && !success) setState(() { message = security.temporaryLockMessage ?? 'Datos incorrectos'; });
    } catch (_) {
      if (mounted) setState(() { message = 'No se pudo verificar el acceso'; });
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) {
    final s = AppSecurityService.instance;
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.shield_outlined, size: 56, color: Color(0xFF168BD2)),
          const SizedBox(height: 12),
          const Text('Gestor de Herramientas', textAlign: TextAlign.center, style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Aplicación protegida', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Wrap(alignment: WrapAlignment.center, spacing: 7, children: [
            ChoiceChip(label: const Text('Contraseña'), selected: method == 'password', onSelected: (_) => setState(() { method = 'password'; message = ''; })),
            if (s.hasPin) ChoiceChip(label: const Text('PIN'), selected: method == 'pin', onSelected: (_) => setState(() { method = 'pin'; message = ''; })),
            if (s.hasPattern) ChoiceChip(label: const Text('Patrón'), selected: method == 'pattern', onSelected: (_) => setState(() { method = 'pattern'; message = ''; })),
          ]),
          const SizedBox(height: 12),
          if (method == 'password') ...[
            TextField(controller: user, decoration: const InputDecoration(labelText: 'Usuario'), textInputAction: TextInputAction.next),
            const SizedBox(height: 10),
            TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña'), onSubmitted: (_) => _submit()),
          ],
          if (method == 'pin') TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN'), onSubmitted: (_) => _submit()),
          if (method == 'pattern') Column(children: [const Text('Dibuja tu patrón'), PatternPad(onComplete: (value) => _submit(value))]),
          const SizedBox(height: 14),
          if (method != 'pattern') FilledButton(onPressed: busy ? null : _submit, child: const Text('Desbloquear')),
          if (s.biometricEnabled) OutlinedButton.icon(
            onPressed: busy ? null : () async {
              try {
                final good = await s.unlockWithBiometrics();
                if (!good && mounted) setState(() => message = s.temporaryLockMessage ?? 'No se ha autorizado la huella');
              } catch (_) { if (mounted) setState(() => message = 'No se pudo abrir el sensor'); }
            },
            icon: const Icon(Icons.fingerprint), label: const Text('Usar huella dactilar')),
          if (busy) const Center(child: CircularProgressIndicator()),
          if (message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 16),
          const Text('Si olvidas todos tus métodos, no hay recuperación por Internet. Conserva tu contraseña y tus copias de seguridad.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      )),
    ))));
  }
}

// A locally drawn 3x3 Android-style pattern. The selected sequence is never logged.
class PatternPad extends StatefulWidget {
  const PatternPad({super.key, required this.onComplete});
  final ValueChanged<String> onComplete;
  @override State<PatternPad> createState() => _PatternPadState();
}
class _PatternPadState extends State<PatternPad> {
  final List<int> selected = [];
  int _index(Offset position, Size size) {
    final cellW = size.width / 3;
    final cellH = size.height / 3;
    final x = (position.dx / cellW).floor();
    final y = (position.dy / cellH).floor();
    if (x < 0 || x > 2 || y < 0 || y > 2) return -1;
    final center = Offset((x + .5) * cellW, (y + .5) * cellH);
    if ((position - center).distance > min(cellW, cellH) * .42) return -1;
    return y * 3 + x;
  }
  void _accept(Offset position, Size size) {
    final next = _index(position, size);
    if (next < 0 || selected.contains(next)) return;
    if (selected.isNotEmpty) {
      final last = selected.last;
      final r0 = last ~/ 3, c0 = last % 3, r1 = next ~/ 3, c1 = next % 3;
      if ((r1-r0).abs() == 2 && (c1-c0).abs() != 1 || (c1-c0).abs() == 2 && (r1-r0).abs() != 1) {
        final mid = ((r0+r1) ~/ 2) * 3 + ((c0+c1) ~/ 2);
        if (!selected.contains(mid)) selected.add(mid);
      }
    }
    setState(() => selected.add(next));
  }
  @override Widget build(BuildContext context) => Center(child: SizedBox(
    width: 248, height: 248,
    child: LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return GestureDetector(behavior: HitTestBehavior.opaque,
        onPanDown: (d) { setState(selected.clear); _accept(d.localPosition, size); },
        onPanStart: (d) => _accept(d.localPosition, size),
        onPanUpdate: (d) => _accept(d.localPosition, size),
        onPanEnd: (_) {
          final value = selected.join();
          setState(selected.clear);
          if (value.length >= 4) widget.onComplete(value);
        },
        child: CustomPaint(painter: _PatternPainter(selected)));
    }),
  ));
}
class _PatternPainter extends CustomPainter {
  _PatternPainter(this.selected);
  final List<int> selected;
  @override void paint(Canvas canvas, Size size) {
    final line = Paint()..color = const Color(0xFF168BD2)..strokeWidth = 3..strokeCap = StrokeCap.round;
    Offset dot(int n) => Offset((n % 3 + .5) * size.width / 3, (n ~/ 3 + .5) * size.height / 3);
    for (var i = 1; i < selected.length; i++) { canvas.drawLine(dot(selected[i-1]), dot(selected[i]), line); }
    for (var i = 0; i < 9; i++) {
      canvas.drawCircle(dot(i), selected.contains(i) ? 10 : 8,
        Paint()..color = selected.contains(i) ? const Color(0xFF168BD2) : const Color(0xFFBEC9D4));
    }
  }
  @override bool shouldRepaint(_PatternPainter old) => true;
}

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});
  @override State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}
class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  final service = AppSecurityService.instance;
  final user = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool busy = false;
  @override void dispose() { user.dispose(); password.dispose(); confirm.dispose(); super.dispose(); }
  void _message(String message) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
  Future<void> _setup() async {
    if (password.text != confirm.text) { _message('Las contraseñas no coinciden'); return; }
    setState(() => busy = true);
    try {
      await service.configure(user.text, password.text);
      password.clear(); confirm.clear();
      _message('Protección activada. Configura PIN, patrón o huella si lo deseas.');
    } catch (e) { _message('No se pudo activar: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<bool> _authenticateOwner() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Confirmar contraseña'),
      content: TextField(controller: controller, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Contraseña del propietario')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Continuar'))],
    ));
    controller.dispose();
    if (value == null) return false;
    final good = await service.validatePassword(value);
    if (!good) _message(service.temporaryLockMessage ?? 'Contraseña incorrecta');
    return good;
  }
  Future<String?> _promptSecret(String title, {bool numeric = false}) async {
    final c = TextEditingController();
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, obscureText: true, autofocus: true,
        keyboardType: numeric ? TextInputType.number : TextInputType.visiblePassword,
        decoration: InputDecoration(labelText: numeric ? 'Mínimo 6 cifras' : 'Mínimo 10 caracteres')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Aceptar'))],
    ));
    c.dispose();
    return result;
  }
  Future<String?> _promptPattern(String title) => showDialog<String>(context: context,
    builder: (ctx) => AlertDialog(title: Text(title), content: Column(mainAxisSize: MainAxisSize.min,
      children: [const Text('Une al menos cuatro puntos'), PatternPad(onComplete: (value) => Navigator.pop(ctx, value))]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))]));
  Future<void> _setPin() async {
    if (!await _authenticateOwner() || !mounted) return;
    final first = await _promptSecret('Crear PIN', numeric: true);
    if (first == null || !mounted) return;
    final second = await _promptSecret('Repetir PIN', numeric: true);
    if (second == null || !mounted) return;
    if (first != second) { _message('Los PIN no coinciden'); return; }
    try { await service.savePin(first); _message('PIN guardado'); }
    catch (e) { _message('$e'); }
  }
  Future<void> _setPattern() async {
    if (!await _authenticateOwner() || !mounted) return;
    final first = await _promptPattern('Dibujar patrón');
    if (first == null || !mounted) return;
    final second = await _promptPattern('Repetir patrón');
    if (second == null || !mounted) return;
    if (first != second) { _message('Los patrones no coinciden'); return; }
    try { await service.savePattern(first); _message('Patrón guardado'); }
    catch (e) { _message('$e'); }
  }
  Future<void> _biometrics(bool enabled) async {
    if (!await _authenticateOwner()) return;
    try { await service.setBiometrics(enabled); _message(enabled ? 'Biometría activada' : 'Biometría desactivada'); }
    catch (e) { _message('$e'); }
  }
  Future<void> _changePassword() async {
    if (!await _authenticateOwner() || !mounted) return;
    final p = await _promptSecret('Nueva contraseña');
    if (p == null || !mounted) return;
    final c = await _promptSecret('Repetir nueva contraseña');
    if (c == null || !mounted) return;
    if (p != c) { _message('Las contraseñas no coinciden'); return; }
    try { await service.changePassword(p); _message('Contraseña actualizada'); }
    catch (e) { _message('$e'); }
  }
  Future<void> _remove(String which) async {
    if (!await _authenticateOwner()) return;
    if (which == 'pin') { await service.savePin(null); } else { await service.savePattern(null); }
    _message('Método eliminado');
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Seguridad y acceso')),
    body: ListenableBuilder(listenable: service, builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
      if (!service.enabled) ...[
        const Text('Proteger esta aplicación', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('Se configurará un solo propietario. Tus herramientas y fotografías no se modificarán.'),
        const SizedBox(height: 16),
        TextField(controller: user, decoration: const InputDecoration(labelText: 'Nombre de usuario')),
        const SizedBox(height: 12),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña (mínimo 10 caracteres)')),
        const SizedBox(height: 12),
        TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Repetir contraseña')),
        const SizedBox(height: 16),
        FilledButton(onPressed: busy ? null : _setup, child: const Text('Activar protección')),
        const SizedBox(height: 12),
        const Text('Importante: guarda tu contraseña. No existe recuperación mediante correo o servidor.', style: TextStyle(color: Colors.black54)),
      ] else ...[
        ListTile(leading: const Icon(Icons.person_outline), title: Text('Propietario: ${service.username}'), subtitle: const Text('Cuenta local de este dispositivo')),
        const Divider(),
        ListTile(leading: const Icon(Icons.key_outlined), title: const Text('Cambiar contraseña'), onTap: _changePassword),
        ListTile(leading: const Icon(Icons.pin_outlined), title: Text(service.hasPin ? 'Cambiar PIN' : 'Configurar PIN'), onTap: _setPin),
        if (service.hasPin) ListTile(leading: const Icon(Icons.remove_circle_outline), title: const Text('Quitar PIN'), onTap: () => _remove('pin')),
        ListTile(leading: const Icon(Icons.gesture_outlined), title: Text(service.hasPattern ? 'Cambiar patrón' : 'Configurar patrón'), onTap: _setPattern),
        if (service.hasPattern) ListTile(leading: const Icon(Icons.remove_circle_outline), title: const Text('Quitar patrón'), onTap: () => _remove('pattern')),
        SwitchListTile(secondary: const Icon(Icons.fingerprint), title: const Text('Huella dactilar'), subtitle: const Text('Si Android tiene una huella registrada'),
          value: service.biometricEnabled, onChanged: _biometrics),
        const Divider(),
        ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('Bloqueo al dejar la aplicación'),
          trailing: DropdownButton<int>(value: service.lockAfterMinutes,
            items: const [DropdownMenuItem(value: 0, child: Text('Inmediato')), DropdownMenuItem(value: 1, child: Text('1 minuto')),
              DropdownMenuItem(value: 5, child: Text('5 minutos')), DropdownMenuItem(value: 15, child: Text('15 minutos'))],
            onChanged: (v) { if (v != null) service.setTimeoutMinutes(v); })),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: service.lock, icon: const Icon(Icons.lock_outline), label: const Text('Bloquear ahora')),
        const SizedBox(height: 16),
        const Text('El bloqueo protege el acceso a la pantalla de la aplicación, pero no cifra todavía la base de datos ni las copias exportadas.',
          style: TextStyle(color: Colors.black54, fontSize: 12)),
      ],
    ])),
  );
}
