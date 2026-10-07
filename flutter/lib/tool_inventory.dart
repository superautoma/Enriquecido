part of 'main_quill_integrated_test.dart';

enum InventoryView { cards, compact, grid }
enum InventorySort { newest, name, nameDescending, quantity, price }
enum InventoryAvailability { all, available, borrowed, overdue, outOfService }
enum InventoryStock { all, low, empty }
enum InventoryContent { all, sets, individual, pieces }
enum InventoryMaintenance { all, pending, overdue }

String inventorySearchText(String value) {
  var result = value.toLowerCase();
  const accented = 'áéíóúüñ';
  const plain = 'aeiouun';
  for (var index = 0; index < accented.length; index++) {
    result = result.replaceAll(accented[index], plain[index]);
  }
  return result;
}

class InventoryPreferences {
  const InventoryPreferences({this.view = InventoryView.cards,
    this.sort = InventorySort.newest, this.types = const {},
    this.conditions = const {}, this.voltages = const {},
    this.sites = const {}, this.racks = const {}, this.shelves = const {},
    this.containers = const {}, this.brands = const {},
    this.availability = InventoryAvailability.all, this.stock = InventoryStock.all,
    this.content = InventoryContent.all, this.maintenance = InventoryMaintenance.all,
    this.includePieces = false, this.withDocuments = false, this.withPhotos = false});
  final InventoryView view;
  final InventorySort sort;
  final Set<String> types, conditions, voltages, sites, racks, shelves, containers, brands;
  final InventoryAvailability availability;
  final InventoryStock stock;
  final InventoryContent content;
  final InventoryMaintenance maintenance;
  final bool includePieces, withDocuments, withPhotos;

  int get filterCount => [types.isNotEmpty, conditions.isNotEmpty, voltages.isNotEmpty,
    sites.isNotEmpty, racks.isNotEmpty, shelves.isNotEmpty, containers.isNotEmpty, brands.isNotEmpty,
    availability != InventoryAvailability.all, stock != InventoryStock.all,
    content != InventoryContent.all, maintenance != InventoryMaintenance.all,
    includePieces, withDocuments, withPhotos].where((value) => value).length;

  InventoryPreferences copyWith({InventoryView? view, InventorySort? sort,
    Set<String>? types, Set<String>? conditions, Set<String>? voltages,
    Set<String>? sites, Set<String>? racks, Set<String>? shelves, Set<String>? containers, Set<String>? brands,
    InventoryAvailability? availability, InventoryStock? stock,
    InventoryContent? content, InventoryMaintenance? maintenance,
    bool? includePieces, bool? withDocuments, bool? withPhotos}) => InventoryPreferences(
      view: view ?? this.view, sort: sort ?? this.sort,
      types: types ?? this.types, conditions: conditions ?? this.conditions,
      voltages: voltages ?? this.voltages,
      sites: sites ?? this.sites, racks: racks ?? this.racks, shelves: shelves ?? this.shelves,
      containers: containers ?? this.containers, brands: brands ?? this.brands, availability: availability ?? this.availability,
      stock: stock ?? this.stock, content: content ?? this.content,
      maintenance: maintenance ?? this.maintenance,
      includePieces: includePieces ?? this.includePieces,
      withDocuments: withDocuments ?? this.withDocuments, withPhotos: withPhotos ?? this.withPhotos);

