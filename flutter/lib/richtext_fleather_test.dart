import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(const FleatherRichTextTestApp());
}

class FleatherRichTextTestApp extends StatelessWidget {
  const FleatherRichTextTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Prueba Fleather',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F9FB),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF168BD2),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEAF4FE),
          foregroundColor: Color(0xFF20242A),
          elevation: 0,
        ),
      ),
      localizationsDelegates: const [
        FleatherLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: FleatherLocalizations.supportedLocales,
      home: const FleatherEditorTestPage(),
    );
  }
}

class FleatherEditorTestPage extends StatefulWidget {
  const FleatherEditorTestPage({super.key});

  @override
  State<FleatherEditorTestPage> createState() =>
      _FleatherEditorTestPageState();
}

class _FleatherEditorTestPageState extends State<FleatherEditorTestPage> {
  late final FleatherController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = FleatherController();
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
          'PRUEBA TEXTO ENRIQUECIDO',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              color: const Color(0xFFE8F5E9),
              child: const Text(
                'Prueba aislada con Fleather. La aplicación principal no se modifica.',
                style: TextStyle(
                  color: Color(0xFF1B5E20),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Material(
              color: Colors.white,
              child: FleatherToolbar.basic(
                controller: _controller,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFD7DDE3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FleatherEditor(
                  controller: _controller,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
