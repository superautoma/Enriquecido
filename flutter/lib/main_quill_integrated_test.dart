import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:share_plus/share_plus.dart';

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

class ToolImage {
  ToolImage({
    this.id,
    required this.toolId,
    required this.path,
    this.description = '',
    this.type = 'General',
    this.position = 0,
    this.isPrimary = false,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  int? id;
  int toolId;
  String path;
  String description;
  String type;
  int position;
  bool isPrimary;
  String createdAt;

  ToolImage copy() => ToolImage(
        id: id,
        toolId: toolId,
        path: path,
        description: description,
        type: type,
        position: position,
        isPrimary: isPrimary,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap({bool includeId = true}) {
    final map = <String, Object?>{
      'tool_id': toolId,
      'path': path,
      'description': description,
      'type': type,
      'position': position,
      'is_primary': isPrimary ? 1 : 0,
      'created_at': createdAt,
    };
    if (includeId && id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory ToolImage.fromMap(Map<String, Object?> map) => ToolImage(
        id: map['id'] as int?,
        toolId: (map['tool_id'] as num?)?.toInt() ?? 0,
        path: (map['path'] as String?) ?? '',
        description: (map['description'] as String?) ?? '',
        type: (map['type'] as String?) ?? 'General',
        position: (map['position'] as num?)?.toInt() ?? 0,
        isPrimary: ((map['is_primary'] as num?)?.toInt() ?? 0) == 1,
        createdAt: (map['created_at'] as String?) ?? '',
      );
}

const toolTypes = <String>[
  'Herramienta manual',
  'Herramienta eléctrica',
  'Repuesto',
  'Consumible',
];

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
    this.type = '',
    List<ToolImage>? images,
  }) : images = images ?? <ToolImage>[];

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
  String type;
  List<ToolImage> images;

  String get imagePath {
    if (images.isEmpty) return '';
    final primary = images.where((image) => image.isPrimary);
    return primary.isNotEmpty ? primary.first.path : images.first.path;
  }

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
        type: type,
        images: images.map((image) => image.copy()).toList(),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'description_delta': descriptionDelta,
        'barcode': barcode,
        'quantity': quantity,
        'unit': unit,
        'minimum_stock': minimumStock,
        'purchase_price': purchasePrice,
        'condition': condition,
        'tool_type': type,
        // Se conserva para compatibilidad con versiones antiguas.
        'image_path': imagePath,
      };

  factory ToolItem.fromMap(Map<String, Object?> map) => ToolItem(
        id: map['id'] as int,
        name: (map['name'] as String?) ?? '',
        description: (map['description'] as String?) ?? '',
        descriptionDelta: (map['description_delta'] as String?) ?? '',
        barcode: (map['barcode'] as String?) ?? '',
        quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
        unit: (map['unit'] as String?) ?? 'ud',
        minimumStock: (map['minimum_stock'] as num?)?.toDouble() ?? 0,
        purchasePrice: (map['purchase_price'] as num?)?.toDouble() ?? 0,
        condition: (map['condition'] as String?) ?? 'Bueno',
        type: (map['tool_type'] as String?) ?? '',
      );
}

class DatabaseStats {
  const DatabaseStats({
    required this.tools,
    required this.images,
    required this.databaseBytes,
    required this.imagesBytes,
  });

  final int tools;
  final int images;
  final int databaseBytes;
  final int imagesBytes;
}

class ToolsDatabase {
  ToolsDatabase._();

  static final ToolsDatabase instance = ToolsDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final base = await getDatabasesPath();
    final path = p.join(base, 'gestor_herramientas.db');