  InventoryPreferences clearFilters() => InventoryPreferences(view: view, sort: sort);
  Map<String, Object> toMap() => {'view': view.name, 'sort': sort.name,
    'types': types.toList(), 'conditions': conditions.toList(), 'voltages': voltages.toList(),
    'sites': sites.toList(), 'racks': racks.toList(), 'shelves': shelves.toList(),
    'containers': containers.toList(), 'brands': brands.toList(),
    'availability': availability.name, 'stock': stock.name, 'content': content.name,
    'maintenance': maintenance.name, 'includePieces': includePieces,
    'withDocuments': withDocuments, 'withPhotos': withPhotos};
  factory InventoryPreferences.fromMap(Map<String, dynamic> map) {
    T choice<T extends Enum>(List<T> choices, String key) =>
      choices.where((value) => value.name == map[key]).firstOrNull ?? choices.first;
    Set<String> values(String key) => map[key] is List ?
      (map[key] as List).whereType<String>().toSet() : <String>{};
    return InventoryPreferences(view: choice(InventoryView.values, 'view'),
      sort: choice(InventorySort.values, 'sort'), types: values('types'),
      conditions: values('conditions'), voltages: values('voltages'),
      sites: values('sites'), racks: values('racks'), shelves: values('shelves'),
      containers: values('containers'), brands: values('brands'),
      availability: choice(InventoryAvailability.values, 'availability'),
      stock: choice(InventoryStock.values, 'stock'), content: choice(InventoryContent.values, 'content'),
      maintenance: choice(InventoryMaintenance.values, 'maintenance'),
      includePieces: map['includePieces'] == true, withDocuments: map['withDocuments'] == true,
      withPhotos: map['withPhotos'] == true);
  }
}

class InventoryFacts {
  InventoryFacts(List<ToolItem> items, {this.documentTools = const {},
    this.pendingMaintenanceTools = const {}, this.overdueMaintenanceTools = const {}})
    : byId = {for (final item in items) item.id: item} {
    for (final item in items) {
      if (item.parentId != null) children.putIfAbsent(item.parentId!, () => []).add(item);
    }
  }
  final Map<int, ToolItem> byId;
  final Map<int, List<ToolItem>> children = {};
  final Set<int> documentTools, pendingMaintenanceTools, overdueMaintenanceTools;
  Iterable<ToolItem> related(ToolItem item) => [item, ...children[item.id] ?? []];
  bool hasRelated(ToolItem item, Set<int> ids) => related(item).any((tool) => ids.contains(tool.id));
  bool ownServiceBlock(ToolItem item) => item.outOfService ||
    (item.parentId != null && (byId[item.parentId]?.outOfService ?? false));
  bool childServiceBlock(ToolItem item) => (children[item.id] ?? []).any((tool) => tool.outOfService);
  bool serviceBlocked(ToolItem item) => ownServiceBlock(item) || childServiceBlock(item);
  ToolLocation locationFor(ToolItem item) => item.location.isEmpty && item.parentId != null
    ? byId[item.parentId]?.location ?? item.location : item.location;
  bool hasPhotos(ToolItem item) => related(item).any((tool) => tool.images.isNotEmpty);
}

