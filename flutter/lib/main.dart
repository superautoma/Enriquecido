import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

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
  final _nameController = TextEditingController();
  final _quillController = QuillController.basic();
  final _editorFocusNode = FocusNode();
  final _editorScrollController = ScrollController();

  @override
  void dispose() {
    _nameController.dispose();
    _quillController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  void _save() {
    FocusScope.of(context).unfocus();

    final name = _nameController.text.trim();
    final plainText = _quillController.document.toPlainText().trim();

    String message;
    if (name.isEmpty) {
      message = 'Escribe un nombre.';
    } else if (plainText.isEmpty) {
      message = 'Prueba correcta. Falta escribir una descripción.';
    } else {
      message = 'Prueba correcta. El editor está funcionando.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Prueba editor enriquecido',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
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
                  const SizedBox(height: 18),
                  const Text(
                    'Descripción',
                    style: TextStyle(
                      fontSize: 17,
                      color: Color(0xFF62666B),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 18),
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
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: const Text('Probar / Guardar'),
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
            ),
          ],
        ),
      ),
    );
  }
}
