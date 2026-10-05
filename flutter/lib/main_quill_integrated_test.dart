import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

void main() {
  runApp(const GestorHerramientasApp());
}

class GestorHerramientasApp extends StatelessWidget {
  const GestorHerramientasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gestor Quill Integrado',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F9FB),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF168BD2),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEAF4FE),
          foregroundColor: Color(0xFF20242A),
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFFD7DDE3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFFD7DDE3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF168BD2), width: 2),
          ),
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es'), Locale('en')],
      home: const ToolsHomePage(),
    );
  }
}

class ToolItem {
  ToolItem({
    required this.id,
    required this.name,
    required this.description,
    required this.descriptionDelta,
    required this.barcode,
    required this.quantity,
    required this.unit,
    required this.minimumStock,
    required this.purchasePrice,
    required this.condition,
  });

  final int id;
  String name;
  String description;
  String descriptionDelta;
  String barcode;
  double quantity;
  String unit;
  double minimumStock;
  double purchasePrice;
  String condition;

  ToolItem copy() => ToolItem(
        id: id,
        name: name,
        description: description,
        descriptionDelta: descriptionDelta,
        barcode: barcode,
        quantity: quantity,
        unit: unit,
        minimumStock: minimumStock,
        purchasePrice: purchasePrice,
        condition: condition,
      );
}

class ConditionStyle {
  const ConditionStyle(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;
}

const conditionStyles = <ConditionStyle>[
  ConditionStyle('Bueno', Color(0xFF43A047), Icons.check_circle_outline),
  ConditionStyle('Revisar', Color(0xFFF9A825), Icons.build_circle_outlined),
  ConditionStyle('Averiado', Color(0xFFE53935), Icons.error_outline),
  ConditionStyle('Prestado', Color(0xFF7E57C2), Icons.swap_horiz),
];

ConditionStyle conditionStyleFor(String value) {
  return conditionStyles.firstWhere(
    (style) => style.label == value,
    orElse: () => conditionStyles.first,
  );
}

class ToolsHomePage extends StatefulWidget {
  const ToolsHomePage({super.key});

  @override
  State<ToolsHomePage> createState() => _ToolsHomePageState();
}

class _ToolsHomePageState extends State<ToolsHomePage> {
  final _searchController = TextEditingController();

  final List<ToolItem> _items = [
    ToolItem(
      id: 1,
      name: 'Destornillador aislado',
      description: 'Destornillador VDE para trabajos eléctricos.',
      descriptionDelta: '',
      barcode: '841000000001',
      quantity: 4,
      unit: 'ud',
      minimumStock: 1,
      purchasePrice: 8.50,
      condition: 'Bueno',
    ),
    ToolItem(
      id: 2,
      name: 'Multímetro',
      description: 'Multímetro digital de uso general.',
      descriptionDelta: '',
      barcode: '841000000002',
      quantity: 2,
      unit: 'ud',
      minimumStock: 1,
      purchasePrice: 64.90,
      condition: 'Revisar',
    ),
    ToolItem(
      id: 3,
      name: 'Taladro',
      description: 'Taladro con cable para taller.',
      descriptionDelta: '',
      barcode: '841000000003',
      quantity: 1,
      unit: 'ud',
      minimumStock: 1,
      purchasePrice: 89.00,
      condition: 'Bueno',
    ),
  ];

  String get _query => _searchController.text.trim().toLowerCase();

  List<ToolItem> get _visibleItems {
    if (_query.isEmpty) return _items;
    return _items
        .where(
          (item) =>
              item.name.toLowerCase().contains(_query) ||
              item.description.toLowerCase().contains(_query) ||
              item.barcode.toLowerCase().contains(_query),
        )
        .toList();
  }

