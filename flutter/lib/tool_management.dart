part of 'main_quill_integrated_test.dart';

const managementChannel = MethodChannel('gestor_herramientas/management');
const managementColor = Color(0xFF697780);

class LoanContent {
  const LoanContent({required this.id, required this.componentId,
    required this.name, required this.quantity, this.returned = 0});
  final int id;
  final int componentId;
  final String name;
  final double quantity;
  final double returned;
  double get pending => quantity - returned;
  factory LoanContent.fromMap(Map<String, Object?> r) => LoanContent(
    id: r['id'] as int, componentId: r['component_id'] as int,
    name: r['name'] as String, quantity: (r['quantity'] as num).toDouble(),
    returned: (r['returned_quantity'] as num).toDouble());
}

class LoanReturnDraft {
  const LoanReturnDraft({required this.date, this.quantity,
    this.contents = const {}, this.notes = '', this.condition = '',
    this.needsMaintenance = false});
  final DateTime date;
  final double? quantity;
  final Map<int, double> contents; // loan_content row ID -> returned now
  final String notes;
  final String condition;
  final bool needsMaintenance;
}

class ToolDocument {
  const ToolDocument({this.id, required this.toolId, required this.name,
    this.kind = 'Manual', this.fileName = '', this.url = '',
    this.loanId, this.taskId});
  final int? id;
  final int toolId;
  final String name;
  final String kind;
  final String fileName;
  final String url;
  final int? loanId;
  final int? taskId;
  bool get isLink => url.isNotEmpty;
  factory ToolDocument.fromMap(Map<String, Object?> r) => ToolDocument(
    id: r['id'] as int, toolId: r['tool_id'] as int, name: r['name'] as String,
    kind: r['kind'] as String, fileName: r['file_name'] as String,
    url: r['url'] as String, loanId: r['loan_id'] as int?, taskId: r['task_id'] as int?);
  Map<String, Object?> toMap() => {'tool_id': toolId, 'name': name.trim(),
    'kind': kind, 'file_name': fileName, 'url': url.trim(),
    'loan_id': loanId, 'task_id': taskId};
}

class MaintenanceTask {
  const MaintenanceTask({this.id, required this.toolId, required this.title,
    required this.dueOn, this.toolName = '', this.interval = 0,
    this.intervalUnit = 'meses', this.notes = '', this.reminderDays = 1,
    this.enabled = true});
  final int? id;
  final int toolId;
  final String title;
  final DateTime dueOn;
  final String toolName;
  final int interval;
  final String intervalUnit;
  final String notes;
  final int reminderDays; // -1 disables this task's reminder
  final bool enabled;
  bool get isOverdue => enabled && loanDay(dueOn).isBefore(loanDay(DateTime.now()));
  DateTime nextAfter(DateTime date) {
    final day = loanDay(date);
    if (intervalUnit == 'días') return day.add(Duration(days: interval));
    final month = DateTime(day.year, day.month + interval, 1);
    final maxDay = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(month.year, month.month, day.day > maxDay ? maxDay : day.day);
  }
  factory MaintenanceTask.fromMap(Map<String, Object?> r) => MaintenanceTask(
    id: r['id'] as int, toolId: r['tool_id'] as int, title: r['title'] as String,
    dueOn: DateTime.parse(r['due_on'] as String),
    toolName: r['tool_name'] as String? ?? '', interval: r['interval_value'] as int,
    intervalUnit: r['interval_unit'] as String, notes: r['notes'] as String,
    reminderDays: r['reminder_days'] as int, enabled: r['enabled'] == 1);
  Map<String, Object?> toMap() => {'tool_id': toolId, 'title': title.trim(),
    'due_on': loanDay(dueOn).toIso8601String(), 'interval_value': interval,
    'interval_unit': intervalUnit, 'notes': notes.trim(),
    'reminder_days': reminderDays, 'enabled': enabled ? 1 : 0};
}

