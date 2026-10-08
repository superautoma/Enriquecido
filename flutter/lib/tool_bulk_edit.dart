part of 'main_quill_integrated_test.dart';

const bulkToolFields = <String, String>{
  'name': 'Nombre',
  'description': 'Descripción',
  'tool_type': 'Tipo',
  'condition': 'Estado',
  'voltage': 'Tensión',
  'brand': 'Marca',
  'model': 'Modelo',
  'location_site': 'Lugar / taller',
  'location_rack': 'Estantería',
  'location_shelf': 'Balda',
  'location_container': 'Caja / maletín',
  'quantity': 'Cantidad',
  'unit': 'Unidad',
  'minimum_stock': 'Stock mínimo',
  'purchase_price': 'Precio de compra',
  'out_of_service': 'Fuera de servicio',
  'service_notes': 'Notas de servicio',
};
const bulkNumericFields = {'quantity', 'minimum_stock', 'purchase_price'};

void validateBulkToolChanges(Map<String, Object?> changes) {
  if (changes.isEmpty) {
    throw StateError('Marca al menos un campo para aplicar');
  }
  if (changes.keys.any(
        (key) => !bulkToolFields.containsKey(key) && key != 'description_delta',
      ) ||
      changes.containsKey('description') !=
          changes.containsKey('description_delta')) {
    throw StateError('Estos campos no admiten edición múltiple');
  }
  for (final entry in changes.entries) {
    if (bulkNumericFields.contains(entry.key)) {
      if (entry.value is! num ||
          !(entry.value as num).isFinite ||
          (entry.value as num) < 0) {
        throw StateError(
          '${bulkToolFields[entry.key]} debe ser un número mayor o igual a cero',
        );
      }
    } else if (entry.key == 'out_of_service') {
      if (entry.value != 0 && entry.value != 1) {
        throw StateError('Estado de servicio no válido');
      }
    } else if (entry.value is! String) {
      throw StateError('Valor no válido para ${bulkToolFields[entry.key]}');
    }
  }
  for (final key in ['name', 'unit', 'condition']) {
    if (changes.containsKey(key) && (changes[key] as String).trim().isEmpty) {
      throw StateError('${bulkToolFields[key]} no puede quedar vacío');
    }
  }
  if (changes.containsKey('condition') &&
      isLoanCondition(changes['condition'] as String)) {
    throw StateError(
      'Registra los préstamos desde la ficha de cada herramienta',
    );
  }
  if (changes.containsKey('description_delta')) {
    try {
      final document = Document.fromJson(
        jsonDecode(changes['description_delta'] as String) as List,
      );
      if (document.toPlainText().trimRight() !=
          (changes['description'] as String).trimRight()) {
        throw const FormatException('Descripción incoherente');
      }
    } catch (_) {
      throw StateError('El formato de la descripción no es válido');
    }
  }
}