List<ToolItem> selectInventoryTools(List<ToolItem> items, InventoryPreferences preferences,
    InventoryFacts facts, {String query = '', DateTime? today}) {
  final text = inventorySearchText(query.trim());
  final day = loanDay(today ?? DateTime.now());
  final visible = items.where((item) {
    if (item.parentId != null && !preferences.includePieces &&
        preferences.content != InventoryContent.pieces) return false;
    if (preferences.content == InventoryContent.sets && !item.isSet) return false;
    if (preferences.content == InventoryContent.individual && (item.isSet || item.parentId != null)) return false;
    if (preferences.content == InventoryContent.pieces && item.parentId == null) return false;
    if (preferences.types.isNotEmpty && !preferences.types.contains(item.type)) return false;
    final location = facts.locationFor(item);
    if (preferences.sites.isNotEmpty && !preferences.sites.contains(location.site)) return false;
    if (preferences.racks.isNotEmpty && !preferences.racks.contains(location.rack)) return false;
    if (preferences.shelves.isNotEmpty && !preferences.shelves.contains(location.shelf)) return false;
    if (preferences.containers.isNotEmpty && !preferences.containers.contains(location.container)) return false;
    if (preferences.brands.isNotEmpty && !preferences.brands.contains(item.brand)) return false;
    final state = item.activeLoans.isNotEmpty || item.activeLoan != null ? 'Prestado' : item.condition;
    if (preferences.conditions.isNotEmpty && !preferences.conditions.contains(state)) return false;
    if (preferences.voltages.isNotEmpty && !preferences.voltages.contains(item.voltage)) return false;
    final loans = item.activeLoans.isEmpty && item.activeLoan != null ? [item.activeLoan!] : item.activeLoans;
    final borrowed = loans.isNotEmpty;
    final overdue = loans.any((loan) => loan.isActive && loan.dueOn != null && loanDay(loan.dueOn!).isBefore(day));
    final available = !facts.serviceBlocked(item) && (item.availableQuantity ?? item.quantity) > 0;
    switch (preferences.availability) {
      case InventoryAvailability.all: break;
      case InventoryAvailability.available: if (!available) return false;
      case InventoryAvailability.borrowed: if (!borrowed) return false;
      case InventoryAvailability.overdue: if (!overdue) return false;
      case InventoryAvailability.outOfService: if (!facts.serviceBlocked(item)) return false;
    }
    if (preferences.stock == InventoryStock.empty && item.quantity > 0) return false;
    if (preferences.stock == InventoryStock.low &&
        (item.minimumStock <= 0 || item.quantity > item.minimumStock)) return false;
    if (preferences.withDocuments && !facts.hasRelated(item, facts.documentTools)) return false;
    if (preferences.withPhotos && !facts.hasPhotos(item)) return false;
    if (preferences.maintenance == InventoryMaintenance.pending &&
        !facts.hasRelated(item, facts.pendingMaintenanceTools)) return false;
    if (preferences.maintenance == InventoryMaintenance.overdue &&
        !facts.hasRelated(item, facts.overdueMaintenanceTools)) return false;
    if (text.isNotEmpty) {
      final search = [item.name, item.description, item.barcode, item.labelCode, item.type, item.voltage,
        item.condition, item.brand, item.model, item.serialNumber, location.label, ...loans.map((loan) => loan.borrower),
        ...facts.children[item.id]?.map((tool) =>
          [tool.name, tool.barcode, tool.labelCode, tool.brand, tool.model, tool.serialNumber, facts.locationFor(tool).label].join(' ')) ?? <String>[],
        if (item.parentId != null) facts.byId[item.parentId]?.name ?? ''].join(' ');
      if (!inventorySearchText(search).contains(text)) return false;
    }
    return true;
  }).toList();
  visible.sort((a, b) {
    int order;
    switch (preferences.sort) {
      case InventorySort.newest: order = b.id.compareTo(a.id);
      case InventorySort.name: order = inventorySearchText(a.name).compareTo(inventorySearchText(b.name));
      case InventorySort.nameDescending: order = inventorySearchText(b.name).compareTo(inventorySearchText(a.name));
      case InventorySort.quantity: order = a.quantity.compareTo(b.quantity);
      case InventorySort.price: order = b.purchasePrice.compareTo(a.purchasePrice);
    }
    return order == 0 ? a.id.compareTo(b.id) : order;
  });
  return visible;
}

Future<InventoryFacts> loadInventoryFacts(List<ToolItem> items) async {
  final db = await ToolsDatabase.instance.database;
  final documents = await db.query('tool_documents', columns: ['tool_id'], distinct: true);
  final tasks = await db.query('maintenance_tasks', columns: ['tool_id', 'due_on'], where: 'enabled=1');
  final today = loanDay(DateTime.now());
  return InventoryFacts(items, documentTools: documents.map((row) => row['tool_id'] as int).toSet(),
    pendingMaintenanceTools: tasks.map((row) => row['tool_id'] as int).toSet(),
    overdueMaintenanceTools: tasks.where((row) => DateTime.parse(row['due_on'] as String).isBefore(today))
      .map((row) => row['tool_id'] as int).toSet());
}

const inventoryPreferencesKey = 'inventory_preferences';
Future<InventoryPreferences> loadInventoryPreferences() async {
  final rows = await (await ToolsDatabase.instance.database).query('management_settings',
    where: 'key=?', whereArgs: [inventoryPreferencesKey]);
  try {
    final value = rows.isEmpty ? null : jsonDecode(rows.single['value'] as String);
    return value is Map<String, dynamic> ? InventoryPreferences.fromMap(value) : const InventoryPreferences();
  } on FormatException { return const InventoryPreferences(); }
}
Future<void> saveInventoryPreferences(InventoryPreferences preferences) async {
  await (await ToolsDatabase.instance.database).insert('management_settings',
    {'key': inventoryPreferencesKey, 'value': jsonEncode(preferences.toMap())},
    conflictAlgorithm: ConflictAlgorithm.replace);
}
