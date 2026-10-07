part of 'main_quill_integrated_test.dart';

const toolsDatabaseVersion = 10;
const toolDetailColumns = ['brand', 'model', 'serial_number', 'location_site',
  'location_rack', 'location_shelf', 'location_container'];

Future<void> ensureToolDetailColumns(DatabaseExecutor db) async {
  final existing = (await db.rawQuery('PRAGMA table_info(tools)'))
    .map((row) => row['name']).toSet();
  for (final column in toolDetailColumns) {
    if (!existing.contains(column)) {
      await db.execute("ALTER TABLE tools ADD COLUMN $column TEXT NOT NULL DEFAULT ''");
    }
  }
}

class ToolLocation {
  const ToolLocation({this.site = '', this.rack = '', this.shelf = '', this.container = ''});
  final String site, rack, shelf, container;
  List<String> get parts => [site, rack, shelf, container].where((s) => s.trim().isNotEmpty).toList();
  bool get isEmpty => parts.isEmpty;
  String get label => parts.join(' → ');
}

class ToolDetailsForm extends StatelessWidget {
  const ToolDetailsForm({super.key, required this.brand, required this.model,
    required this.serialNumber, required this.site, required this.rack,
    required this.shelf, required this.container, this.inheritedLocation = ''});
  final TextEditingController brand, model, serialNumber, site, rack, shelf, container;
  final String inheritedLocation;

  Widget _field(String key, String label, TextEditingController controller, IconData icon) =>
    Padding(padding: const EdgeInsets.only(top: 10), child: TextFormField(
      key: ValueKey('tool_$key'), controller: controller,
      textCapitalization: TextCapitalization.none,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon))));

  @override
  Widget build(BuildContext context) => Column(children: [
    ExpansionTile(key: const ValueKey('tool_identification'),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.badge_outlined, color: managementColor),
      title: const Text('Identificación'),
      initiallyExpanded: [brand, model, serialNumber].any((c) => c.text.isNotEmpty),
      children: [
        _field('brand', 'Marca', brand, Icons.business_outlined),
        _field('model', 'Modelo', model, Icons.handyman_outlined),
        _field('serial_number', 'Número de serie', serialNumber, Icons.tag),
        const SizedBox(height: 10),
      ]),
    ExpansionTile(key: const ValueKey('tool_location'),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.location_on_outlined, color: managementColor),
      title: const Text('Ubicación'),
      initiallyExpanded: [site, rack, shelf, container].any((c) => c.text.isNotEmpty),
      children: [
        if (inheritedLocation.isNotEmpty) Align(alignment: Alignment.centerLeft,
          child: Text('Si dejas estos campos vacíos, se usará la ubicación del conjunto: $inheritedLocation',
            style: const TextStyle(color: managementColor))),
        _field('location_site', 'Lugar / taller', site, Icons.home_work_outlined),
        _field('location_rack', 'Estantería', rack, Icons.view_week_outlined),
        _field('location_shelf', 'Balda', shelf, Icons.table_rows_outlined),
        _field('location_container', 'Caja / maletín', container, Icons.inventory_2_outlined),
        const SizedBox(height: 10),
      ]),
  ]);
}