extension BulkToolUpdates on ToolsDatabase {
  Future<void> updateToolsTogether(
    List<ToolItem> originals,
    Map<String, Object?> changes,
  ) async {
    if (originals.isEmpty ||
        originals.map((item) => item.id).toSet().length != originals.length) {
      throw StateError('Selecciona herramientas diferentes');
    }
    validateBulkToolChanges(changes);
    final db = await database;
    await db.transaction((txn) async {
      for (final original in originals) {
        final rows = await txn.query(
          'tools',
          where: 'id=?',
          whereArgs: [original.id],
        );
        if (rows.isEmpty || rows.single['deleted_at'] != '') {
          throw StateError(
            '${original.name} ya no está disponible. Actualiza la selección.',
          );
        }
        final current = rows.single;
        final before = original.toMap();
        for (final key in changes.keys) {
          if (current[key] != before[key]) {
            throw StateError(
              '${original.name} ha cambiado. Reabre la edición múltiple.',
            );
          }
        }
        final reserved = await reservedQuantity(txn, original.id);
        if (reserved > 0 &&
            ['condition', 'unit'].any(
              (key) => changes.containsKey(key) && changes[key] != current[key],
            )) {
          throw StateError(
            '${original.name} tiene préstamos activos. Conserva su estado y unidad.',
          );
        }
        if (changes.containsKey('quantity')) {
          final quantity = (changes['quantity'] as num).toDouble();
          if (quantity + 0.000001 < reserved) {
            throw StateError(
              '${original.name}: la cantidad no puede ser menor que las unidades prestadas',
            );
          }
          final pieces = await txn.query(
            'tools',
            columns: ['id'],
            where: "parent_id=? AND deleted_at=''",
            whereArgs: [original.id],
            limit: 1,
          );
          if (current['is_set'] == 1 && pieces.isNotEmpty && quantity != 1) {
            throw StateError(
              '${original.name}: un conjunto con piezas debe tener cantidad 1',
            );
          }
        }
        // Update chosen columns only; never replace rows or rewrite images/history.
        await txn.update(
          'tools',
          changes,
          where: 'id=?',
          whereArgs: [original.id],
        );
      }
    });
  }
}

class BulkEditToolsPage extends StatefulWidget {
  const BulkEditToolsPage({super.key, required this.items});
  final List<ToolItem> items;
  @override
  State<BulkEditToolsPage> createState() => _BulkEditToolsPageState();
}

class _BulkEditToolsPageState extends State<BulkEditToolsPage> {
  final _form = GlobalKey<FormState>();
  final _enabled = <String>{};
  final _controllers = <String, TextEditingController>{};
  bool _out = false, _busy = false;
  String _description = '', _delta = '[{"insert":"\\n"}]';
  List<FieldOption> _types = defaultFieldOptions('type');
  List<FieldOption> _conditions = defaultFieldOptions('condition');

