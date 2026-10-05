import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(const AppFlowyRichTextTestApp());
}

class AppFlowyRichTextTestApp extends StatelessWidget {
  const AppFlowyRichTextTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Prueba AppFlowy Editor',
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
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        AppFlowyEditorLocalizations.delegate,
      ],
      supportedLocales: AppFlowyEditorLocalizations.delegate.supportedLocales,
      home: const RichTextTestPage(),
    );
  }
}

class RichTextTestPage extends StatefulWidget {
  const RichTextTestPage({super.key});

  @override
  State<RichTextTestPage> createState() => _RichTextTestPageState();
}

class _RichTextTestPageState extends State<RichTextTestPage> {
  late final EditorState editorState;

  @override
  void initState() {
    super.initState();
    editorState = EditorState.blank(withInitialText: true);
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
                'Prueba aislada con AppFlowy Editor. '
                'La aplicación principal no se modifica.',
                style: TextStyle(
                  color: Color(0xFF1B5E20),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              height: 52,
              color: Colors.white,
              child: FixedFormattingToolbar(editorState: editorState),
            ),
            const Divider(height: 1),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFD7DDE3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AppFlowyEditor(
                  editorState: editorState,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FixedFormattingToolbar extends StatelessWidget {
  const FixedFormattingToolbar({
    super.key,
    required this.editorState,
  });

  final EditorState editorState;

  @override
  Widget build(BuildContext context) {
    final items = <IconData>[
      Icons.format_bold,
      Icons.format_italic,
      Icons.format_underlined,
      Icons.format_strikethrough,
      Icons.format_list_bulleted,
      Icons.format_list_numbered,
      Icons.format_align_left,
      Icons.format_align_center,
      Icons.format_align_right,
      Icons.format_align_justify,
    ];

    return ValueListenableBuilder(
      valueListenable: editorState.selectionNotifier,
      builder: (context, selection, _) {
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 2),
          itemBuilder: (_, index) {
            final icon = items[index];
            final active = _isActive(icon, selection);

            return IconButton(
              tooltip: _tooltip(icon),
              icon: Icon(icon),
              color: active
                  ? const Color(0xFF168BD2)
                  : const Color(0xFF30353A),
              onPressed: () => _apply(icon),
            );
          },
        );
      },
    );
  }

  String _tooltip(IconData icon) {
    if (icon == Icons.format_bold) return 'Negrita';
    if (icon == Icons.format_italic) return 'Cursiva';
    if (icon == Icons.format_underlined) return 'Subrayado';
    if (icon == Icons.format_strikethrough) return 'Tachado';
    if (icon == Icons.format_list_bulleted) return 'Viñetas';
    if (icon == Icons.format_list_numbered) return 'Numeración';
    if (icon == Icons.format_align_left) return 'Izquierda';
    if (icon == Icons.format_align_center) return 'Centrar';
    if (icon == Icons.format_align_right) return 'Derecha';
    if (icon == Icons.format_align_justify) return 'Justificar';
    return '';
  }

  bool _isActive(IconData icon, Selection? selection) {
    if (icon == Icons.format_bold) {
      return _isTextDecorationActive(
        selection,
        AppFlowyRichTextKeys.bold,
      );
    }
    if (icon == Icons.format_italic) {
      return _isTextDecorationActive(
        selection,
        AppFlowyRichTextKeys.italic,
      );
    }
    if (icon == Icons.format_underlined) {
      return _isTextDecorationActive(
        selection,
        AppFlowyRichTextKeys.underline,
      );
    }
    if (icon == Icons.format_strikethrough) {
      return _isTextDecorationActive(
        selection,
        AppFlowyRichTextKeys.strikethrough,
      );
    }
    return false;
  }

  bool _isTextDecorationActive(
    Selection? selection,
    String attributeName,
  ) {
    selection = selection ?? editorState.selection;
    if (selection == null) return false;

    final nodes = editorState.getNodesInSelection(selection);

    if (selection.isCollapsed) {
      return editorState.toggledStyle.containsKey(attributeName);
    }

    return nodes.allSatisfyInSelection(selection, (delta) {
      return delta.everyAttributes(
        (attributes) => attributes[attributeName] == true,
      );
    });
  }

  void _apply(IconData icon) {
    if (icon == Icons.format_bold) {
      editorState.toggleAttribute(AppFlowyRichTextKeys.bold);
      return;
    }
    if (icon == Icons.format_italic) {
      editorState.toggleAttribute(AppFlowyRichTextKeys.italic);
      return;
    }
    if (icon == Icons.format_underlined) {
      editorState.toggleAttribute(AppFlowyRichTextKeys.underline);
      return;
    }
    if (icon == Icons.format_strikethrough) {
      editorState.toggleAttribute(AppFlowyRichTextKeys.strikethrough);
      return;
    }

    if (icon == Icons.format_list_bulleted) {
      editorState.formatNode(null, (node) {
        return node.copyWith(
          type: node.type == BulletedListBlockKeys.type
              ? ParagraphBlockKeys.type
              : BulletedListBlockKeys.type,
        );
      });
      return;
    }

    if (icon == Icons.format_list_numbered) {
      editorState.formatNode(null, (node) {
        return node.copyWith(
          type: node.type == NumberedListBlockKeys.type
              ? ParagraphBlockKeys.type
              : NumberedListBlockKeys.type,
        );
      });
      return;
    }

    String? alignment;
    if (icon == Icons.format_align_left) alignment = 'left';
    if (icon == Icons.format_align_center) alignment = 'center';
    if (icon == Icons.format_align_right) alignment = 'right';
    if (icon == Icons.format_align_justify) alignment = 'justify';

    if (alignment != null) {
      editorState.formatNode(null, (node) {
        return node.copyWith(
          attributes: {
            ...node.attributes,
            blockComponentAlign: alignment,
          },
        );
      });
    }
  }
}