class MaintenanceRecord {
  const MaintenanceRecord({this.id, required this.taskId, required this.date,
    this.notes = '', this.parts = '', this.cost = 0});
  final int? id;
  final int taskId;
  final DateTime date;
  final String notes;
  final String parts;
  final double cost;
  factory MaintenanceRecord.fromMap(Map<String, Object?> r) => MaintenanceRecord(
    id: r['id'] as int, taskId: r['task_id'] as int,
    date: DateTime.parse(r['performed_on'] as String), notes: r['notes'] as String,
    parts: r['parts'] as String, cost: (r['cost'] as num).toDouble());
}

Future<Directory> toolDocumentsDirectory() async {
  final directory = Directory(p.join((await getApplicationDocumentsDirectory()).path,
    'tool_documents'));
  await directory.create(recursive: true);
  return directory;
}

Future<void> createManagementTables(DatabaseExecutor db) async {
  final tools = await db.rawQuery('PRAGMA table_info(tools)');
  for (final entry in <String, String>{
    'parent_id': 'INTEGER REFERENCES tools(id) ON DELETE RESTRICT',
    'is_set': 'INTEGER NOT NULL DEFAULT 0',
    'out_of_service': 'INTEGER NOT NULL DEFAULT 0',
    'service_notes': "TEXT NOT NULL DEFAULT ''",
  }.entries) {
    if (!tools.any((r) => r['name'] == entry.key)) {
      await db.execute('ALTER TABLE tools ADD COLUMN ${entry.key} ${entry.value}');
    }
  }
  final loans = await db.rawQuery('PRAGMA table_info(tool_loans)');
  for (final entry in <String, String>{
    'returned_quantity': 'REAL NOT NULL DEFAULT 0',
    'contact': "TEXT NOT NULL DEFAULT ''",
    'delivery_condition': "TEXT NOT NULL DEFAULT ''",
    'accessories': "TEXT NOT NULL DEFAULT ''",
    'reminder_days': 'INTEGER NOT NULL DEFAULT 1',
  }.entries) {
    if (!loans.any((r) => r['name'] == entry.key)) {
      await db.execute('ALTER TABLE tool_loans ADD COLUMN ${entry.key} ${entry.value}');
    }
  }
  await db.execute('UPDATE tool_loans SET returned_quantity = quantity WHERE returned_on IS NOT NULL');
  await db.execute('DROP INDEX IF EXISTS idx_tool_active_loan');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_tool_loans_active ON tool_loans(tool_id, returned_on)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_tools_parent ON tools(parent_id)');
  await db.execute('''CREATE TABLE IF NOT EXISTS loan_contents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_id INTEGER NOT NULL REFERENCES tool_loans(id) ON DELETE CASCADE,
    component_id INTEGER NOT NULL REFERENCES tools(id) ON DELETE RESTRICT,
    name TEXT NOT NULL, quantity REAL NOT NULL CHECK(quantity > 0),
    returned_quantity REAL NOT NULL DEFAULT 0,
    UNIQUE(loan_id, component_id)
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS loan_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_id INTEGER NOT NULL REFERENCES tool_loans(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL, kind TEXT NOT NULL, details TEXT NOT NULL DEFAULT '',
    performed_on TEXT, quantity REAL NOT NULL DEFAULT 0,
    condition TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT ''
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS borrowers (
    name TEXT PRIMARY KEY, contact TEXT NOT NULL DEFAULT ''
  )''');
  await db.execute('''INSERT OR IGNORE INTO borrowers(name, contact)
    SELECT borrower, contact FROM tool_loans ORDER BY id DESC''');
  await db.execute('''CREATE TABLE IF NOT EXISTS maintenance_tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id INTEGER NOT NULL REFERENCES tools(id) ON DELETE RESTRICT,
    title TEXT NOT NULL, due_on TEXT NOT NULL,
    interval_value INTEGER NOT NULL DEFAULT 0,
    interval_unit TEXT NOT NULL DEFAULT 'meses', notes TEXT NOT NULL DEFAULT '',
    reminder_days INTEGER NOT NULL DEFAULT 1, enabled INTEGER NOT NULL DEFAULT 1
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS maintenance_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id INTEGER NOT NULL REFERENCES maintenance_tasks(id) ON DELETE CASCADE,
    performed_on TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
    parts TEXT NOT NULL DEFAULT '', cost REAL NOT NULL DEFAULT 0
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS tool_documents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id INTEGER NOT NULL REFERENCES tools(id) ON DELETE RESTRICT,
    name TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'Manual',
    file_name TEXT NOT NULL DEFAULT '', url TEXT NOT NULL DEFAULT '',
    loan_id INTEGER REFERENCES tool_loans(id) ON DELETE RESTRICT,
    task_id INTEGER REFERENCES maintenance_tasks(id) ON DELETE RESTRICT
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS management_settings (
    key TEXT PRIMARY KEY, value TEXT NOT NULL
  )''');
}

