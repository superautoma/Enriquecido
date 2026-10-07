part of 'main_quill_integrated_test.dart';

const ownToolCodePrefix = 'GH1:';

String newOwnToolCode() {
  final random = math.Random.secure();
  return ownToolCodePrefix + List.generate(16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

bool isOwnToolCode(String value) => value.startsWith(ownToolCodePrefix);

List<String> detectedToolCodes(Iterable<String?> values) => values
  .whereType<String>().map((value) => value.trim()).where((value) => value.isNotEmpty)
  .toSet().toList();

// Codes are opaque strings: leading zeros and letter case identify the code.
List<ToolItem> toolsMatchingCode(Iterable<ToolItem> tools, String value) {
  final code = value.trim();
  if (code.isEmpty) return [];
  return tools.where((tool) => tool.barcode.trim() == code || tool.labelCode == code).toList();
}

Future<void> ensureToolCodeColumns(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(tools)');
  if (!columns.any((column) => column['name'] == 'label_code')) {
    await db.execute("ALTER TABLE tools ADD COLUMN label_code TEXT NOT NULL DEFAULT ''");
  }
  await db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_tool_label_code "
    "ON tools(label_code) WHERE label_code <> ''");
}

Future<String> ensureOwnToolLabel(int toolId) async {
  final db = await ToolsDatabase.instance.database;
  return db.transaction((txn) async {
    final rows = await txn.query('tools', columns: ['label_code'], where: 'id=?', whereArgs: [toolId]);
    if (rows.isEmpty) throw StateError('Guarda primero la herramienta.');
    final existing = rows.single['label_code'] as String;
    if (existing.isNotEmpty) return existing;
    final code = newOwnToolCode();
    await txn.update('tools', {'label_code': code}, where: 'id=?', whereArgs: [toolId]);
    return code;
  });
}

Future<String?> readToolCode(BuildContext context) => Navigator.of(context).push<String>(
  MaterialPageRoute(builder: (_) => const ToolCodeScannerPage()));

class ToolCodeScannerPage extends StatefulWidget {
  const ToolCodeScannerPage({super.key});
  @override
  State<ToolCodeScannerPage> createState() => _ToolCodeScannerPageState();
}

class _ToolCodeScannerPageState extends State<ToolCodeScannerPage> {
  final _controller = ms.MobileScannerController(detectionSpeed: ms.DetectionSpeed.noDuplicates);
  bool _handling = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resume() async {
    if (!mounted) return;
    _handling = false;
    try { await _controller.start(); } catch (_) { /* The preview displays the permission/camera error. */ }
  }

  Future<void> _detected(ms.BarcodeCapture capture) async {
    if (_handling || !mounted) return;
    final codes = detectedToolCodes(capture.barcodes.map((barcode) => barcode.rawValue));
    if (codes.isEmpty) return;
    _handling = true;
    try { await _controller.stop(); } catch (_) { /* Still-image reading works without camera permission. */ }
    if (!mounted) return;
    String? code = codes.length == 1 ? codes.single : await showModalBottomSheet<String>(
      context: context, useSafeArea: true, builder: (context) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .5, child: Column(children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Elige el código que quieres leer')),
          Expanded(child: ListView(children: codes.map((value) => ListTile(title: Text(value),
            onTap: () => Navigator.pop(context, value))).toList())),
        ]))));
    if (!mounted) return;
    if (code != null) { Navigator.pop(context, code); } else { await _resume(); }
  }

  Future<void> _manual() async {
    if (_handling) return;
    _handling = true;
    try { await _controller.stop(); } catch (_) { /* Camera may be unavailable. */ }
    if (!mounted) return;
    final input = TextEditingController();
    final code = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Introducir código'),
      content: TextField(controller: input, autofocus: true, key: const ValueKey('scan_manual_code'),
        decoration: const InputDecoration(labelText: 'Código de barras o QR'),
        onSubmitted: (value) { if (value.trim().isNotEmpty) Navigator.pop(context, value.trim()); }),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () { if (input.text.trim().isNotEmpty) Navigator.pop(context, input.text.trim()); },
          child: const Text('Usar código'))]));
    // The dialog route can still be animating out with the field attached.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    input.dispose();
    if (!mounted) return;
    if (code != null) { Navigator.pop(context, code); } else { await _resume(); }
  }

  Future<void> _image() async {
    if (_handling) return;
    _handling = true;
    try { await _controller.stop(); } catch (_) { /* Gallery works when camera permission is denied. */ }
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (!mounted) return;
      if (image != null) {
        final capture = await _controller.analyzeImage(image.path);
        if (!mounted) return;
        if (capture != null && detectedToolCodes(capture.barcodes.map((b) => b.rawValue)).isNotEmpty) {
          _handling = false;
          await _detected(capture);
          return;
        }
        _message('No se encontró un código legible en la imagen. Prueba con otra foto.');
      }
    } catch (_) {
      _message('No se pudo leer la imagen. Prueba con otra foto o introduce el código.');
    }
    await _resume();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Leer código'), actions: [
      ValueListenableBuilder<ms.MobileScannerState>(valueListenable: _controller,
        builder: (context, state, _) => IconButton(tooltip: 'Linterna',
          onPressed: state.torchState == ms.TorchState.unavailable ? null : () async {
            try { await _controller.toggleTorch(); } catch (_) { _message('La linterna no está disponible.'); }
          }, icon: Icon(state.torchState == ms.TorchState.on ? Icons.flash_on : Icons.flash_off))),
    ]),
    body: SafeArea(child: Column(children: [
      const Padding(padding: EdgeInsets.all(16), child: Text(
        'Apunta al código de barras o QR. Acércate hasta que se vea nítido.', textAlign: TextAlign.center)),
      Expanded(child: ColoredBox(color: Colors.black, child: ms.MobileScanner(
        controller: _controller, onDetect: _detected, tapToFocus: true,
        errorBuilder: (context, error) => Center(child: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white, size: 40),
            const SizedBox(height: 12),
            const Text('No se puede acceder a la cámara. Permite su uso en los ajustes de la aplicación '
              'o utiliza una imagen o la entrada manual.', style: TextStyle(color: Colors.white), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _resume, child: const Text('Reintentar')),
          ])))),
        overlayBuilder: (context, constraints) => IgnorePointer(child: Center(child: Container(
          width: constraints.maxWidth * .8, height: constraints.maxHeight * .55,
          decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 2),
            borderRadius: BorderRadius.circular(12))))),
      ))),
      Padding(padding: const EdgeInsets.all(12), child: Wrap(alignment: WrapAlignment.center,
        spacing: 12, runSpacing: 4, children: [
          TextButton.icon(onPressed: _image, icon: const Icon(Icons.image_outlined), label: const Text('Leer imagen')),
          TextButton.icon(onPressed: _manual, icon: const Icon(Icons.keyboard_outlined), label: const Text('Introducir código')),
        ])),
    ])),
  );
}

