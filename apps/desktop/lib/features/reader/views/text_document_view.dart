import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../reading_position.dart';

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
  Widget build(BuildContext context) => widget.markdown
      ? Markdown(
          data: widget.content,
          selectable: true,
          controller: scroll,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: TextStyle(fontSize: widget.fontSize, height: 1.95),
            h1: TextStyle(fontSize: widget.fontSize * 1.8, height: 1.7),
            h2: TextStyle(fontSize: widget.fontSize * 1.4, height: 1.7),
          ),
          imageBuilder: (uri, title, alt) =>
              Text('[圖片：${alt ?? title ?? '未提供說明'}]'),
          onSelectionChanged: (text, selection, cause) {
            if (text != null && text.isNotEmpty) widget.onQuote(text);
          },
        )
      : SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(28),
          child: SelectionArea(
            onSelectionChanged: (content) {
              if (content != null && content.plainText.isNotEmpty) {
                widget.onQuote(content.plainText);
              }
            },
            child: Text(
              widget.content,
              style: TextStyle(fontSize: widget.fontSize, height: 1.95),
            ),
          ),
        );
}