Future<double> reservedQuantity(DatabaseExecutor db, int toolId) async {
  final own = await db.rawQuery('''SELECT COALESCE(SUM(quantity-returned_quantity),0) AS n
    FROM tool_loans WHERE tool_id=? AND returned_on IS NULL''', [toolId]);
  final part = await db.rawQuery('''SELECT COALESCE(SUM(c.quantity-c.returned_quantity),0) AS n
    FROM loan_contents c JOIN tool_loans l ON l.id=c.loan_id
    WHERE c.component_id=? AND l.returned_on IS NULL''', [toolId]);
  return (own.single['n'] as num).toDouble() + (part.single['n'] as num).toDouble();
}

Future<void> addLoanEvent(DatabaseExecutor db, int loanId, String kind,
  {String details = '', DateTime? performedOn, double quantity = 0,
    String condition = '', String notes = ''}) async {
  await db.insert('loan_events', {'loan_id': loanId,
    'created_at': DateTime.now().toIso8601String(), 'kind': kind, 'details': details,
    'performed_on': performedOn == null ? null : loanDay(performedOn).toIso8601String(),
    'quantity': quantity, 'condition': condition, 'notes': notes});
}

Future<void> refreshLoanCondition(DatabaseExecutor db, int toolId,
    String previousCondition) async {
  final own = await db.query('tool_loans', where: 'tool_id=? AND returned_on IS NULL',
    whereArgs: [toolId]);
  final parts = await db.rawQuery('''SELECT l.id FROM loan_contents c
    JOIN tool_loans l ON l.id=c.loan_id
    WHERE c.component_id=? AND l.returned_on IS NULL AND c.quantity>c.returned_quantity''', [toolId]);
  await db.update('tools', {'condition': own.isNotEmpty || parts.isNotEmpty ?
    'Prestado' : previousCondition}, where: 'id=?', whereArgs: [toolId]);
}

