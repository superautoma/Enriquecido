part of 'main_quill_integrated_test.dart';

class VisualInventoryResults extends StatefulWidget {
  const VisualInventoryResults({
    super.key,
    required this.source,
    required this.items,
    required this.eligibleItems,
    required this.engine,
    required this.onOpen,
    required this.onClose,
    this.picker,
  });
  final ImageSource source;
  final List<ToolItem> items, eligibleItems;
  final LocalVisualSearch engine;
  final void Function(ToolItem) onOpen;
  final VoidCallback onClose;
  final Future<XFile?> Function(ImageSource)? picker;
  @override
  State<VisualInventoryResults> createState() => _VisualInventoryResultsState();
}

class _VisualInventoryResultsState extends State<VisualInventoryResults> {
  VisualSearchReport? _report;
  String? _error, _queryPath;
  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    try {
      final photo =
          await (widget.picker?.call(widget.source) ??
              pickVisualQuery(widget.source));
      if (!mounted) return;
      if (photo == null) {
        widget.onClose();
        return;
      }
      setState(() => _queryPath = photo.path);
      final report = await widget.engine.search(
        photo.path,
        widget.items
            .where((item) => !item.isDeleted)
            .map(
              (item) => VisualCandidate(
                item.id,
                item.images.map((image) => image.path).toList(),
              ),
            )
            .toList(),
        cancelled: () => !mounted,
      );
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is FormatException
              ? '${error.message}'
              : visualPickerError(error),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final eligible = {for (final item in widget.eligibleItems) item.id: item};
    final matches =
        _report?.matches
            .where((match) => eligible.containsKey(match.id))
            .toList() ??
        [];
    final closeMatch = matches.isNotEmpty && matches.first.score >= .90;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (_queryPath != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Image.file(
                    File(_queryPath!),
                    width: 40,
                    height: 40,
                    cacheWidth: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
                ),
              const Expanded(
                child: Text(
                  'Similitud de fotografías · Solo en este dispositivo',
                ),
              ),
              IconButton(
                tooltip: 'Cerrar búsqueda visual',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
        else if (_report == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                LinearProgressIndicator(),
                SizedBox(height: 8),
                Text('Comparando fotografías locales…'),
              ],
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: math.min(matches.length, 20) + 1,
              itemBuilder: (context, index) {
                if (index == 0)
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _report!.comparablePhotos == 0
                          ? 'No hay imágenes comparables. Las fotografías ausentes, ilegibles o sin detalle se omiten.'
                          : matches.isEmpty
                          ? 'No hay resultados con la búsqueda y los filtros actuales.'
                          : '${closeMatch ? 'Fotografías visualmente próximas.' : 'No hay coincidencias fiables; se muestran las fotografías más próximas.'} '
                                'No identifica herramientas ni confirma su identidad. Fondo, ángulo y encuadre influyen.'
                                '${_report!.skippedPhotos > 0 ? ' ${_report!.skippedPhotos} fotos no comparables.' : ''}',
                    ),
                  );
                final match = matches[index - 1];
                final item = eligible[match.id]!;
                final parents = widget.items.where(
                  (tool) => tool.id == item.parentId,
                );
                final parent = parents.isEmpty ? null : parents.first;
                return ListTile(
                  key: ValueKey('visual_result_${item.id}'),
                  leading: Image.file(
                    File(match.path),
                    width: 56,
                    height: 56,
                    cacheWidth: 112,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    'Similitud visual: ${(match.score * 100).round()}/100'
                    '${item.parentId == null ? '' : '\nPieza de ${parent?.name ?? 'conjunto ${item.parentId}'}'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onOpen(item),
                );
              },
            ),
          ),
      ],
    );
  }
}