    _database = await openDatabase(
      path,
      version: 4,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tools (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            description_delta TEXT NOT NULL DEFAULT '',
            barcode TEXT NOT NULL DEFAULT '',
            quantity REAL NOT NULL DEFAULT 0,
            unit TEXT NOT NULL DEFAULT 'ud',
            minimum_stock REAL NOT NULL DEFAULT 0,
            purchase_price REAL NOT NULL DEFAULT 0,
            condition TEXT NOT NULL DEFAULT 'Bueno',
            tool_type TEXT NOT NULL DEFAULT '',
            image_path TEXT NOT NULL DEFAULT ''
          )
        ''');

        await _createToolImagesTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE tools ADD COLUMN image_path TEXT NOT NULL DEFAULT ''",
          );
        }

        if (oldVersion < 3) {
          await _createToolImagesTable(db);
          await db.execute('''
            INSERT INTO tool_images (
              tool_id, path, description, type, position, is_primary, created_at
            )
            SELECT
              id,
              image_path,
              '',
              'General',
              0,
              1,
              datetime('now')
            FROM tools
            WHERE TRIM(COALESCE(image_path, '')) <> ''
          ''');
        }

        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE tools ADD COLUMN tool_type TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );

    return _database!;
  }

  static Future<void> _createToolImagesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tool_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tool_id INTEGER NOT NULL,
        path TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'General',
        position INTEGER NOT NULL DEFAULT 0,
        is_primary INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (tool_id) REFERENCES tools(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tool_images_tool_id '
      'ON tool_images(tool_id)',
    );
  }

  Future<List<ToolItem>> loadTools() async {
    final db = await database;
    final rows = await db.query('tools', orderBy: 'id DESC');
    final tools = rows.map(ToolItem.fromMap).toList();

    if (tools.isEmpty) return tools;

    final imageRows = await db.query(
      'tool_images',
      orderBy: 'tool_id ASC, is_primary DESC, position ASC, id ASC',
    );

    final byTool = <int, List<ToolImage>>{};
    for (final row in imageRows) {
      final image = ToolImage.fromMap(row);
      byTool.putIfAbsent(image.toolId, () => <ToolImage>[]).add(image);
    }

    for (final tool in tools) {
      tool.images = byTool[tool.id] ?? <ToolImage>[];

      // Protección extra para bases antiguas que no hubieran migrado la foto.
      if (tool.images.isEmpty) {
        final legacyPath =
            (rows.firstWhere((row) => row['id'] == tool.id)['image_path']
                    as String?) ??
                '';
        if (legacyPath.trim().isNotEmpty) {
          tool.images = [
            ToolImage(
              toolId: tool.id,
              path: legacyPath,
              position: 0,
              isPrimary: true,
            ),
          ];
        }
      }
    }

    return tools;
  }

  Future<List<ToolImage>> loadImages(int toolId) async {
    final db = await database;
    final rows = await db.query(
      'tool_images',
      where: 'tool_id = ?',
      whereArgs: [toolId],
      orderBy: 'is_primary DESC, position ASC, id ASC',
    );
    return rows.map(ToolImage.fromMap).toList();
  }

  Future<void> saveTool(ToolItem item) async {
    final db = await database;

    final oldRows = await db.query(
      'tool_images',
      columns: ['path'],
      where: 'tool_id = ?',
      whereArgs: [item.id],
    );
    final oldPaths = oldRows
        .map((row) => (row['path'] as String?) ?? '')
        .where((path) => path.isNotEmpty)
        .toSet();

    _normalizeImages(item);

    await db.transaction((txn) async {
      await txn.insert(
        'tools',
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'tool_images',
        where: 'tool_id = ?',
        whereArgs: [item.id],
      );

      for (final image in item.images) {
        image.toolId = item.id;
        await txn.insert(
          'tool_images',
          image.toMap(includeId: false),
        );
      }
    });

    final newPaths = item.images.map((image) => image.path).toSet();
    final stalePaths = oldPaths.difference(newPaths);

    for (final path in stalePaths) {
      final count = Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM tool_images WHERE path = ?',
              [path],
            ),
          ) ??
          0;
      if (count == 0) {
        final file = File(path);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    }
  }

  void _normalizeImages(ToolItem item) {
    for (var index = 0; index < item.images.length; index++) {
      final image = item.images[index];
      image.toolId = item.id;
      image.position = index;
    }

    if (item.images.isEmpty) return;

    var primaryIndex = item.images.indexWhere((image) => image.isPrimary);
    if (primaryIndex < 0) primaryIndex = 0;

    for (var index = 0; index < item.images.length; index++) {
      item.images[index].isPrimary = index == primaryIndex;
    }
  }

  Future<void> seedIfEmpty(List<ToolItem> defaults) async {
    final db = await database;
    final countResult =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM tools'));
    if ((countResult ?? 0) != 0) return;

    final batch = db.batch();
    for (final item in defaults) {
      batch.insert('tools', item.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<DatabaseStats> getStats() async {
    final db = await database;

    final toolsCount =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM tools')) ??
            0;
    final imagesCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM tool_images'),
        ) ??
        0;

    final path = await databasePath;
    final dbFile = File(path);
    final databaseBytes = await dbFile.exists() ? await dbFile.length() : 0;

    final docs = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(docs.path, 'tool_images'));
    final imagesBytes = await _directorySize(imagesDir);

    return DatabaseStats(
      tools: toolsCount,
      images: imagesCount,
      databaseBytes: databaseBytes,
      imagesBytes: imagesBytes,
    );
  }

  Future<String> integrityCheck() async {
    final db = await database;
    final rows = await db.rawQuery('PRAGMA integrity_check');
    if (rows.isEmpty) return 'Sin resultado';

    final value = rows.first.values.isEmpty ? null : rows.first.values.first;
    return value?.toString() ?? 'Sin resultado';
  }

  Future<List<Map<String, Object?>>> databaseOverview() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        t.id,
        t.name,
        t.barcode,
        t.tool_type,
        COUNT(i.id) AS image_count
      FROM tools t
      LEFT JOIN tool_images i ON i.tool_id = t.id
      GROUP BY t.id, t.name, t.barcode, t.tool_type
      ORDER BY t.id DESC
    ''');
  }

