part of 'main_quill_integrated_test.dart';

const inventorySortLabels = <InventorySort, String>{
  InventorySort.newest: 'Más recientes', InventorySort.name: 'Nombre A–Z',
  InventorySort.nameDescending: 'Nombre Z–A', InventorySort.quantity: 'Menor cantidad primero',
  InventorySort.price: 'Mayor precio primero'};
const inventoryViewLabels = <InventoryView, String>{InventoryView.cards: 'Tarjetas',
  InventoryView.compact: 'Lista compacta', InventoryView.grid: 'Cuadrícula'};
const inventoryViewIcons = <InventoryView, IconData>{InventoryView.cards: Icons.view_agenda_outlined,
  InventoryView.compact: Icons.view_list_outlined, InventoryView.grid: Icons.grid_view_outlined};

class InventoryFilterSheet extends StatefulWidget {
  const InventoryFilterSheet({super.key, required this.initial, required this.items,
    required this.facts, required this.conditionOptions, this.query = ''});
  final InventoryPreferences initial;
  final List<ToolItem> items;
  final InventoryFacts facts;
  final List<FieldOption> conditionOptions;
  final String query;
  @override
  State<InventoryFilterSheet> createState() => _InventoryFilterSheetState();
}

class _InventoryFilterSheetState extends State<InventoryFilterSheet> {
  late InventoryPreferences _value;
  @override
  void initState() { super.initState(); _value = widget.initial; }

  Widget _title(String text) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)));
  Widget _choices<T>(Map<T, String> choices, T selected, ValueChanged<T> onChanged) => Wrap(
    spacing: 8, runSpacing: 6, children: choices.entries.map((entry) => ChoiceChip(
      label: Text(entry.value), selected: entry.key == selected,
      onSelected: withControlFeedback((_) => setState(() => onChanged(entry.key))))).toList());
  Widget _multiple(List<String> choices, Set<String> selected, ValueChanged<Set<String>> onChanged) => Wrap(
    spacing: 8, runSpacing: 6, children: choices.map((label) => FilterChip(
      label: Text(label.isEmpty ? 'Sin indicar' : label), selected: selected.contains(label),
      onSelected: withControlFeedback((value) => setState(() {
        final next = {...selected};
        if (value) { next.add(label); } else { next.remove(label); }
        onChanged(next);
      })))).toList());

  @override
  Widget build(BuildContext context) {
    final types = {...widget.items.map((item) => item.type), ..._value.types}.toList()..sort();
    final conditions = {...widget.conditionOptions.map((option) => option.label), ..._value.conditions}.toList();
    final voltages = {...widget.items.map((item) => item.voltage), ..._value.voltages}.toList()
      ..sort((a, b) {
        double number(String s) => double.tryParse(RegExp(r'\d+(?:[.,]\d+)?')
          .firstMatch(s)?.group(0)?.replaceAll(',', '.') ?? '') ?? -1;
        return number(a).compareTo(number(b));
      });
    List<String> options(Iterable<String> values, Set<String> selected) => {...values, ...selected}.toList()
      ..sort((a, b) => inventorySearchText(a).compareTo(inventorySearchText(b)));
    final locations = widget.items.map(widget.facts.locationFor).toList();
    final sites = options(locations.map((l) => l.site), _value.sites);
    final racks = options(locations.map((l) => l.rack), _value.racks);
    final shelves = options(locations.map((l) => l.shelf), _value.shelves);
    final containers = options(locations.map((l) => l.container), _value.containers);
    final brands = options(widget.items.map((item) => item.brand), _value.brands);
    final count = selectInventoryTools(widget.items, _value, widget.facts, query: widget.query).length;
    return SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * .88,
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 4), child: Row(children: [
          const Expanded(child: Text('Filtrar y ordenar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          IconButton(tooltip: 'Cerrar filtros', onPressed: withButtonFeedback(() => Navigator.pop(context)), icon: const Icon(Icons.close))])),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
          Text('Puedes combinar filtros. $count resultados.'),
          _title('Ordenar por'),
          DropdownButtonFormField<InventorySort>(onTap: () => ButtonFeedbackController.instance.tap(), enableFeedback: false, initialValue: _value.sort, isExpanded: true,
            items: inventorySortLabels.entries.map((entry) => DropdownMenuItem(
              value: entry.key, child: Text(entry.value))).toList(),
            onChanged: withControlFeedback((value) => setState(() => _value = _value.copyWith(sort: value)))),
          _title('Disponibilidad'),
          _choices(const {InventoryAvailability.all: 'Todas', InventoryAvailability.available: 'Disponibles',
            InventoryAvailability.borrowed: 'Con préstamos', InventoryAvailability.overdue: 'Préstamo vencido',
            InventoryAvailability.outOfService: 'Fuera de servicio'}, _value.availability,
            (value) => _value = _value.copyWith(availability: value)),
          _title('Tipo · selección múltiple'),
          _multiple(types, _value.types, (value) => _value = _value.copyWith(types: value)),
          _title('Estado · selección múltiple'),
          _multiple(conditions, _value.conditions, (value) => _value = _value.copyWith(conditions: value)),
          _title('Tensión · selección múltiple'),
          _multiple(voltages, _value.voltages, (value) => _value = _value.copyWith(voltages: value)),
          _title('Lugar / taller'),
          _multiple(sites, _value.sites, (value) => _value = _value.copyWith(sites: value)),
          _title('Estantería'),
          _multiple(racks, _value.racks, (value) => _value = _value.copyWith(racks: value)),
          _title('Balda'),
          _multiple(shelves, _value.shelves, (value) => _value = _value.copyWith(shelves: value)),
          _title('Caja / maletín'),
          _multiple(containers, _value.containers, (value) => _value = _value.copyWith(containers: value)),
          _title('Marca'),
          _multiple(brands, _value.brands, (value) => _value = _value.copyWith(brands: value)),
          _title('Existencias'),
          _choices(const {InventoryStock.all: 'Todas', InventoryStock.low: 'Bajo mínimo',
            InventoryStock.empty: 'Sin existencias'}, _value.stock,
            (value) => _value = _value.copyWith(stock: value)),
          _title('Conjuntos y piezas'),
          _choices(const {InventoryContent.all: 'Todos', InventoryContent.sets: 'Conjuntos',
            InventoryContent.individual: 'Individuales', InventoryContent.pieces: 'Solo piezas'}, _value.content,
            (value) => _value = _value.copyWith(content: value)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Mostrar también las piezas'),
            subtitle: const Text('Incluye las fichas guardadas dentro de conjuntos.'),
            value: _value.includePieces, onChanged: withControlFeedback((value) => setState(() => _value = _value.copyWith(includePieces: value)))),
          _title('Mantenimiento'),
          _choices(const {InventoryMaintenance.all: 'Todos', InventoryMaintenance.pending: 'Pendiente',
            InventoryMaintenance.overdue: 'Vencido'}, _value.maintenance,
            (value) => _value = _value.copyWith(maintenance: value)),
          CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Con documentos'),
            value: _value.withDocuments, onChanged: withControlFeedback((value) => setState(() => _value = _value.copyWith(withDocuments: value)))),
          CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Con fotografías'),
            value: _value.withPhotos, onChanged: withControlFeedback((value) => setState(() => _value = _value.copyWith(withPhotos: value)))),
        ])),
        Padding(padding: const EdgeInsets.all(12), child: LayoutBuilder(builder: (context, constraints) {
          final clear = TextButton(onPressed: withButtonFeedback(() => setState(() => _value = _value.clearFilters())),
            child: const Text('Limpiar filtros'));
          final apply = FilledButton(onPressed: withButtonFeedback(() => Navigator.pop(context, _value)),
            child: Text('Ver $count resultados'));
          if (MediaQuery.textScalerOf(context).scale(14) > 20) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [apply, clear]);
          }
          return Row(children: [clear, const SizedBox(width: 8), Expanded(child: apply)]);
        })),
      ])));
  }
}

