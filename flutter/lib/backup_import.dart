part of 'main_quill_integrated_test.dart';

class BackupImportResult {
  const BackupImportResult({this.tools = 0, this.pieces = 0, this.loans = 0,
    this.documents = 0, this.maintenance = 0, this.regeneratedLabels = 0, this.trashed = 0, this.alreadyImported = false});
  final int tools, pieces, loans, documents, maintenance, regeneratedLabels, trashed;
  final bool alreadyImported;
  String get summary => alreadyImported ? 'Este archivo ya se había importado. No se ha añadido otra vez.' :
    'Añadidas $tools herramientas y $pieces piezas, $loans préstamos, '
    '$documents documentos y $maintenance tareas de mantenimiento.'
    '${trashed == 0 ? '' : ' $trashed artículos permanecen en la papelera.'}'
    '${regeneratedLabels == 0 ? '' : ' Se han generado $regeneratedLabels etiquetas QR nuevas para evitar duplicados.'}';
}

class BackupImportPlan {
  BackupImportPlan._(this.directory, this.fileName, this.fingerprint, this.tables,
    this.alreadyImported, this.existingTools, this.matchingReferences, this.iconNames, this.iconAppearances);
  final Directory directory;
  final String fileName, fingerprint;
  final Map<String, List<Map<String, Object?>>> tables;
  final bool alreadyImported;
  final int existingTools, matchingReferences;
  final Map<String, dynamic> iconNames, iconAppearances;
  bool _used = false;
  String get marker => 'imported_backup_$fingerprint';
  int get tools => tables['tools']!.where((row) => row['parent_id'] == null).length;
  int get pieces => tables['tools']!.length - tools;
  int get trashed => tables['tools']!.where((row) => row['deleted_at'] != '').length;
  int count(String table) => tables[table]?.length ?? 0;
  Future<void> dispose() async {
    try { if (await directory.exists()) await directory.delete(recursive: true); } on FileSystemException { /* Temporary cleanup may race with app shutdown. */ }
  }