mixin ToolManagementDatabase {
  Future<Database> get database;

  Future<List<ToolItem>> loadComponents(int parentId) async {
    final all = await ToolsDatabase.instance.loadTools(includeComponents: true);
    return all.where((t) => t.parentId == parentId).toList();
  }
  Future<ToolItem?> loadTool(int id) async =>
    (await ToolsDatabase.instance.loadTools(includeComponents: true))
      .where((t) => t.id == id).firstOrNull;
  Future<int> nextToolId() async {
    final db = await database;
    return ((Sqflite.firstIntValue(await db.rawQuery('SELECT MAX(id) FROM tools')) ?? 0) + 1);
  }

  Future<void> detachComponent(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('tools', where: 'id=?', whereArgs: [id]);
      if (rows.isEmpty) throw StateError('La pieza ya no existe');
      final parent = rows.single['parent_id'];
      if (await reservedQuantity(txn, id) > 0 ||
          (parent != null && await reservedQuantity(txn, parent as int) > 0)) {
        throw StateError('Devuelve primero los préstamos de esta pieza o del conjunto');
      }
      await txn.update('tools', {'parent_id': null}, where: 'id=?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, Object?>>> loadBorrowers() async =>
    (await database).query('borrowers', orderBy: 'name COLLATE NOCASE');

  Future<List<LoanContent>> loadLoanContents(int loanId) async =>
    (await (await database).query('loan_contents', where: 'loan_id=?',
      whereArgs: [loanId], orderBy: 'id')).map(LoanContent.fromMap).toList();
  Future<List<Map<String, Object?>>> loanEvents(int loanId) async =>
    (await database).query('loan_events', where: 'loan_id=?',
      whereArgs: [loanId], orderBy: 'created_at DESC, id DESC');

  Future<void> recordReturn(int loanId, LoanReturnDraft draft) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('tool_loans', where: 'id=? AND returned_on IS NULL',
        whereArgs: [loanId]);
      if (rows.isEmpty) throw StateError('El préstamo ya está devuelto');
      final loan = ToolLoan.fromMap(rows.single);
      final day = loanDay(draft.date);
      if (day.isBefore(loanDay(loan.startedOn)) || day.isAfter(loanDay(DateTime.now()))) {
        throw StateError('La devolución debe estar entre la entrega y hoy');
      }
      final contents = (await txn.query('loan_contents', where: 'loan_id=?',
        whereArgs: [loanId])).map(LoanContent.fromMap).toList();
      var allReturned = false;
      var returned = loan.returnedQuantity;
      var count = 0.0;
      final affected = <int>[];
      if (contents.isNotEmpty) {
        final known = contents.map((c) => c.id).toSet();
        if (draft.contents.keys.any((id) => !known.contains(id))) {
          throw StateError('El contenido del préstamo ha cambiado');
        }
        allReturned = true;
        for (final c in contents) {
          final amount = draft.contents[c.id] ?? 0;
          if (!amount.isFinite || amount < 0 || amount > c.pending + 0.000001) {
            throw StateError('Cantidad de devolución no válida: ${c.name}');
          }
          count += amount;
          if (amount > 0) affected.add(c.componentId);
          await txn.update('loan_contents', {'returned_quantity': c.returned + amount},
            where: 'id=?', whereArgs: [c.id]);
          if (c.pending - amount > 0.000001) allReturned = false;
        }
        if (allReturned) returned = loan.quantity;
      } else {
        final amount = draft.quantity ?? loan.pendingQuantity;
        if (!amount.isFinite || amount <= 0 || amount > loan.pendingQuantity + 0.000001) {
          throw StateError('La cantidad supera lo pendiente de devolución');
        }
        count = amount;
        returned += amount;
        allReturned = loan.quantity - returned < 0.000001;
      }
      if (count <= 0) throw StateError('Indica al menos una unidad o pieza devuelta');
      final priorReturns = await txn.query('loan_events', columns: ['performed_on'],
        where: 'loan_id=? AND kind=?', whereArgs: [loanId, 'Devolución']);
      var finalDay = day;
      for (final event in priorReturns) {
        final value = event['performed_on'] as String?;
        if (value != null && DateTime.parse(value).isAfter(finalDay)) finalDay = DateTime.parse(value);
      }
      await txn.update('tool_loans', {'returned_quantity': returned,
        'returned_on': allReturned ? finalDay.toIso8601String() : null},
        where: 'id=?', whereArgs: [loanId]);
      await addLoanEvent(txn, loanId, 'Devolución', performedOn: day,
        quantity: count, condition: draft.condition, notes: draft.notes,
        details: contents.isEmpty ? '${formatNumber(count)} ${loan.unit}' :
          contents.where((c) => (draft.contents[c.id] ?? 0) > 0).map((c) =>
            '${c.name}: ${formatNumber(draft.contents[c.id]!)}').join('\n'));
      final condition = draft.condition.trim().isEmpty ? loan.previousCondition : draft.condition.trim();
      if (condition.isNotEmpty) await txn.update('tool_loans',
        {'previous_condition': condition}, where: 'tool_id=? AND returned_on IS NULL',
        whereArgs: [loan.toolId]);
      await refreshLoanCondition(txn, loan.toolId, condition);
      for (final id in affected) {
        // Components keep their own state unless a returned defect was recorded.
        final tool = (await txn.query('tools', where: 'id=?', whereArgs: [id])).single;
        final previous = draft.condition.trim().isEmpty ?
          (isLoanCondition(tool['condition'] as String) ? 'Bueno' : tool['condition'] as String) : condition;
        await refreshLoanCondition(txn, id, previous);
      }
      if (draft.needsMaintenance) {
        for (final id in [if (contents.isEmpty) loan.toolId, ...affected]) {
          await txn.update('tools', {'out_of_service': 1,
            'service_notes': draft.notes.isEmpty ? 'Revisar tras la devolución' : draft.notes},
            where: 'id=?', whereArgs: [id]);
        }
      }
    });
    await syncManagementReminders();
  }

  Future<void> editLoanEvent(int id, String notes, String condition) async {
    await (await database).update('loan_events', {'notes': notes.trim(),
      'condition': condition.trim()}, where: 'id=?', whereArgs: [id]);
  }

  Future<List<ToolDocument>> loadDocuments(int toolId, {int? loanId, int? taskId}) async {
    final db = await database;
    final where = loanId != null ? 'tool_id=? AND loan_id=?' : taskId != null ?
      'tool_id=? AND task_id=?' : 'tool_id=?';
    final args = [toolId, if (loanId != null) loanId, if (loanId == null && taskId != null) taskId];
    return (await db.query('tool_documents', where: where, whereArgs: args,
      orderBy: 'id DESC')).map(ToolDocument.fromMap).toList();
  }

  Future<int> saveDocument(ToolDocument document) async {
    if (document.name.trim().isEmpty) throw StateError('Pon un nombre al documento');
    if (document.isLink) {
      final uri = Uri.tryParse(document.url);
      if (uri == null || !const ['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) {
        throw StateError('Escribe un enlace http o https completo');
      }
    } else if (document.fileName.isEmpty || p.basename(document.fileName) != document.fileName ||
        !await File(p.join((await toolDocumentsDirectory()).path, document.fileName)).exists()) {
      throw StateError('Adjunta un archivo disponible');
    }
    final db = await database;
    if (document.id == null) return db.insert('tool_documents', document.toMap());
    final old = await db.query('tool_documents', where: 'id=?', whereArgs: [document.id]);
    if (old.isEmpty) throw StateError('El documento ya no existe');
    await db.update('tool_documents', document.toMap(), where: 'id=?', whereArgs: [document.id]);
    await _removeUnusedDocument(old.single['file_name'] as String);
    return document.id!;
  }
  Future<void> deleteDocument(ToolDocument document) async {
    await (await database).delete('tool_documents', where: 'id=?', whereArgs: [document.id]);
    await _removeUnusedDocument(document.fileName);
  }
  Future<void> _removeUnusedDocument(String fileName) async {
    if (fileName.isEmpty) return;
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM tool_documents WHERE file_name=?', [fileName])) ?? 0;
    if (count == 0) {
      final file = File(p.join((await toolDocumentsDirectory()).path, fileName));
      if (await file.exists()) await file.delete();
    }
  }

  Future<List<MaintenanceTask>> loadMaintenance({int? toolId}) async {
    final rows = await (await database).rawQuery('''SELECT m.*, t.name AS tool_name
      FROM maintenance_tasks m JOIN tools t ON t.id=m.tool_id
      ${toolId == null ? '' : 'WHERE m.tool_id=?'} ORDER BY enabled DESC, due_on, m.id''',
      toolId == null ? [] : [toolId]);
    return rows.map(MaintenanceTask.fromMap).toList();
  }
  Future<int> saveMaintenance(MaintenanceTask task) async {
    if (task.title.trim().isEmpty || task.interval < 0 || task.interval > 10000 ||
        !const ['meses', 'días'].contains(task.intervalUnit)) {
      throw StateError('Revisa el nombre y la periodicidad');
    }
    final db = await database;
    int id;
    if (task.id == null) {
      id = await db.insert('maintenance_tasks', task.toMap());
    } else {
      final changed = await db.update('maintenance_tasks', task.toMap(), where: 'id=?', whereArgs: [task.id]);
      if (changed == 0) throw StateError('La tarea ya no existe');
      id = task.id!;
    }
    await syncManagementReminders();
    return id;
  }
  Future<List<MaintenanceRecord>> maintenanceRecords(int taskId) async =>
    (await (await database).query('maintenance_records', where: 'task_id=?',
      whereArgs: [taskId], orderBy: 'performed_on DESC, id DESC'))
        .map(MaintenanceRecord.fromMap).toList();
  Future<void> saveMaintenanceRecord(MaintenanceRecord record) async {
    if (!record.cost.isFinite || record.cost < 0 ||
        loanDay(record.date).isAfter(loanDay(DateTime.now()))) {
      throw StateError('Revisa la fecha y el coste');
    }
    final db = await database;
    await db.transaction((txn) async {
      final taskRows = await txn.query('maintenance_tasks', where: 'id=?', whereArgs: [record.taskId]);
      if (taskRows.isEmpty) throw StateError('La tarea ya no existe');
      final task = MaintenanceTask.fromMap(taskRows.single);
      final map = <String, Object?>{'task_id': record.taskId,
        'performed_on': loanDay(record.date).toIso8601String(), 'notes': record.notes.trim(),
        'parts': record.parts.trim(), 'cost': record.cost};
      if (record.id == null) {
        await txn.insert('maintenance_records', map);
      } else {
        final changed = await txn.update('maintenance_records', map,
          where: 'id=? AND task_id=?', whereArgs: [record.id, record.taskId]);
        if (changed == 0) throw StateError('La intervención ya no existe');
      }
      final latest = await txn.query('maintenance_records', where: 'task_id=?',
        whereArgs: [record.taskId], orderBy: 'performed_on DESC, id DESC', limit: 1);
      final date = DateTime.parse(latest.single['performed_on'] as String);
      await txn.update('maintenance_tasks', task.interval == 0 ? {'enabled': 0} :
        {'due_on': task.nextAfter(date).toIso8601String(), 'enabled': 1},
        where: 'id=?', whereArgs: [record.taskId]);
    });
    await syncManagementReminders();
  }
  Future<void> setOutOfService(int id, bool out, String notes) async {
    await (await database).update('tools', {'out_of_service': out ? 1 : 0,
      'service_notes': notes.trim()}, where: 'id=?', whereArgs: [id]);
  }
}