  Future<void> _openEditor({ToolItem? item}) async {
    final result = await Navigator.of(context).push<ToolItem>(
      MaterialPageRoute(
        builder: (_) => EditToolPage(
          item: item?.copy(),
          nextId: _items.isEmpty
              ? 1
              : _items.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      final index = _items.indexWhere((element) => element.id == result.id);
      if (index >= 0) {
        _items[index] = result;
      } else {
        _items.insert(0, result);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mis herramientas · QUILL V4',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Opciones',
            onPressed: () {},
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        backgroundColor: const Color(0xFF168BD2),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, size: 30),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar herramientas',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Row(
                children: [
                  Text(
                    '${visible.length} artículos',
                    style: const TextStyle(
                      color: Color(0xFF72777D),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.tune, size: 20),
                    label: const Text('Filtrar'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(
                      child: Text(
                        'No se encontraron herramientas',
                        style: TextStyle(color: Color(0xFF7A7F85)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 92),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        final style = conditionStyleFor(item.condition);

                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _openEditor(item: item),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEAF4FE),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.handyman_outlined,
                                      color: Color(0xFF168BD2),
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF25292D),
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 9,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: style.color
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    style.icon,
                                                    size: 15,
                                                    color: style.color,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    style.label,
                                                    style: TextStyle(
                                                      color: style.color,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              'Cantidad: ${formatNumber(item.quantity)} ${item.unit}',
                                              style: const TextStyle(
                                                color: Color(0xFF6F747A),
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Color(0xFF9AA0A6),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditToolPage extends StatefulWidget {
  const EditToolPage({
    super.key,
    required this.item,
    required this.nextId,
  });

  final ToolItem? item;
  final int nextId;

  @override
  State<EditToolPage> createState() => _EditToolPageState();
}

class _EditToolPageState extends State<EditToolPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late String _descriptionPlain;
  late String _descriptionDelta;
  late final TextEditingController _barcode;
  late final TextEditingController _quantity;
  late final TextEditingController _unit;
  late final TextEditingController _minimumStock;
  late final TextEditingController _purchasePrice;

  late String _condition;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;

    _name = TextEditingController(text: item?.name ?? '');
    _descriptionPlain = item?.description ?? '';
    _descriptionDelta = item?.descriptionDelta ?? '';
    _barcode = TextEditingController(text: item?.barcode ?? '');
    _quantity = TextEditingController(
      text: item == null ? '1' : formatNumber(item.quantity),
    );
    _unit = TextEditingController(text: item?.unit ?? 'ud');
    _minimumStock = TextEditingController(
      text: item == null ? '0' : formatNumber(item.minimumStock),
    );
    _purchasePrice = TextEditingController(
      text: item == null ? '' : item.purchasePrice.toStringAsFixed(2),
    );
    _condition = item?.condition ?? conditionStyles.first.label;
  }

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _quantity.dispose();
    _unit.dispose();
    _minimumStock.dispose();
    _purchasePrice.dispose();
    super.dispose();
  }

  double _number(String value) {
    return double.tryParse(value.replaceAll(',', '.').trim()) ?? 0;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final result = ToolItem(
      id: widget.item?.id ?? widget.nextId,
      name: _name.text.trim(),
      description: _descriptionPlain,
      descriptionDelta: _descriptionDelta,
      barcode: _barcode.text.trim(),
      quantity: _number(_quantity.text),
      unit: _unit.text.trim().isEmpty ? 'ud' : _unit.text.trim(),
      minimumStock: _number(_minimumStock.text),
      purchasePrice: _number(_purchasePrice.text),
      condition: _condition,
    );

    Navigator.of(context).pop(result);
  }

  Future<void> _openQuillDescription() async {
    final result = await Navigator.of(context).push<QuillDescriptionResult>(
      MaterialPageRoute(
        builder: (_) => QuillDescriptionPage(
          initialPlainText: _descriptionPlain,
          initialDelta: _descriptionDelta,
        ),
      ),
    );

    if (result == null) return;
    setState(() {
      _descriptionPlain = result.plainText;
      _descriptionDelta = result.deltaJson;
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = conditionStyleFor(_condition);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Editar artículo · QUILL V4' : 'Nuevo artículo · QUILL V4',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'GUARDAR',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
            children: [
              const SectionTitle('Información básica'),
              const SizedBox(height: 10),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre*',
                  prefixIcon: Icon(Icons.handyman_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Escribe el nombre'
                    : null,
              ),
              const SizedBox(height: 12),
              DescriptionQuillCard(
                text: _descriptionPlain,
                deltaJson: _descriptionDelta,
                onTap: _openQuillDescription,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barcode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Código de barras',
                  prefixIcon: Icon(Icons.qr_code_scanner),
                ),
              ),
              const SizedBox(height: 22),
              const SectionTitle('Existencias'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _quantity,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cantidad',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _unit,
                      decoration: const InputDecoration(
                        labelText: 'Unidad',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _minimumStock,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cantidad mínima',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 22),
              const SectionTitle('Estado'),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _condition,
                decoration: InputDecoration(
                  labelText: 'Estado de la herramienta',
                  prefixIcon: Icon(style.icon, color: style.color),
                ),
                items: conditionStyles
                    .map(
                      (option) => DropdownMenuItem(
                        value: option.label,
                        child: Row(
                          children: [
                            Icon(option.icon, color: option.color, size: 20),
                            const SizedBox(width: 8),
                            Text(option.label),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _condition = value);
                },
              ),
              const SizedBox(height: 22),
              const SectionTitle('Compra e imagen'),
              const SizedBox(height: 10),
              TextFormField(
                controller: _purchasePrice,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Precio de compra (€)',
                  prefixIcon: Icon(Icons.euro),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'La selección de imagen se añadirá en el siguiente bloque.',
                      ),
                    ),
                  );
                },
                child: Container(
                  height: 126,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFD7DDE3),
                    ),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 36,
                        color: Color(0xFF168BD2),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Añadir imagen',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF168BD2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar artículo'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF168BD2),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DescriptionQuillCard extends StatelessWidget {
  const DescriptionQuillCard({
    super.key,
    required this.text,
    required this.deltaJson,
    required this.onTap,
  });

  final String text;
  final String deltaJson;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasText = text.trim().isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        isEmpty: false,
        decoration: const InputDecoration(
          labelText: 'Descripción',
          suffixIcon: Icon(
            Icons.edit_outlined,
            color: Color(0xFF168BD2),
          ),
          contentPadding: EdgeInsets.fromLTRB(16, 18, 12, 16),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Align(
            alignment: Alignment.topLeft,
            child: hasText
                ? _RichDeltaPreview(
                    plainText: text,
                    deltaJson: deltaJson,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _RichDeltaPreview extends StatelessWidget {
  const _RichDeltaPreview({
    required this.plainText,
    required this.deltaJson,
  });

  final String plainText;
  final String deltaJson;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];

    try {
      if (deltaJson.trim().isNotEmpty) {
        final decoded = jsonDecode(deltaJson);
        if (decoded is List) {
          for (final operation in decoded) {
            if (operation is! Map) continue;

            final insert = operation['insert'];
            if (insert is! String) continue;

            final rawAttributes = operation['attributes'];
            final attributes = rawAttributes is Map
                ? Map<String, dynamic>.from(rawAttributes)
                : const <String, dynamic>{};

            spans.add(
              TextSpan(
                text: insert,
                style: _styleFromAttributes(attributes),
              ),
            );
          }
        }
      }
    } catch (_) {
      // Si un Delta antiguo no se puede interpretar, mostramos texto normal.
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: plainText));
    }

    return RichText(
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(
          fontSize: 15,
          height: 1.35,
          color: Color(0xFF2B3035),
        ),
        children: spans,
      ),
    );
  }

  TextStyle _styleFromAttributes(Map<String, dynamic> attributes) {
    final decorations = <TextDecoration>[];

    if (attributes['underline'] == true) {
      decorations.add(TextDecoration.underline);
    }
    if (attributes['strike'] == true) {
      decorations.add(TextDecoration.lineThrough);
    }

    return TextStyle(
      fontWeight:
          attributes['bold'] == true ? FontWeight.w700 : FontWeight.normal,
      fontStyle:
          attributes['italic'] == true ? FontStyle.italic : FontStyle.normal,
      decoration: decorations.isEmpty
          ? TextDecoration.none
          : TextDecoration.combine(decorations),
      color: _parseColor(attributes['color']),
      backgroundColor: _parseColor(attributes['background']),
      fontSize: _parseFontSize(attributes['size']),
    );
  }

  Color? _parseColor(dynamic value) {
    if (value is! String || value.isEmpty) return null;

    var hex = value.trim();
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    }

    if (hex.length == 6) {
      hex = 'FF$hex';
    }

    if (hex.length != 8) return null;

    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  double? _parseFontSize(dynamic value) {
    if (value == null) return null;

    final text = value.toString();
    switch (text) {
      case 'small':
        return 12;
      case 'large':
        return 20;
      case 'huge':
        return 26;
      default:
        return double.tryParse(text);
    }
  }
}

class QuillDescriptionResult {
  const QuillDescriptionResult({
    required this.plainText,
    required this.deltaJson,
  });

  final String plainText;
  final String deltaJson;
}

class QuillDescriptionPage extends StatefulWidget {
  const QuillDescriptionPage({
    super.key,
    required this.initialPlainText,
    required this.initialDelta,
  });

  final String initialPlainText;
  final String initialDelta;

  @override
  State<QuillDescriptionPage> createState() => _QuillDescriptionPageState();
}

class _QuillDescriptionPageState extends State<QuillDescriptionPage> {
  late final QuillController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    Document document;
    if (widget.initialDelta.trim().isNotEmpty) {
      try {
        document = Document.fromJson(
          jsonDecode(widget.initialDelta) as List<dynamic>,
        );
      } catch (_) {
        document = _documentFromPlain(widget.initialPlainText);
      }
    } else {
      document = _documentFromPlain(widget.initialPlainText);
    }

    _controller = QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  Document _documentFromPlain(String value) {
    final text = value.trim().isEmpty ? '\n' : '${value.trimRight()}\n';
    return Document.fromJson([
      {'insert': text}
    ]);
  }

  void _accept() {
    Navigator.of(context).pop(
      QuillDescriptionResult(
        plainText: _controller.document.toPlainText().trim(),
        deltaJson: jsonEncode(_controller.document.toDelta().toJson()),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Editor Quill',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: _accept,
            child: const Text(
              'ACEPTAR',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF3CD),
              padding: const EdgeInsets.all(10),
              child: const Text(
                'Quill integrado en la aplicación, en pantalla propia.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            QuillSimpleToolbar(
              controller: _controller,
              config: const QuillSimpleToolbarConfig(),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFB0B7BE)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: QuillEditor.basic(
                  controller: _controller,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  config: const QuillEditorConfig(
                    placeholder: 'Escribe aquí…',
                    padding: EdgeInsets.all(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: Color(0xFF5E646A),
      ),
    );
  }
}

String formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}