Future<Uint8List> toolLabelPdf(ToolItem tool) async {
  if (tool.labelCode.isEmpty) throw StateError('La herramienta no tiene etiqueta propia.');
  final document = pw.Document();
  document.addPage(pw.Page(pageFormat: pdf.PdfPageFormat(70 * pdf.PdfPageFormat.mm,
    50 * pdf.PdfPageFormat.mm, marginAll: 3 * pdf.PdfPageFormat.mm),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(tool.name, maxLines: 2, overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Expanded(child: pw.Row(children: [
        pw.Container(color: pdf.PdfColors.white, padding: const pw.EdgeInsets.all(6),
          child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: tool.labelCode,
            width: 27 * pdf.PdfPageFormat.mm, height: 27 * pdf.PdfPageFormat.mm, drawText: false)),
        pw.SizedBox(width: 6),
        pw.Expanded(child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('#${tool.id}', style: const pw.TextStyle(fontSize: 10)),
            if (tool.brand.isNotEmpty) pw.Text(tool.brand, maxLines: 2, style: const pw.TextStyle(fontSize: 8)),
            if (tool.serialNumber.isNotEmpty) pw.Text('Serie: ${tool.serialNumber}', maxLines: 2,
              style: const pw.TextStyle(fontSize: 8)),
          ])),
      ])),
    ])));
  return document.save();
}

class ToolLabelPage extends StatefulWidget {
  const ToolLabelPage({super.key, required this.tool});
  final ToolItem tool;
  @override
  State<ToolLabelPage> createState() => _ToolLabelPageState();
}

class _ToolLabelPageState extends State<ToolLabelPage> {
  bool _sharing = false;
  Future<void> _sharePdf() async {
    setState(() => _sharing = true);
    try {
      final directory = await getTemporaryDirectory();
      final file = File(p.join(directory.path, 'etiqueta_${widget.tool.id}.pdf'));
      await file.writeAsBytes(await toolLabelPdf(widget.tool), flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Etiqueta de ${widget.tool.name}',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo exportar la etiqueta: $error')));
    } finally { if (mounted) setState(() => _sharing = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Etiqueta QR propia')),
    body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
      Text(widget.tool.name, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 20),
      Center(child: Container(color: Colors.white, padding: const EdgeInsets.all(20), child: bw.BarcodeWidget(
        barcode: bw.Barcode.qrCode(), data: widget.tool.labelCode, width: 200, height: 200, drawText: false))),
      const SizedBox(height: 12),
      SelectableText(widget.tool.labelCode, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      const Text('Esta etiqueta identifica esta ficha. El código del fabricante se conserva por separado. '
        'Escanéala desde el listado para abrirla.', textAlign: TextAlign.center),
      const SizedBox(height: 20),
      Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 8, children: [
        OutlinedButton.icon(icon: const Icon(Icons.copy_outlined), label: const Text('Copiar código'), onPressed: () async {
          await Clipboard.setData(ClipboardData(text: widget.tool.labelCode));
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código copiado')));
        }),
        FilledButton.icon(onPressed: _sharing ? null : _sharePdf, icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Compartir PDF')),
      ]),
      const SizedBox(height: 12),
      const Text('Etiqueta de 70 × 50 mm. Imprime el PDF a tamaño real.', textAlign: TextAlign.center),
    ]))),
  );
}
