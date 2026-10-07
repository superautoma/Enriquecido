part of 'main_quill_integrated_test.dart';

Future<void> ensureToolTrashColumns(DatabaseExecutor db) async {
  final columns = (await db.rawQuery('PRAGMA table_info(tools)'))
    .map((row) => row['name']).toSet();
  for (final name in ['deleted_at', 'trash_group']) {
    if (!columns.contains(name)) {
      await db.execute("ALTER TABLE tools ADD COLUMN $name TEXT NOT NULL DEFAULT ''");
    }
  }
  await db.execute('CREATE INDEX IF NOT EXISTS idx_tool_trash_group ON tools(trash_group)');
}

String newToolTrashGroup() => 'trash_${newOwnToolCode().substring(ownToolCodePrefix.length)}';

String trashErrorMessage(Object error) => error is StateError
  ? error.message.toString() : 'No se pudo completar la operación: $error';

Future<void> requireActiveTool(DatabaseExecutor db, int id) async {
  final rows = await db.query('tools', columns: ['deleted_at'], where: 'id=?', whereArgs: [id]);
  if (rows.isEmpty) throw StateError('El artículo ya no existe.');
  if (rows.single['deleted_at'] != '') {
    throw StateError('El artículo está en la papelera. Recupéralo antes de editarlo.');
  }
}

Future<void> requireNoTrashLoans(DatabaseExecutor db, Iterable<int> ids) async {
  for (final id in ids.toSet()) {
    final rows = await db.rawQuery('''SELECT l.id FROM tool_loans l
      WHERE l.returned_on IS NULL AND (l.tool_id=? OR l.id IN
        (SELECT loan_id FROM loan_contents WHERE component_id=?)) LIMIT 1''', [id, id]);
    final legacy = await db.query('tools', columns: ['condition'], where: 'id=?', whereArgs: [id]);
    if (rows.isNotEmpty || (legacy.isNotEmpty && isLoanCondition(legacy.single['condition'] as String))) {
      throw StateError('Devuelve primero los préstamos activos del artículo o de su conjunto.');
    }
  }
}

Future<List<Map<String, Object?>>> toolTrashCandidates(DatabaseExecutor db, int id) async {
  await requireActiveTool(db, id);
  final root = (await db.query('tools', where: 'id=?', whereArgs: [id])).single;
  final children = await db.query('tools', where: "parent_id=? AND deleted_at=''", whereArgs: [id]);
  final rows = [root, ...children];
  await requireNoTrashLoans(db, [for (final row in rows) row['id'] as int,
    if (root['parent_id'] != null) root['parent_id'] as int]);
  return rows;
}

mixin ToolTrashDatabase {
  Future<Database> get database;

  Future<List<ToolItem>> trashCandidates(int id) async =>
    (await toolTrashCandidates(await database, id)).map(ToolItem.fromMap).toList();

  Future<void> trashTool(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      // Recheck after confirmation: an intervening loan must prevent deletion.
      final rows = await toolTrashCandidates(txn, id);
      final stamp = DateTime.now().toUtc().toIso8601String();
      final group = newToolTrashGroup();
      for (final row in rows) {
        await txn.update('tools', {'deleted_at': stamp, 'trash_group': group},
          where: 'id=?', whereArgs: [row['id']]);
      }
    });
    await syncManagementReminders();
  }

  Future<void> restoreTrashedTool(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('tools', where: "id=? AND deleted_at<>''", whereArgs: [id]);
      if (rows.isEmpty) throw StateError('El artículo ya no está en la papelera.');
      final group = rows.single['trash_group'] as String;
      final batch = await txn.query('tools', where: "trash_group=? AND deleted_at<>''", whereArgs: [group]);
      final ids = batch.map((row) => row['id'] as int).toSet();
      for (final row in batch) {
        final parentId = row['parent_id'] as int?;
        if (parentId == null || ids.contains(parentId)) continue;
        final parent = await txn.query('tools', where: 'id=?', whereArgs: [parentId]);
        if (parent.isEmpty || parent.single['deleted_at'] != '') {
          throw StateError('Recupera primero el conjunto al que pertenece esta pieza.');
        }
        await requireNoTrashLoans(txn, [parentId]);
      }
      await txn.update('tools', {'deleted_at': '', 'trash_group': ''},
        where: "trash_group=? AND deleted_at<>''", whereArgs: [group]);
    });
    await syncManagementReminders();
  }
}

Future<bool?> confirmToolTrash(BuildContext context, ToolItem item, int pieces) =>
  showDialog<bool>(context: context, builder: (context) => AlertDialog(
    title: const Text('Eliminar artículo'),
    content: Text('«${item.name}» pasará a la papelera${pieces == 0 ? '.' : ' junto con $pieces piezas.'}'
      '\n\nPodrás recuperarlo con sus fotos, documentos, historial y etiquetas QR.'
      '\nLos cambios de esta ficha que no hayas guardado se descartarán.'),
    actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enviar a la papelera'))]));

class ToolTrashPage extends StatefulWidget {
  const ToolTrashPage({super.key});
  @override
  State<ToolTrashPage> createState() => _ToolTrashPageState();
}

class _ToolTrashPageState extends State<ToolTrashPage> {
  List<List<ToolItem>> _batches = [];
  bool _loading = true, _busy = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final all = await ToolsDatabase.instance.loadTools(includeComponents: true, includeDeleted: true);
      final groups = <String, List<ToolItem>>{};
      for (final tool in all.where((tool) => tool.isDeleted)) {
        groups.putIfAbsent(tool.trashGroup, () => []).add(tool);
      }
      final batches = groups.values.toList();
      for (final batch in batches) {
        batch.sort((a, b) => (a.parentId == null ? 0 : 1).compareTo(b.parentId == null ? 0 : 1));
      }
      batches.sort((a, b) => b.first.deletedAt.compareTo(a.first.deletedAt));
      if (mounted) setState(() { _batches = batches; _loading = false; _error = null; });
    } catch (error) {
      if (mounted) setState(() { _loading = false; _error = trashErrorMessage(error); });
    }
  }

  Future<void> _restore(ToolItem item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ToolsDatabase.instance.restoreTrashedTool(item.id);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('«${item.name}» recuperado')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trashErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Papelera de artículos')),
    body: SafeArea(child: _loading ? const Center(child: CircularProgressIndicator()) :
      _error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!))) :
      _batches.isEmpty ? const Center(child: Text('La papelera está vacía')) :
      ListView(padding: const EdgeInsets.all(16), children: [
        const Padding(padding: EdgeInsets.only(bottom: 16), child: Text(
          'Recupera los artículos para devolverlos al inventario. Los conjuntos se recuperan con sus piezas.')),
        for (final batch in _batches) Card(child: ListTile(
          title: Text(batch.first.name),
          subtitle: Text([if (batch.first.parentId != null) 'Pieza de un conjunto',
            if (batch.length > 1) '${batch.length - 1} piezas: ${batch.skip(1).map((tool) => tool.name).join(', ')}',
            'Eliminado: ${DateTime.tryParse(batch.first.deletedAt)?.toLocal().toString().substring(0, 16) ?? batch.first.deletedAt}']
            .join('\n'), maxLines: 4, overflow: TextOverflow.ellipsis),
          trailing: IconButton(tooltip: 'Recuperar artículo', icon: const Icon(Icons.restore),
            onPressed: _busy ? null : () => _restore(batch.first)))),
      ])));
}