Future<void> syncManagementReminders({bool requestPermission = false}) async {
  if (!Platform.isAndroid) return;
  try {
    final db = await ToolsDatabase.instance.database;
    final settings = await db.query('management_settings', where: 'key=?', whereArgs: ['notifications']);
    final enabled = settings.isNotEmpty && settings.single['value'] == '1';
    final reminders = <Map<String, Object?>>[];
    final now = DateTime.now();
    DateTime atNine(DateTime due, int days) {
      final date = loanDay(due).subtract(Duration(days: days));
      final result = DateTime(date.year, date.month, date.day, 9);
      return result.isAfter(now) ? result : now.add(const Duration(seconds: 10));
    }
    if (enabled) {
      for (final loan in await ToolsDatabase.instance.loadLoans()) {
        if (loan.isActive && loan.dueOn != null && loan.reminderDays >= 0) {
          reminders.add({'id': 'loan_${loan.id}',
            'time': atNine(loan.dueOn!, loan.reminderDays).millisecondsSinceEpoch,
            'title': 'Devolución de ${loan.toolName}',
            'text': '${loan.borrower} · ${loanDateText(loan.dueOn!)}',
            'version': '${loan.dueOn}:${loan.reminderDays}'});
        }
      }
      for (final task in await ToolsDatabase.instance.loadMaintenance()) {
        if (task.enabled && task.reminderDays >= 0) {
          reminders.add({'id': 'maintenance_${task.id}',
            'time': atNine(task.dueOn, task.reminderDays).millisecondsSinceEpoch,
            'title': '${task.toolName}: ${task.title}',
            'text': 'Mantenimiento · ${loanDateText(task.dueOn)}',
            'version': '${task.dueOn}:${task.reminderDays}'});
        }
      }
    }
    await managementChannel.invokeMethod<void>('reminders', {
      'items': reminders, 'requestPermission': enabled && requestPermission});
  } on MissingPluginException { /* Desktop tests use the same SQLite model. */ }
    on PlatformException { /* Pending dates remain visible in the app. */ }
}
