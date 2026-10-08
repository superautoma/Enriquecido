part of 'main_quill_integrated_test.dart';

class ImportBackupPage extends StatefulWidget {
  const ImportBackupPage({super.key, this.initialPath});
  final String? initialPath;
  @override
  State<ImportBackupPage> createState() => _ImportBackupPageState();
}

class _ImportBackupPageState extends State<ImportBackupPage> {
  BackupImportPlan? _plan;
  BackupImportResult? _result;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) _prepare(widget.initialPath!);
  }
  @override
  void dispose() { _plan?.dispose(); super.dispose(); }

  Future<void> _select() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom,
        allowedExtensions: const ['zip'], allowMultiple: false);
      final path = picked?.files.single.path;
      if (path != null && mounted) await _prepare(path);
    } catch (error) { if (mounted) setState(() => _error = '$error'); }
  }
  Future<void> _prepare(String path) async {
    setState(() { _busy = true; _error = null; _result = null; });
    try {
      await _plan?.dispose(); _plan = null;
      final plan = await BackupImportPlan.prepare(path);
      if (!mounted) { await plan.dispose(); return; }
      setState(() => _plan = plan);
    } catch (error) { if (mounted) setState(() => _error = '$error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _import() async {
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _plan!.apply();
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = 'No se ha completado la importación. Tus datos anteriores se conservan.\n$error');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return PopScope(canPop: !_busy, child: Scaffold(
      appBar: AppBar(leading: Navigator.canPop(context) ? BackButton(onPressed: withButtonFeedback(() => Navigator.maybePop(context))) : null, title: const Text('Importar y añadir')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        const Icon(Icons.playlist_add_outlined, size: 44, color: managementColor),
        const SizedBox(height: 14),
        const Text('Añade herramientas a tu inventario', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        const SizedBox(height: 10),
        const Text('Tus fichas, fotografías, documentos, préstamos y ajustes actuales se conservan. '
          'Las fichas del ZIP se añaden como registros nuevos, con sus conjuntos e historial.'),
        const SizedBox(height: 18),
        if (_busy) ...[
          const LinearProgressIndicator(), const SizedBox(height: 12),
          Text(plan == null ? 'Comprobando el archivo…' : 'Añadiendo los datos…'),
        ] else if (_result != null) ...[
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 36),
          const SizedBox(height: 12), Text(_result!.summary), const SizedBox(height: 16),
          FilledButton(onPressed: withButtonFeedback(() => Navigator.pop(context, !_result!.alreadyImported)),
            child: const Text('Volver al listado')),
        ] else ...[
          if (plan != null) ...[
            Text(plan.fileName, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text('Actualmente: ${plan.existingTools} herramientas.\n'
              'Para añadir: ${plan.tools} herramientas y ${plan.pieces} piezas.\n'
              '${plan.count('tool_loans')} préstamos · ${plan.count('tool_documents')} documentos\n'
              '${plan.count('maintenance_tasks')} tareas de mantenimiento.'),
            if (plan.trashed > 0) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text('${plan.trashed} artículos del ZIP están eliminados y se añadirán a la papelera.')),
            if (plan.matchingReferences > 0) ...[
              const SizedBox(height: 12),
              Text('${plan.matchingReferences} referencias coinciden con las actuales. '
                'Se conservarán ambas fichas; la existente seguirá igual.'),
            ],
            const SizedBox(height: 16),
            if (plan.alreadyImported) const Text('Este ZIP ya se ha importado. No se volverán a añadir sus fichas.')
            else if (_error == null) FilledButton.icon(onPressed: withButtonFeedback(_import),
              icon: const Icon(Icons.playlist_add), label: const Text('Añadir a mi inventario')),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(onPressed: withButtonFeedback(_select), icon: const Icon(Icons.folder_open),
            label: Text(plan == null ? 'Seleccionar archivo ZIP' : 'Seleccionar otro ZIP')),
        ],
        if (_error != null) ...[const SizedBox(height: 16), Text(_error!, style: const TextStyle(color: Color(0xFFBF3434)))],
      ]))));
  }
}