  Future<int> _directorySize(Directory directory) async {
    if (!await directory.exists()) return 0;

    var total = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<String> get databasePath async {
    final base = await getDatabasesPath();
    return p.join(base, 'gestor_herramientas.db');
  }

  Future<void> closeForBackup() async {
    final db = _database;
    if (db != null) {
      try {
        await db.execute('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {}
      await db.close();
      _database = null;
    }
  }

  Future<void> reopen() async {
    await database;
  }
}

class BackupManager {
  BackupManager._();

  static const int formatVersion = 1;

  static Future<Directory> _imagesDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'tool_images'));
  }

  static String _stamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  static Future<File> createBackup() async {
    final temp = await getTemporaryDirectory();
    final stamp = _stamp();
    final workDir = Directory(p.join(temp.path, 'gh_backup_work_$stamp'));
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
    await workDir.create(recursive: true);

    final databasePath = await ToolsDatabase.instance.databasePath;
    final imagesDir = await _imagesDirectory();

    await ToolsDatabase.instance.closeForBackup();

    try {
      final dbFile = File(databasePath);
      if (!await dbFile.exists()) {
        throw StateError('No se ha encontrado la base de datos');
      }

      final databaseDir = Directory(p.join(workDir.path, 'database'));
      await databaseDir.create(recursive: true);
      await dbFile.copy(
        p.join(databaseDir.path, 'gestor_herramientas.db'),
      );

      final backupImagesDir = Directory(p.join(workDir.path, 'tool_images'));
      if (await imagesDir.exists()) {
        await _copyDirectory(imagesDir, backupImagesDir);
      } else {
        await backupImagesDir.create(recursive: true);
      }

      final manifest = <String, Object?>{
        'format': 'gestor_herramientas_backup',
        'format_version': formatVersion,
        'created_at': DateTime.now().toIso8601String(),
        'database': 'database/gestor_herramientas.db',
        'images': 'tool_images',
        'note':
            'Copia completa de SQLite e imágenes. Incluye automáticamente campos futuros guardados en la base de datos.',
      };
      await File(p.join(workDir.path, 'manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true,
      );

      final archive = Archive();
      await _addDirectoryToArchive(archive, workDir, workDir.path);

      final zipBytes = ZipEncoder().encode(archive);

      final output = File(
        p.join(temp.path, 'gestor_herramientas_backup_$stamp.zip'),
      );
      await output.writeAsBytes(zipBytes, flush: true);
      return output;
    } finally {
      await ToolsDatabase.instance.reopen();
      if (await workDir.exists()) {
        try {
          await workDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  static Future<void> restoreBackup(String zipPath) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw StateError('No se encuentra el archivo de copia');
    }

    final temp = await getTemporaryDirectory();
    final stamp = _stamp();
    final restoreDir = Directory(p.join(temp.path, 'gh_restore_$stamp'));
    if (await restoreDir.exists()) {
      await restoreDir.delete(recursive: true);
    }
    await restoreDir.create(recursive: true);

    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);

      for (final entry in archive) {
        final normalized = p.normalize(entry.name);
        if (p.isAbsolute(normalized) ||
            normalized == '..' ||
            normalized.startsWith('../') ||
            normalized.contains('/../')) {
          throw const FormatException('La copia contiene una ruta no válida');
        }

        final targetPath = p.join(restoreDir.path, normalized);
        if (entry.isFile) {
          final output = File(targetPath);
          await output.parent.create(recursive: true);
          await output.writeAsBytes(entry.content as List<int>, flush: true);
        } else {
          await Directory(targetPath).create(recursive: true);
        }
      }

      final manifestFile = File(p.join(restoreDir.path, 'manifest.json'));
      final restoredDb = File(
        p.join(restoreDir.path, 'database', 'gestor_herramientas.db'),
      );

      if (!await manifestFile.exists() || !await restoredDb.exists()) {
        throw const FormatException(
          'El archivo no es una copia válida del Gestor de Herramientas',
        );
      }

      final manifestRaw = jsonDecode(await manifestFile.readAsString());
      if (manifestRaw is! Map ||
          manifestRaw['format'] != 'gestor_herramientas_backup') {
        throw const FormatException('Formato de copia no reconocido');
      }

      final version = (manifestRaw['format_version'] as num?)?.toInt() ?? 0;
      if (version > formatVersion) {
        throw const FormatException(
          'La copia fue creada por una versión más nueva de la aplicación',
        );
      }

      final dbDestination = await ToolsDatabase.instance.databasePath;
      final imagesDestination = await _imagesDirectory();
      final restoredImages = Directory(
        p.join(restoreDir.path, 'tool_images'),
      );

      await ToolsDatabase.instance.closeForBackup();

      try {
        final destinationDbFile = File(dbDestination);
        await destinationDbFile.parent.create(recursive: true);
        await restoredDb.copy(dbDestination);

        if (await imagesDestination.exists()) {
          await imagesDestination.delete(recursive: true);
        }

        if (await restoredImages.exists()) {
          await _copyDirectory(restoredImages, imagesDestination);
        } else {
          await imagesDestination.create(recursive: true);
        }
      } finally {
        await ToolsDatabase.instance.reopen();
      }
    } finally {
      if (await restoreDir.exists()) {
        try {
          await restoreDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  static Future<void> _copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);

    await for (final entity in source.list(recursive: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        await _copyDirectory(
          entity,
          Directory(p.join(destination.path, name)),
        );
      } else if (entity is File) {
        await entity.copy(p.join(destination.path, name));
      }
    }
  }

  static Future<void> _addDirectoryToArchive(
    Archive archive,
    Directory directory,
    String rootPath,
  ) async {
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) continue;

      final relative = p.relative(entity.path, from: rootPath);
      final archiveName = relative.replaceAll('\\', '/');
      final data = await entity.readAsBytes();
      archive.addFile(ArchiveFile(archiveName, data.length, data));
    }
  }
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

  final List<ToolItem> _defaultItems = [
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

  final List<ToolItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    await ToolsDatabase.instance.seedIfEmpty(_defaultItems);
    final items = await ToolsDatabase.instance.loadTools();
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(items);
      _loading = false;
    });
  }

  String get _query => _searchController.text.trim().toLowerCase();

  List<ToolItem> get _visibleItems {
    if (_query.isEmpty) return _items;
    return _items
        .where(
          (item) =>
              item.name.toLowerCase().contains(_query) ||
              item.description.toLowerCase().contains(_query) ||
              item.barcode.toLowerCase().contains(_query) ||
              item.type.toLowerCase().contains(_query),
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

    await ToolsDatabase.instance.saveTool(result);

    if (!mounted) return;
    setState(() {
      final index = _items.indexWhere((element) => element.id == result.id);
      if (index >= 0) {
        _items[index] = result;
      } else {
        _items.insert(0, result);
      }
    });
  }

  Future<void> _createBackup() async {
    try {
      final backup = await BackupManager.createBackup();
      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(backup.path)],
        subject: 'Copia de seguridad · Gestor de Herramientas',
        text:
            'Copia completa de la base de datos y las imágenes del Gestor de Herramientas.',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear la copia: $error')),
      );
    }
  }

  Future<bool> _restoreBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      allowMultiple: false,
    );

    final path = picked?.files.single.path;
    if (path == null || !mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.restore),
        title: const Text('Restaurar copia'),
        content: const Text(
          'Se sustituirán la base de datos y las imágenes actuales por las '
          'contenidas en la copia. Esta operación no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      await BackupManager.restoreBackup(path);
      await _loadItems();
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copia restaurada correctamente'),
        ),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo restaurar la copia: $error')),
      );
      return false;
    }
  }

  Future<void> _openDatabaseManager() async {
    final restored = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DatabaseManagementPage(
          onCreateBackup: _createBackup,
          onRestoreBackup: _restoreBackup,
        ),
      ),
    );

    if (restored == true) {
      await _loadItems();
    }
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
          'Mis herramientas · QUILL V12',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'database':
                  _openDatabaseManager();
                case 'backup':
                  _createBackup();
                case 'restore':
                  _restoreBackup();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'database',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.storage_outlined),
                  title: Text('Gestión de base de datos'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'backup',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.backup_outlined),
                  title: Text('Crear copia de seguridad'),
                ),
              ),
              PopupMenuItem(
                value: 'restore',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.restore),
                  title: Text('Restaurar copia'),
                ),
              ),
            ],
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
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
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
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEAF4FE),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: item.imagePath.isNotEmpty &&
                                            File(item.imagePath).existsSync()
                                        ? Image.file(
                                            File(item.imagePath),
                                            fit: BoxFit.cover,
                                          )
                                        : const Icon(
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

class DatabaseManagementPage extends StatefulWidget {
  const DatabaseManagementPage({
    super.key,
    required this.onCreateBackup,
    required this.onRestoreBackup,
  });

  final Future<void> Function() onCreateBackup;
  final Future<bool> Function() onRestoreBackup;

  @override
  State<DatabaseManagementPage> createState() =>
      _DatabaseManagementPageState();
}

class _DatabaseManagementPageState extends State<DatabaseManagementPage> {
  late Future<DatabaseStats> _stats;
  late Future<List<Map<String, Object?>>> _overview;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _stats = ToolsDatabase.instance.getStats();
    _overview = ToolsDatabase.instance.databaseOverview();
  }

  void _refreshUi() {
    setState(_refresh);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  Future<void> _checkIntegrity() async {
    try {
      final result = await ToolsDatabase.instance.integrityCheck();
      if (!mounted) return;

      final ok = result.trim().toLowerCase() == 'ok';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            size: 36,
          ),
          title: Text(ok ? 'Base de datos correcta' : 'Resultado de comprobación'),
          content: Text(
            ok
                ? 'SQLite no ha encontrado errores de integridad.'
                : result,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo comprobar la base de datos: $error')),
      );
    }
  }

  Future<void> _restore() async {
    final restored = await widget.onRestoreBackup();
    if (!mounted || !restored) return;
    _refreshUi();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Gestión de base de datos',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _refreshUi(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              FutureBuilder<DatabaseStats>(
                future: _stats,
                builder: (context, snapshot) {
                  final stats = snapshot.data;
                  return Row(
                    children: [
                      Expanded(
                        child: _DatabaseStatCard(
                          icon: Icons.handyman_outlined,
                          label: 'Herramientas',
                          value: stats == null ? '—' : '${stats.tools}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DatabaseStatCard(
                          icon: Icons.photo_library_outlined,
                          label: 'Imágenes',
                          value: stats == null ? '—' : '${stats.images}',
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              FutureBuilder<DatabaseStats>(
                future: _stats,
                builder: (context, snapshot) {
                  final stats = snapshot.data;
                  return Row(
                    children: [
                      Expanded(
                        child: _DatabaseStatCard(
                          icon: Icons.storage_outlined,
                          label: 'SQLite',
                          value: stats == null
                              ? '—'
                              : _formatBytes(stats.databaseBytes),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DatabaseStatCard(
                          icon: Icons.folder_outlined,
                          label: 'Fotos',
                          value: stats == null
                              ? '—'
                              : _formatBytes(stats.imagesBytes),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              const SectionTitle('Seguridad y mantenimiento'),
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: const Text('Crear copia de seguridad'),
                      subtitle: const Text(
                        'Guarda SQLite y todas las imágenes en un ZIP.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: widget.onCreateBackup,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.restore),
                      title: const Text('Restaurar copia'),
                      subtitle: const Text(
                        'Recupera herramientas, campos e imágenes.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _restore,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.health_and_safety_outlined),
                      title: const Text('Comprobar integridad'),
                      subtitle: const Text(
                        'Verifica que la base SQLite no tenga errores.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _checkIntegrity,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: SectionTitle('Registros guardados'),
                  ),
                  IconButton(
                    tooltip: 'Actualizar',
                    onPressed: _refreshUi,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, Object?>>>(
                future: _overview,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No se pudieron leer los registros: ${snapshot.error}',
                      ),
                    );
                  }

                  final rows = snapshot.data ?? const [];
                  if (rows.isEmpty) {
                    return const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('No hay herramientas guardadas.'),
                      ),
                    );
                  }

                  return Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var index = 0; index < rows.length; index++) ...[
                          Builder(
                            builder: (context) {
                              final row = rows[index];
                              final id = row['id'] ?? '';
                              final name = (row['name'] as String?) ?? '';
                              final barcode =
                                  (row['barcode'] as String?) ?? '';
                              final toolType =
                                  (row['tool_type'] as String?) ?? '';
                              final imageCount =
                                  (row['image_count'] as num?)?.toInt() ?? 0;

                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  child: Text('$id'),
                                ),
                                title: Text(
                                  name.isEmpty ? 'Sin nombre' : name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    if (toolType.isNotEmpty) toolType,
                                    if (barcode.isNotEmpty) barcode,
                                    '$imageCount imágenes',
                                  ].join(' · '),
                                ),
                              );
                            },
                          ),
                          if (index < rows.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DatabaseStatCard extends StatelessWidget {
  const _DatabaseStatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD7DDE3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF168BD2)),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF72777D),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
  late String _type;
  late List<ToolImage> _images;
  final ImagePicker _imagePicker = ImagePicker();

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
    _type = item?.type ?? '';
    _images = item?.images.map((image) => image.copy()).toList() ??
        <ToolImage>[];
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
      type: _type,
      images: _images.map((image) => image.copy()).toList(),
    );

    Navigator.of(context).pop(result);
  }

  Future<Directory> _toolImagesDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(docs.path, 'tool_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  void _appendStoredImage(String path) {
    setState(() {
      final image = ToolImage(
        toolId: widget.item?.id ?? widget.nextId,
        path: path,
        position: _images.length,
        isPrimary: _images.isEmpty,
      );
      _images.add(image);
    });
  }

  Future<String> _copyPickedImage(XFile picked) async {
    final imagesDir = await _toolImagesDirectory();
    final extension = p.extension(picked.path).isEmpty
        ? '.jpg'
        : p.extension(picked.path);
    final targetPath = p.join(
      imagesDir.path,
      'tool_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    final stored = await File(picked.path).copy(targetPath);
    return stored.path;
  }

  Future<void> _storePickedImage(ImageSource source) async {
    if (source == ImageSource.gallery) {
      final picked = await _imagePicker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (picked.isEmpty) return;

      for (final image in picked) {
        final storedPath = await _copyPickedImage(image);
        if (!mounted) return;
        _appendStoredImage(storedPath);
      }
      return;
    }

    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1800,
    );
    if (picked == null) return;

    final storedPath = await _copyPickedImage(picked);
    if (!mounted) return;
    _appendStoredImage(storedPath);
  }

  Future<void> _downloadImageFromUrl() async {
    final controller = TextEditingController();

    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Imagen desde URL'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'URL de la imagen',
            hintText: 'https://...',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Descargar'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (url == null || url.trim().isEmpty) return;

    try {
      final uri = Uri.parse(url.trim());
      if (!(uri.scheme == 'http' || uri.scheme == 'https')) {
        throw const FormatException('La URL debe comenzar por http:// o https://');
      }

      final client = HttpClient();
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'GestorHerramientas/1.0',
      );
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        client.close(force: true);
        throw HttpException(
          'Error HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final contentType = response.headers.contentType?.mimeType ?? '';
      if (!contentType.startsWith('image/')) {
        client.close(force: true);
        throw const FormatException('La dirección no devuelve una imagen');
      }

      String extension = p.extension(uri.path).toLowerCase();
      if (extension.isEmpty || extension.length > 6) {
        extension = switch (contentType) {
          'image/png' => '.png',
          'image/webp' => '.webp',
          'image/gif' => '.gif',
          _ => '.jpg',
        };
      }

      final imagesDir = await _toolImagesDirectory();
      final targetPath = p.join(
        imagesDir.path,
        'tool_url_${DateTime.now().millisecondsSinceEpoch}$extension',
      );
      final file = File(targetPath);
      await response.pipe(file.openWrite());
      client.close();

      if (!mounted) return;
      _appendStoredImage(file.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo descargar la imagen: $error'),
        ),
      );
    }
  }

  Future<void> _openAiImageOption() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.auto_awesome, size: 34),
        title: const Text('Imagen con IA'),
        content: const Text(
          'La opción de IA ya está incluida en el gestor. '
          'Para generar imágenes desde la APK falta conectar un servicio de IA '
          'mediante una API segura; no se debe guardar una clave privada dentro de la aplicación.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  void _setPrimaryImage(ToolImage image) {
    setState(() {
      for (final candidate in _images) {
        candidate.isPrimary = identical(candidate, image);
      }
    });
  }

  void _removeImage(ToolImage image) {
    final wasPrimary = image.isPrimary;
    setState(() {
      _images.remove(image);
      for (var index = 0; index < _images.length; index++) {
        _images[index].position = index;
      }
      if (wasPrimary && _images.isNotEmpty) {
        for (final candidate in _images) {
          candidate.isPrimary = false;
        }
        _images.first.isPrimary = true;
      }
    });
  }

  Future<void> _editImageMetadata(ToolImage image) async {
    final descriptionController =
        TextEditingController(text: image.description);
    var selectedType = image.type;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Datos de la imagen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                ),
                items: const [
                  DropdownMenuItem(value: 'General', child: Text('General')),
                  DropdownMenuItem(
                    value: 'Placa',
                    child: Text('Placa de características'),
                  ),
                  DropdownMenuItem(
                    value: 'Avería',
                    child: Text('Avería / incidencia'),
                  ),
                  DropdownMenuItem(
                    value: 'Documento',
                    child: Text('Documento / factura'),
                  ),
                  DropdownMenuItem(
                    value: 'Detalle',
                    child: Text('Detalle'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedType = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Descripción de la imagen',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                {
                  'type': selectedType,
                  'description': descriptionController.text.trim(),
                },
              ),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    descriptionController.dispose();
    if (result == null) return;

    setState(() {
      image.type = result['type'] ?? 'General';
      image.description = result['description'] ?? '';
    });
  }

  Future<void> _openImage(ToolImage image) async {
    if (!File(image.path).existsSync()) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Image.file(
                    File(image.path),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              if (image.description.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text(
                    image.description,
                    textAlign: TextAlign.center,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: image.isPrimary
                          ? null
                          : () {
                              _setPrimaryImage(image);
                              Navigator.pop(dialogContext);
                            },
                      icon: const Icon(Icons.star_outline),
                      label: Text(
                        image.isPrimary ? 'Principal' : 'Hacer principal',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _editImageMetadata(image);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Datos'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _removeImage(image);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Eliminar'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAllImages() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    Text(
                      'Imágenes (${_images.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: _images.length,
                  itemBuilder: (context, index) {
                    final image = _images[index];
                    return _ToolImageThumbnail(
                      image: image,
                      size: double.infinity,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _openImage(image);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
          _isEditing ? 'Editar artículo · QUILL V12' : 'Nuevo artículo · QUILL V12',
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
              DropdownButtonFormField<String>(
                initialValue: _type.isEmpty ? null : _type,
                decoration: const InputDecoration(
                  labelText: 'Tipo*',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                hint: const Text('Selecciona el tipo'),
                items: toolTypes
                    .map(
                      (type) => DropdownMenuItem<String>(
                        value: type,
                        child: Text(type),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _type = value ?? '');
                },
                validator: (value) =>
                    value == null || value.isEmpty ? 'Selecciona el tipo' : null,
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
              Row(
                children: [
                  Text(
                    _images.length == 1
                        ? '1 imagen'
                        : '${_images.length} imágenes',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6F747A),
                    ),
                  ),
                  const Spacer(),
                  if (_images.length > 4)
                    TextButton(
                      onPressed: _openAllImages,
                      child: Text('Ver todas (${_images.length})'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFD7DDE3),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CompactImageToolbar(
                      onCamera: () => _storePickedImage(ImageSource.camera),
                      onUrl: _downloadImageFromUrl,
                      onAi: _openAiImageOption,
                      onGallery: () => _storePickedImage(ImageSource.gallery),
                    ),
                    if (_images.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                        child: Text(
                          'Sin imágenes. Puedes añadir tantas como necesites.',
                          style: TextStyle(
                            color: Color(0xFF7A7F85),
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 104,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(8),
                          scrollDirection: Axis.horizontal,
                          itemCount: _images.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final image = _images[index];
                            return _ToolImageThumbnail(
                              image: image,
                              size: 88,
                              onTap: () => _openImage(image),
                            );
                          },
                        ),
                      ),
                  ],
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

class _CompactImageToolbar extends StatelessWidget {
  const _CompactImageToolbar({
    required this.onCamera,
    required this.onUrl,
    required this.onAi,
    required this.onGallery,
  });

  final VoidCallback onCamera;
  final VoidCallback onUrl;
  final VoidCallback onAi;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      color: const Color(0xFFF0F1F2),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          _CompactImageAction(
            icon: Icons.photo_camera,
            tooltip: 'Cámara',
            onTap: onCamera,
          ),
          _CompactImageAction(
            icon: Icons.link,
            tooltip: 'URL',
            onTap: onUrl,
          ),
          _CompactImageAction(
            icon: Icons.auto_awesome,
            tooltip: 'IA',
            onTap: onAi,
          ),
          _CompactImageAction(
            icon: Icons.photo_library_outlined,
            tooltip: 'Galería',
            onTap: onGallery,
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(right: 10, left: 4),
            child: Text(
              'IMÁGENES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7A7F85),
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactImageAction extends StatelessWidget {
  const _CompactImageAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(
        minWidth: 44,
        minHeight: 44,
      ),
      iconSize: 25,
      color: const Color(0xFF39444D),
      icon: Icon(icon),
    );
  }
}

class _ToolImageThumbnail extends StatelessWidget {
  const _ToolImageThumbnail({
    required this.image,
    required this.size,
    required this.onTap,
  });

  final ToolImage image;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final exists = File(image.path).existsSync();

    return SizedBox(
      width: size.isFinite ? size : null,
      height: size.isFinite ? size : null,
      child: Material(
        color: const Color(0xFFE9EDF0),
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: exists ? onTap : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (exists)
                Image.file(
                  File(image.path),
                  fit: BoxFit.cover,
                )
              else
                const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFF8A9096),
                  ),
                ),
              if (image.isPrimary)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.star,
                      size: 16,
                      color: Colors.amber,
                    ),
                  ),
                ),
              Positioned(
                left: 4,
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    image.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
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