class InventoryToolTile extends StatelessWidget {
  const InventoryToolTile({super.key, required this.item, required this.facts,
    required this.conditionOptions, required this.onTap, this.view = InventoryView.cards});
  final ToolItem item;
  final InventoryFacts facts;
  final List<FieldOption> conditionOptions;
  final VoidCallback onTap;
  final InventoryView view;

  Widget _picture(double size) => Container(width: size, height: size,
    clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: const Color(0xFFEAF4FE),
      borderRadius: BorderRadius.circular(12)),
    child: item.imagePath.isNotEmpty && File(item.imagePath).existsSync() ?
      Image.file(File(item.imagePath), fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)) :
      Icon(item.isSet ? Icons.widgets_outlined : Icons.handyman_outlined,
        color: const Color(0xFF168BD2), size: size > 60 ? 42 : 26));

  @override
  Widget build(BuildContext context) {
    final compact = view == InventoryView.compact;
    final grid = view == InventoryView.grid;
    final borrowed = item.activeLoans.isNotEmpty || item.activeLoan != null;
    final style = optionForValue(conditionOptions, borrowed ? 'Prestado' : item.condition, fieldKey: 'condition');
    final blocked = facts.serviceBlocked(item);
    final overdue = item.activeLoans.any((loan) => loan.isOverdue) || (item.activeLoan?.isOverdue ?? false);
    final parent = facts.byId[item.parentId];
    final location = facts.locationFor(item);
    final identification = [item.brand, item.model].where((s) => s.isNotEmpty).join(' ');
    final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(item.name, maxLines: grid ? 3 : compact ? 2 : null, overflow: grid || compact ? TextOverflow.ellipsis : null,
        style: TextStyle(fontSize: compact ? 14 : 16, fontWeight: FontWeight.w800, color: const Color(0xFF25292D))),
      if (parent != null) Text('Pieza de ${parent.name}', maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: managementColor)),
      if (!compact && identification.isNotEmpty) Text(identification, maxLines: 1,
        overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: managementColor)),
      if (!location.isEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [
        const Icon(Icons.location_on_outlined, size: 14, color: managementColor), const SizedBox(width: 4),
        Expanded(child: Text(location.label, maxLines: grid ? 2 : 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: managementColor)))])),
      if (!compact && item.voltage.isNotEmpty) Text(item.voltage, style: const TextStyle(fontSize: 13, color: managementColor)),
      const SizedBox(height: 5),
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (blocked) Text(facts.ownServiceBlock(item) ? 'Fuera de servicio' : 'Pieza fuera de servicio',
          style: const TextStyle(color: Color(0xFFBF3434), fontSize: 12)),
        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: style.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            fieldOptionIconWidget(style, size: compact ? 18 : 22), const SizedBox(width: 4),
            Flexible(child: Text(style.label, style: TextStyle(color: style.color, fontWeight: FontWeight.w700, fontSize: 12)))])),
        Text('${compact || grid ? '' : 'Cantidad: '}${formatNumber(item.quantity)} ${item.unit}',
          style: const TextStyle(fontSize: 13, color: managementColor)),
      ]),
      if (borrowed) ...[
        const SizedBox(height: 4),
        Text('${formatNumber(item.availableQuantity ?? 0)} disponibles${overdue ? ' · Préstamo vencido' : ''}',
          maxLines: grid ? 2 : null, overflow: grid ? TextOverflow.ellipsis : null,
          style: TextStyle(fontSize: 12, color: overdue ? const Color(0xFFBF3434) : managementColor)),
        if (!compact && !grid) Text('Prestada a ${item.activeLoans.isNotEmpty ? item.activeLoans.map((loan) => loan.borrower).toSet().join(', ') : item.activeLoan!.borrower}',
          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFFB76E00))),
      ],
    ]);
    return Material(color: Colors.white, borderRadius: BorderRadius.circular(14),
      child: InkWell(enableFeedback: false, borderRadius: BorderRadius.circular(14), onTap: withButtonFeedback(onTap),
        child: Padding(padding: EdgeInsets.all(compact ? 10 : 12), child: grid ?
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: _picture(78)), const SizedBox(height: 10), details]) :
          Row(children: [_picture(compact ? 38 : 52), SizedBox(width: compact ? 10 : 12),
            Expanded(child: details), const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9AA0A6))]))));
  }
}

