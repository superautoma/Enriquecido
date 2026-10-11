part of 'main_quill_integrated_test.dart';

/// Sits above the Navigator: all routes and back navigation are blocked together.
/// The inventory subtree is not mounted until pending recovery has been checked.
class RestoreGate extends StatefulWidget {
  const RestoreGate({super.key, required this.child, this.testRecovery});
  final Widget child;

  /// Presentation tests inject a recovery result; release always uses real disk recovery.
  final Future<bool> Function()? testRecovery;
  @override
  State<RestoreGate> createState() => _RestoreGateState();
}

class _RestoreGateState extends State<RestoreGate> {
  bool _ready = false, _recovered = false, _checking = false;

  @override
  void initState() {
    super.initState();
    if (SafeRestore.readyWithoutNotice && widget.testRecovery == null) {
      _ready = true;
    } else {
      _check();
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final recovered = await (!kReleaseMode && widget.testRecovery != null
          ? widget.testRecovery!()
          : SafeRestore.ensureReady());
      if (mounted)
        setState(() {
          _ready = true;
          _recovered = recovered;
        });
    } catch (_) {
      // The global blocked state retains the recovery files and closes access.
      SafeRestore.status.value = const RestoreStatus(RestorePhase.blocked);
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<RestoreStatus>(
    valueListenable: SafeRestore.status,
    builder: (context, status, _) {
      final blocked = status.phase == RestorePhase.blocked;
      final overlay = !_ready || status.busy || blocked || _recovered;
      return PopScope(
        canPop: !overlay,
        child: Stack(
          children: [
            if (_ready)
              ExcludeFocus(
                excluding: overlay,
                child: ExcludeSemantics(
                  excluding: overlay,
                  child: AbsorbPointer(absorbing: overlay, child: widget.child),
                ),
              ),
            if (overlay)
              Positioned.fill(
                child: Scaffold(
                  backgroundColor: const Color(0xFFF7F9FB),
                  body: SafeArea(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (blocked)
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 48,
                                  color: Color(0xFF9A3412),
                                )
                              else if (_recovered)
                                const Icon(
                                  Icons.restore,
                                  size: 48,
                                  color: Color(0xFF168BD2),
                                )
                              else
                                const CircularProgressIndicator(),
                              const SizedBox(height: 24),
                              Text(
                                blocked
                                    ? 'No se pudo recuperar el inventario'
                                    : _recovered
                                    ? SafeRestore.recoveredMessage
                                    : status.phase == RestorePhase.idle
                                    ? 'Comprobando restauraciones pendientes'
                                    : status.label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (blocked) ...[
                                const Text(
                                  'No podemos confirmar que tus datos se hayan recuperado. '
                                  'Conserva los datos de la aplicación: no la desinstales ni borres su almacenamiento. '
                                  'Los archivos de recuperación se mantienen en el almacenamiento privado. '
                                  'Libera espacio fuera de la aplicación si es necesario y reintenta la recuperación.',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                FilledButton(
                                  onPressed: _check,
                                  child: const Text('Reintentar recuperación'),
                                ),
                              ] else if (_recovered)
                                FilledButton(
                                  onPressed: () async {
                                    await SafeRestore.acknowledgeRecovery();
                                    if (mounted)
                                      setState(() => _recovered = false);
                                  },
                                  child: const Text('Continuar'),
                                )
                              else if (status.phase != RestorePhase.idle &&
                                  status.phase != RestorePhase.recovering)
                                const Text(
                                  'Mantén la aplicación abierta. Tus datos anteriores se conservan hasta verificar el resultado.',
                                  textAlign: TextAlign.center,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
