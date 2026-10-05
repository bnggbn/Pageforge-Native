import 'package:flutter/material.dart';
import 'article_body.dart';
import '../reading_position.dart';
import 'document_selection.dart';

class TextDocumentView extends StatefulWidget {
  const TextDocumentView({
    required this.content,
    required this.markdown,
    required this.fontSize,
    required this.position,
    required this.onQuote,
    super.key,
  });
  final String content;
  final bool markdown;
  final double fontSize;
  final ReadingPosition position;
  final ValueChanged<String> onQuote;
  @override
  State<TextDocumentView> createState() => _TextDocumentViewState();
}

class _TextDocumentViewState extends State<TextDocumentView> {
  final scroll = ScrollController();
  bool restoring = true;
  @override
  void initState() {
    super.initState();
    scroll.addListener(capture);
    restore();
  }

  void capture() {
    if (!restoring && scroll.hasClients) {
      widget.position.remember(scroll.offset, scroll.position.maxScrollExtent);
    }
  }

  void restore() {
    restoring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (scroll.hasClients) {
        scroll.jumpTo(widget.position.ratio * scroll.position.maxScrollExtent);
      }
      restoring = false;
    });
  }

  @override
  void didUpdateWidget(TextDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontSize != widget.fontSize) restore();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DocumentSelection(
    onQuote: widget.onQuote,
    scrollController: scroll,
    child: ArticleBody(
      content: widget.content,
      markdown: widget.markdown,
      fontSize: widget.fontSize,
    ),
  );
}
