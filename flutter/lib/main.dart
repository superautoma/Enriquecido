import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() {
  runApp(const RichTextTestApp());
}

class RichTextTestApp extends StatelessWidget {
  const RichTextTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Prueba editor enriquecido',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF168BD2),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEAF4FE),
          foregroundColor: Color(0xFF20242A),
          elevation: 0,
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es'),
        Locale('en'),
      ],
      home: const EditorTestPage(),
    );
  }
}

class EditorTestPage extends StatefulWidget {
  const EditorTestPage({super.key});

  @override
  State<EditorTestPage> createState() => _EditorTestPageState();
}

class _EditorTestPageState extends State<EditorTestPage> {
  final TextEditingController _nameController = TextEditingController();
  final QuillController _quillController = QuillController.basic();
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();

  Database? _db;
  bool _loading = true;
  bool _saving = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _openDb();
  }

  Future<void> _openDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'richtext_flutter_test.db');

    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (database, version) async {
        await database.execute(
          'CREATE TABLE article ('
          'id INTEGER PRIMARY KEY, '
          'name TEXT NOT NULL, '
          'description_delta TEXT NOT NULL'
          ')',
        );

        await database.insert('article', {
          'id': 1,
          'name': '',
          'description_delta': jsonEncode([
            {'insert': '\n'}
          ]),
        });
      },
    );

    final rows = await db.query(
      'article',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final row = rows.first;
      _nameController.text = (row['name'] as String?) ?? '';

      final raw = (row['description_delta'] as String?) ?? '';
      if (raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw) as List<dynamic>;
          _quillController.document = Document.fromJson(decoded);
        } catch (_) {}
      }
    }

    if (!mounted) return;

    setState(() {
      _db = db;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_db == null) return;

    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe un nombre antes de guardar.'),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _status = 'Guardando…';
    });

    final deltaJson = jsonEncode(
      _quillController.document.toDelta().toJson(),
    );

    await _db!.update(
      'article',
      {
        'name': name,
        'description_delta': deltaJson,
      },
      where: 'id = ?',
      whereArgs: [1],
    );

    if (!mounted) return;

    setState(() {
      _saving = false;
      _status = 'Guardado correctamente en SQLite';
    });

    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quillController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    _db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Prueba editor enriquecido',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Nombre*',
                style: TextStyle(
                  fontSize: 17,
                  color: Color(0xFF62666B),
                ),
              ),
              TextField(
                controller: _nameController,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.only(top: 8, bottom: 8),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      width: 1.5,
                      color: Color(0xFF5E6268),
                    ),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      width: 2,
                      color: Color(0xFF168BD2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Descripción',
                style: TextStyle(
                  fontSize: 17,
                  color: Color(0xFF62666B),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: const Color(0xFFD4DAE0)),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: QuillSimpleToolbar(
                    controller: _quillController,
                    config: const QuillSimpleToolbarConfig(
                      axis: Axis.horizontal,
                      multiRowsDisplay: false,
                      showDividers: true,
                      showBoldButton: true,
                      showItalicButton: true,
                      showUnderLineButton: true,
                      showStrikeThrough: true,
                      showColorButton: true,
                      showBackgroundColorButton: true,
                      showFontSize: true,
                      showAlignmentButtons: true,
                      showLeftAlignment: true,
                      showCenterAlignment: true,
                      showRightAlignment: true,
                      showJustifyAlignment: true,
                      showListNumbers: true,
                      showListBullets: true,
                      showUndo: true,
                      showRedo: true,
                      showClearFormat: true,
                      showFontFamily: false,
                      showInlineCode: false,
                      showHeaderStyle: false,
                      showListCheck: false,
                      showCodeBlock: false,
                      showQuote: false,
                      showIndent: false,
                      showLink: false,
                      showDirection: false,
                      showSearchButton: false,
                      showSubscript: false,
                      showSuperscript: false,
                    ),
                  ),
                ),
              ),
              Container(
                height: 330,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFC8CDD3)),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                ),
                child: QuillEditor(
                  focusNode: _editorFocusNode,
                  scrollController: _editorScrollController,
                  controller: _quillController,
                  config: const QuillEditorConfig(
                    placeholder: 'Escribe aquí la descripción…',
                    padding: EdgeInsets.all(12),
                    autoFocus: false,
                    expands: true,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Guardando…' : 'Guardar'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF168BD2),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF4E7A55),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                'La descripción se guarda como Quill Delta JSON en SQLite. '
                'No usa WebView, Chrome ni HTML.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF858A90),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