  static Future<BackupImportPlan> prepare(String path) async {
    final bytes = await File(path).readAsBytes();
    final fingerprint = crypto.sha256.convert(bytes).toString();
    final temporary = await getTemporaryDirectory();
    final directory = await temporary.createTemp('gh_import_');
    Database? source;
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final names = <String>{};
      for (final entry in archive) {
        final name = entry.name.replaceAll('\\', '/');
        final normalized = p.posix.normalize(name);
        if (p.posix.isAbsolute(name) || RegExp(r'^[a-zA-Z]:').hasMatch(name) ||
            name.split('/').contains('..') || normalized == '.' || !names.add(normalized)) {
          throw const FormatException('El ZIP contiene una ruta no válida o repetida.');
        }
        final target = p.join(directory.path, normalized);
        if (entry.isFile) {
          final file = File(target);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(entry.content as List<int>, flush: true);
        } else { await Directory(target).create(recursive: true); }
      }
      final manifestFile = File(p.join(directory.path, 'manifest.json'));
      final databaseFile = File(p.join(directory.path, 'database', 'gestor_herramientas.db'));
      if (!await manifestFile.exists() || !await databaseFile.exists()) {
        throw const FormatException('Selecciona un ZIP de copia del Gestor de Herramientas.');
      }
      final manifest = jsonDecode(await manifestFile.readAsString());
      if (manifest is! Map || manifest['format'] != 'gestor_herramientas_backup' ||
          manifest['format_version'] is! num || !const [1, 2].contains(manifest['format_version'])) {
        throw const FormatException('Formato de copia no compatible.');
      }
      source = await openDatabase(databaseFile.path, readOnly: true, singleInstance: false);
      final version = await source.getVersion();
      if (version < 1 || version > toolsDatabaseVersion || (await source.rawQuery('PRAGMA integrity_check')).any((row) => row.values.first != 'ok')) {
        throw const FormatException('La base está dañada o necesita una versión más nueva de la aplicación.');
      }
      await source.close(); source = null;
      source = await openDatabase(databaseFile.path, version: toolsDatabaseVersion, singleInstance: false,
        onUpgrade: ToolsDatabase._upgradeSchema);
      if ((await source.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw const FormatException('La copia tiene registros relacionados que faltan.');
      }
      final tables = <String, List<Map<String, Object?>>>{};
      for (final table in const ['tools', 'tool_images', 'tool_loans', 'loan_contents',
        'loan_events', 'maintenance_tasks', 'maintenance_records', 'tool_documents', 'borrowers', 'field_options']) {
        tables[table] = await source.query(table);
      }
      await source.close(); source = null;
      final byId = {for (final row in tables['tools']!) row['id']: row};
      for (final row in tables['tools']!) {
        final deleted = row['deleted_at'] as String;
        final group = row['trash_group'] as String;
        if ((deleted.isEmpty != group.isEmpty) ||
            (deleted.isNotEmpty && DateTime.tryParse(deleted) == null)) {
          throw const FormatException('La copia contiene una papelera no válida.');
        }
        final parent = row['parent_id'];
        final owner = byId[parent];
        if (row['name'] is! String || (row['name'] as String).trim().isEmpty ||
            row['quantity'] is! num || !(row['quantity'] as num).isFinite || (row['quantity'] as num) < 0 ||
            (parent != null && (owner == null || owner['is_set'] != 1 || owner['parent_id'] != null || (owner['deleted_at'] != '' && deleted.isEmpty) || row['is_set'] == 1 || parent == row['id']))) {
          throw const FormatException('La copia contiene una herramienta o conjunto no válido.');
        }
      }
      for (final row in tables['tool_loans']!) {
        final quantity = row['quantity'] as num;
        final returned = row['returned_quantity'] as num;
        if (!quantity.isFinite || !returned.isFinite || quantity < 0 || returned < 0 || returned > quantity) {
          throw const FormatException('La copia contiene cantidades de préstamo no válidas.');
        }
      }
      final loansById = {for (final row in tables['tool_loans']!) row['id']: row};
      final reserved = <int, double>{};
      DateTime? parsed(Object? value) => value is String ? DateTime.tryParse(value) : null;
      for (final row in tables['tool_loans']!) {
        final started = parsed(row['started_on']);
        final due = parsed(row['due_on']);
        final returned = parsed(row['returned_on']);
        if (started == null || (row['due_on'] != null && (due == null || due.isBefore(started))) ||
            (row['returned_on'] != null && (returned == null || returned.isBefore(started)))) {
          throw const FormatException('La copia contiene fechas de préstamo no válidas.');
        }
        if (row['returned_on'] == null) {
          if (byId[row['tool_id']]!['deleted_at'] != '') {
            throw const FormatException('La copia contiene un préstamo activo de un artículo en la papelera.');
          }
          final id = row['tool_id'] as int;
          reserved[id] = (reserved[id] ?? 0) + (row['quantity'] as num).toDouble() - (row['returned_quantity'] as num).toDouble();
        }
      }
      for (final row in tables['loan_contents']!) {
        final quantity = row['quantity'] as num;
        final returned = row['returned_quantity'] as num;
        final loan = loansById[row['loan_id']]!;
        final component = byId[row['component_id']]!;
        if (!quantity.isFinite || !returned.isFinite || quantity <= 0 || returned < 0 ||
            returned > quantity || component['parent_id'] != loan['tool_id']) {
          throw const FormatException('El contenido de un préstamo no es válido.');
        }
        if (loan['returned_on'] == null) {
          if (component['deleted_at'] != '') {
            throw const FormatException('La copia contiene piezas prestadas en la papelera.');
          }
          final id = row['component_id'] as int;
          reserved[id] = (reserved[id] ?? 0) + quantity.toDouble() - returned.toDouble();
        }
      }
      for (final entry in reserved.entries) {
        if (entry.value > (byId[entry.key]!['quantity'] as num).toDouble() + 0.000001) {
          throw const FormatException('La copia presta más unidades de las existentes.');
        }
      }
      for (final row in tables['maintenance_tasks']!) {
        if (parsed(row['due_on']) == null || (row['interval_value'] as num) < 0 ||
            !const ['días', 'meses'].contains(row['interval_unit'])) {
          throw const FormatException('La copia contiene un mantenimiento no válido.');
        }
      }
      for (final row in tables['maintenance_records']!) {
        final cost = row['cost'] as num;
        if (parsed(row['performed_on']) == null || !cost.isFinite || cost < 0) {
          throw const FormatException('La copia contiene una intervención no válida.');
        }
      }
      final current = await ToolsDatabase.instance.database;
      final marker = await current.query('management_settings', where: 'key=?',
        whereArgs: ['imported_backup_$fingerprint']);
      final existing = await current.query('tools', columns: ['barcode', 'parent_id']);
      final references = existing.map((row) => row['barcode']).whereType<String>().where((s) => s.trim().isNotEmpty).toSet();
      Future<Map<String, dynamic>> readMap(String fileName) async {
        final file = File(p.join(directory.path, 'tool_images', fileName));
        if (!await file.exists()) return {};
        final value = jsonDecode(await file.readAsString());
        return value is Map<String, dynamic> ? value : {};
      }
      final settings = await readMap('icon_settings.json');
      final plan = BackupImportPlan._(directory, p.basename(path), fingerprint, tables,
        marker.isNotEmpty, existing.where((row) => row['parent_id'] == null).length,
        tables['tools']!.where((row) => references.contains(row['barcode'])).length,
        await readMap('icon_names.json'), settings['appearances'] is Map<String, dynamic> ?
          settings['appearances'] as Map<String, dynamic> : {});
      // Validate every referenced local asset before touching the destination.
      for (final row in tables['tool_images']!) { await plan._imageFile(row['path'] as String); }
      for (final row in tables['tools']!) {
        if ((row['image_path'] as String).isNotEmpty) await plan._imageFile(row['image_path'] as String);
      }
      for (final row in tables['tool_documents']!) {
        final fileName = row['file_name'] as String;
        if (fileName.isNotEmpty) await plan._documentFile(fileName);
      }
      for (final row in tables['field_options']!) {
        final key = row['icon_key'] as String;
        if (isCustomIconKey(key)) await plan._iconFile(key);
      }
      return plan;
    } catch (_) {
      if (source != null) await source.close();
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<File> _imageFile(String original) async {
    final normalized = original.replaceAll('\\', '/');
    final marker = normalized.lastIndexOf('/tool_images/');
    if (marker >= 0) {
      final relative = normalized.substring(marker + '/tool_images/'.length);
      if (!relative.split('/').contains('..')) {
        final candidate = File(p.join(directory.path, 'tool_images', relative));
        if (await candidate.exists()) return candidate;
      }
    }
    final file = File(p.join(directory.path, 'tool_images', p.posix.basename(normalized)));
    if (!await file.exists()) throw FormatException('Falta una fotografía en la copia: ${p.posix.basename(normalized)}');
    return file;
  }
  Future<File> _documentFile(String name) async {
    if (p.basename(name) != name || name.contains('\\') || name == '.' || name == '..') {
      throw const FormatException('Un documento tiene un nombre de archivo no válido.');
    }
    final file = File(p.join(directory.path, 'tool_documents', name));
    if (!await file.exists()) throw FormatException('Falta un documento en la copia: $name');
    return file;
  }
  Future<File> _iconFile(String key) async {
    final file = File(p.join(directory.path, 'tool_images', 'custom_icons',
      p.posix.basename(customIconPathFromKey(key).replaceAll('\\', '/'))));
    if (!await file.exists()) throw const FormatException('Falta un icono personalizado en la copia.');
    return file;
  }

  Future<BackupImportResult> apply() async {
    if (_used) throw StateError('Selecciona de nuevo el archivo para importarlo.');
    _used = true;
    final createdFiles = <File>[];
    final assets = <String, String>{};
    final prefix = 'import_${DateTime.now().microsecondsSinceEpoch}_${fingerprint.substring(0, 8)}';
    final images = await BackupManager._imagesDirectory();
    final documents = await toolDocumentsDirectory();
    final icons = await customIconsDirectory();
    var sequence = 0;
    Future<String> copy(File source, Directory destination, {String label = ''}) async {
      if (assets.containsKey(source.path)) return assets[source.path]!;
      await destination.create(recursive: true);
      final extension = p.extension(source.path).toLowerCase();
      final clean = label.replaceAll(RegExp(r'[^a-zA-Z0-9áéíóúÁÉÍÓÚñÑüÜ_-]'), '_');
      final stem = clean.length > 40 ? clean.substring(0, 40) : clean;
      final target = File(p.join(destination.path, '${stem.isEmpty ? '' : '${stem}_'}${prefix}_${sequence++}$extension'));
      if (await target.exists()) throw StateError('No se pudo reservar un nombre de archivo nuevo.');
      createdFiles.add(target);
      await source.copy(target.path);
      assets[source.path] = target.path;
      return target.path;
    }
    final current = await ToolsDatabase.instance.database;
    var committed = false;
    try {
      final result = await current.transaction((txn) async {
        if ((await txn.query('management_settings', where: 'key=?', whereArgs: [marker])).isNotEmpty) {
          return const BackupImportResult(alreadyImported: true);
        }
        final customKeys = <String, String>{};
        final customDirectory = Directory(p.join(directory.path, 'tool_images', 'custom_icons'));
        if (await customDirectory.exists()) {
          await for (final entity in customDirectory.list()) {
            if (entity is! File || !const ['.png', '.jpg', '.jpeg', '.webp', '.svg'].contains(p.extension(entity.path).toLowerCase())) continue;
            final basename = p.basename(entity.path);
            final label = iconNames['custom:$basename'] as String? ?? p.basenameWithoutExtension(basename);
            final target = await copy(entity, icons, label: label);
            customKeys[basename] = 'custom:$target';
            final group = File('${entity.path}.group.json');
            if (await group.exists()) {
              final sidecar = File('$target.group.json'); createdFiles.add(sidecar);
              await group.copy(sidecar.path);
            }
          }
        }
        final columns = <String, Set<String>>{};
        for (final table in tables.keys) {
          columns[table] = (await txn.rawQuery('PRAGMA table_info($table)')).map((row) => row['name'] as String).toSet();
        }
        Map<String, Object?> values(String table, Map<String, Object?> row) => Map.of(row)
          ..removeWhere((key, value) => key == 'id' || !columns[table]!.contains(key));
        final toolIds = <int, int>{};
        final trashGroups = <String, String>{};
        final usedLabels = (await txn.query('tools', columns: ['label_code']))
          .map((row) => row['label_code'] as String).where((code) => code.isNotEmpty).toSet();
        var regeneratedLabels = 0;
        for (final row in tables['tools']!) {
          final map = values('tools', row)..['parent_id'] = null;
          final group = map['trash_group'] as String? ?? '';
          if (group.isNotEmpty) map['trash_group'] = trashGroups.putIfAbsent(group, newToolTrashGroup);
          var label = map['label_code'] as String? ?? '';
          if (label.isNotEmpty && usedLabels.contains(label)) {
            do { label = newOwnToolCode(); } while (usedLabels.contains(label));
            map['label_code'] = label;
            regeneratedLabels++;
          }
          if (label.isNotEmpty) usedLabels.add(label);
          final photo = row['image_path'] as String;
          map['image_path'] = photo.isEmpty ? '' : await copy(await _imageFile(photo), images);
          toolIds[row['id'] as int] = await txn.insert('tools', map);
        }
        int mapped(Map<int, int> ids, Object? old) {
          if (old is! int || !ids.containsKey(old)) throw const FormatException('Falta un registro relacionado en la copia.');
          return ids[old]!;
        }
        for (final row in tables['tools']!) {
          if (row['parent_id'] != null) await txn.update('tools', {'parent_id': mapped(toolIds, row['parent_id'])},
            where: 'id=?', whereArgs: [mapped(toolIds, row['id'])]);
        }
        final loanIds = <int, int>{};
        for (final row in tables['tool_loans']!) {
          final map = values('tool_loans', row)..['tool_id'] = mapped(toolIds, row['tool_id']);
          loanIds[row['id'] as int] = await txn.insert('tool_loans', map);
        }
        for (final row in tables['loan_contents']!) {
          await txn.insert('loan_contents', values('loan_contents', row)
            ..['loan_id'] = mapped(loanIds, row['loan_id'])
            ..['component_id'] = mapped(toolIds, row['component_id']));
        }
        for (final row in tables['loan_events']!) {
          await txn.insert('loan_events', values('loan_events', row)..['loan_id'] = mapped(loanIds, row['loan_id']));
        }
        final taskIds = <int, int>{};
        for (final row in tables['maintenance_tasks']!) {
          taskIds[row['id'] as int] = await txn.insert('maintenance_tasks',
            values('maintenance_tasks', row)..['tool_id'] = mapped(toolIds, row['tool_id']));
        }
        for (final row in tables['maintenance_records']!) {
          await txn.insert('maintenance_records', values('maintenance_records', row)..['task_id'] = mapped(taskIds, row['task_id']));
        }
        for (final row in tables['tool_images']!) {
          await txn.insert('tool_images', values('tool_images', row)
            ..['tool_id'] = mapped(toolIds, row['tool_id'])
            ..['path'] = await copy(await _imageFile(row['path'] as String), images));
        }
        for (final row in tables['tool_documents']!) {
          final map = values('tool_documents', row)..['tool_id'] = mapped(toolIds, row['tool_id']);
          if (row['loan_id'] != null) map['loan_id'] = mapped(loanIds, row['loan_id']);
          if (row['task_id'] != null) map['task_id'] = mapped(taskIds, row['task_id']);
          final name = row['file_name'] as String;
          map['file_name'] = name.isEmpty ? '' : p.basename(await copy(await _documentFile(name), documents));
          await txn.insert('tool_documents', map);
        }
        for (final row in tables['borrowers']!) {
          await txn.insert('borrowers', values('borrowers', row), conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        for (final row in tables['field_options']!) {
          final existing = await txn.query('field_options', where: 'field_key=? AND label=?',
            whereArgs: [row['field_key'], row['label']]);
          if (existing.isNotEmpty) continue;
          final map = values('field_options', row);
          final key = row['icon_key'] as String;
          if (isCustomIconKey(key)) {
            map['icon_key'] = customKeys[p.posix.basename(customIconPathFromKey(key).replaceAll('\\', '/'))]!;
            final colors = iconAppearances[iconNameStorageKey(key)];
            if (colors is Map) {
              if (colors['line'] is int) map['color_value'] = colors['line'];
              if (colors['circle'] is int) map['circle_color_value'] = colors['circle'];
            }
          }
          final position = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COALESCE(MAX(position),-1)+1 FROM field_options WHERE field_key=?', [row['field_key']]))!;
          map['position'] = position;
          await txn.insert('field_options', map);
        }
        await txn.insert('management_settings', {'key': marker, 'value': jsonEncode({
          'file': fileName, 'date': DateTime.now().toIso8601String(), 'tools': tools, 'pieces': pieces})});
        if ((await txn.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
          throw const FormatException('No se pudo verificar la relación entre los datos importados.');
        }
        return BackupImportResult(tools: tools, pieces: pieces, trashed: trashed, loans: count('tool_loans'), regeneratedLabels: regeneratedLabels,
          documents: count('tool_documents'), maintenance: count('maintenance_tasks'));
      });
      committed = true;
      try { await syncManagementReminders(); } catch (error) { debugPrint('Avisos tras importación: $error'); }
      return result;
    } finally {
      if (!committed) {
        for (final file in createdFiles.reversed) {
          try { if (await file.exists()) await file.delete(); } catch (_) {}
        }
      }
    }
  }
}