class InventoryResults extends StatelessWidget {
  const InventoryResults({super.key, required this.items, required this.view,
    required this.facts, required this.conditionOptions, required this.onOpen,
    required this.onRefresh, required this.onClear, this.hasFilters = false});
  final List<ToolItem> items;
  final InventoryView view;
  final InventoryFacts facts;
  final List<FieldOption> conditionOptions;
  final ValueChanged<ToolItem> onOpen;
  final Future<void> Function() onRefresh;
  final VoidCallback onClear;
  final bool hasFilters;
  @override
  Widget build(BuildContext context) {
    Widget tile(int index) => InventoryToolTile(item: items[index], facts: facts, view: view,
      conditionOptions: conditionOptions, onTap: withButtonFeedback(() => onOpen(items[index])));
    Widget results;
    if (items.isEmpty) {
      results = ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(24),
        children: [const SizedBox(height: 40), const Center(child: Text('No se encontraron herramientas')),
          if (hasFilters) Center(child: TextButton(onPressed: withButtonFeedback(onClear), child: const Text('Limpiar búsqueda y filtros')))]);
    } else if (view == InventoryView.grid) {
      results = LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = (constraints.maxWidth / (scale > 1.3 ? 300 : 175)).floor().clamp(1, 4).toInt();
        final rows = (items.length / columns).ceil();
        return ListView.separated(physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 92), itemCount: rows,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, row) => IntrinsicHeight(child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (var column = 0; column < columns; column++) ...[
              if (column > 0) const SizedBox(width: 8),
              Expanded(child: row * columns + column < items.length ?
                tile(row * columns + column) : const SizedBox()),
            ]])));
      });
    } else {
      results = ListView.separated(physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 92), itemCount: items.length,
        separatorBuilder: (_, _) => SizedBox(height: view == InventoryView.compact ? 4 : 8),
        itemBuilder: (_, index) => tile(index));
    }
    return RefreshIndicator(onRefresh: onRefresh, child: results);
  }
}
