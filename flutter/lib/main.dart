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
      title: 'Flutter Rich Text V2',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF168BD2),
          brightness: Brightness.light,
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: FlutterQuillLocalizations.supportedLocales,
      home: const StartPage(),
    );
  }
}

class StartPage extends StatelessWidget {
  const StartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFEAF4FE),
        title: const Text(
          'FLUTTER V2 — PRUEBA BÁSICA',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF81C784)),
              ),
              child: const Text(
                'SI VES ESTE RECUADRO, FLUTTER ESTÁ DIBUJANDO LA PANTALLA CORRECTAMENTE.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1B5E20),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Esta pantalla no contiene todavía el editor Quill. '
              'Así podemos comprobar primero que el problema no está en Flutter.',
              style: TextStyle(fontSize: 17),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RichEditorPage(),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF168BD2),
                minimumSize: const Size.fromHeight(56),
              ),
              child: const Text(
                'ABRIR EDITOR ENRIQUECIDO',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RichEditorPage extends StatefulWidget {
  const RichEditorPage({super.key});

  @override
  State<RichEditorPage> createState() => _RichEditorPageState();
}

class _RichEditorPageState extends State<RichEditorPage> {
  late final QuillController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = QuillController.basic();
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
        backgroundColor: const Color(0xFFEAF4FE),
        title: const Text('Editor enriquecido'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF3CD),
            padding: const EdgeInsets.all(12),
            child: const Text(
              'Si esta franja amarilla aparece pero el editor no, '
              'el problema está dentro de Quill.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: QuillSimpleToolbar(
              controller: _controller,
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
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFB0B7BE)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: QuillEditor(
                controller: _controller,
                focusNode: _focusNode,
                scrollController: _scrollController,
                config: const QuillEditorConfig(
                  placeholder: 'Escribe aquí…',
                  padding: EdgeInsets.all(12),
                  autoFocus: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