  @override
  void initState() {
    super.initState();
    for (final field in bulkToolFields.keys) {
      final values = widget.items.map((item) => item.toMap()[field]).toSet();
      final common = values.length == 1 ? values.single : null;
      if (field == 'out_of_service') {
        _out = common == 1;
      } else if (field != 'description') {
        _controllers[field] = TextEditingController(
          text: common == null ? '' : common.toString(),
        );
      }
    }
    final descriptions = widget.items
        .map((item) => '${item.description}\u0000${item.descriptionDelta}')
        .toSet();
    if (descriptions.length == 1) {
      _description = widget.items.first.description;
      _delta = widget.items.first.descriptionDelta.isEmpty
          ? jsonEncode([
              {'insert': '$_description\n'},
            ])
          : widget.items.first.descriptionDelta;
    }
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final types = await ToolsDatabase.instance.loadFieldOptions('type');
      final conditions = await ToolsDatabase.instance.loadFieldOptions(
        'condition',
      );
      if (!mounted) return;
      setState(() {
        if (types.isNotEmpty) _types = types;
        if (conditions.isNotEmpty) _conditions = conditions;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron cargar las opciones: $error')),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _editDescription() async {
    final result = await Navigator.of(context).push<QuillDescriptionResult>(
      MaterialPageRoute(
        builder: (_) => QuillDescriptionPage(
          initialPlainText: _description,
          initialDelta: _delta,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _description = result.plainText;
      _delta = result.deltaJson;
    });
  }

  Map<String, Object?> _changes() => {
    for (final key in _enabled)
      key: key == 'description'
          ? _description
          : key == 'out_of_service'
          ? (_out ? 1 : 0)
          : bulkNumericFields.contains(key)
          ? double.tryParse(_controllers[key]!.text.trim().replaceAll(',', '.'))
          : _controllers[key]!.text.trim(),
    if (_enabled.contains('description')) 'description_delta': _delta,
  };

  Future<void> _save() async {
    if (_busy || _enabled.isEmpty || !_form.currentState!.validate()) return;
    final changes = _changes();
    try {
      validateBulkToolChanges(changes);
    } catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Revisa los campos: $error')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Aplicar a ${widget.items.length} herramientas'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Se sustituirán únicamente los campos marcados:'),
                const SizedBox(height: 8),
                for (final key in _enabled)
                  Text(
                    '${bulkToolFields[key]}: ${key == 'out_of_service' ? (_out ? 'Sí' : 'No') : (changes[key].toString().isEmpty ? 'Vaciar campo' : changes[key])}',
                  ),
                const Divider(),
                for (final item in widget.items) Text('• ${item.name}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('bulk_confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aplicar cambios'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ToolsDatabase.instance.updateToolsTogether(widget.items, changes);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se ha aplicado ningún cambio: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _editor(String key) {
    if (key == 'description') {
      return OutlinedButton(
        onPressed: _editDescription,
        child: Text(
          _description.isEmpty
              ? 'Editar descripción con formato'
              : _description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (key == 'out_of_service') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Fuera de servicio'),
        value: _out,
        onChanged: (value) => setState(() => _out = value),
      );
    }
    final controller = _controllers[key]!;
    if (key == 'tool_type' || key == 'condition' || key == 'voltage') {
      final options = <String>{
        if (key != 'condition') '',
        if (key == 'voltage') ...voltageOptionsFor(controller.text),
        if (key == 'tool_type') ..._types.map((option) => option.label),
        if (key == 'condition')
          ..._conditions
              .map((option) => option.label)
              .where((value) => !isLoanCondition(value)),
        if (controller.text.isNotEmpty && !isLoanCondition(controller.text))
          controller.text,
      };
      return DropdownButtonFormField<String>(
        key: ValueKey('bulk_value_$key'),
        initialValue: options.contains(controller.text)
            ? controller.text
            : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: bulkToolFields[key]),
        items: options
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(value.isEmpty ? 'Sin indicar' : value),
              ),
            )
            .toList(),
        onChanged: (value) {
          controller.text = value ?? '';
        },
        validator: (value) =>
            key == 'condition' && (value == null || value.isEmpty)
            ? 'Elige un estado'
            : null,
      );
    }
    return TextFormField(
      key: ValueKey('bulk_value_$key'),
      controller: controller,
      decoration: InputDecoration(
        labelText: bulkToolFields[key],
        helperText:
            bulkNumericFields.contains(key) || ['name', 'unit'].contains(key)
            ? null
            : 'Vacío borra este campo en las seleccionadas',
      ),
      keyboardType: bulkNumericFields.contains(key)
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      validator: (value) {
        final text = (value ?? '').trim();
        if (['name', 'unit'].contains(key) && text.isEmpty) {
          return 'Este campo es obligatorio';
        }
        if (bulkNumericFields.contains(key)) {
          final number = double.tryParse(text.replaceAll(',', '.'));
          if (number == null || !number.isFinite || number < 0) {
            return 'Escribe un número mayor o igual a cero';
          }
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Editar varias herramientas')),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _busy,
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${widget.items.length} herramientas seleccionadas'),
                const Text(
                  'Marca los campos que quieras aplicar a todas. Los demás conservarán su valor.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Los préstamos, fotos, documentos, códigos, números de serie y conjuntos se gestionan en cada ficha.',
                ),
                for (final entry in bulkToolFields.entries) ...[
                  CheckboxListTile(
                    key: ValueKey('bulk_field_${entry.key}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text('Aplicar ${entry.value.toLowerCase()}'),
                    value: _enabled.contains(entry.key),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        _enabled.add(entry.key);
                      } else {
                        _enabled.remove(entry.key);
                      }
                    }),
                  ),
                  if (_enabled.contains(entry.key)) _editor(entry.key),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('bulk_save'),
                  onPressed: _enabled.isEmpty ? null : _save,
                  child: Text(_busy ? 'Guardando…' : 'Revisar cambios'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
