import 'package:flutter/material.dart';
import '../../../data/models.dart';
import '../annotations/annotated_article.dart';
import '../annotations/paragraph_location.dart';
import '../reading_position.dart';
import 'document_selection.dart';

class TextDocumentView extends StatefulWidget {
  const TextDocumentView({
    required this.content,
    required this.markdown,
    required this.fontSize,
    required this.position,
    required this.onQuote,
    this.notes = const [],
    this.section = 0,
    this.onCreateNote,
    this.onOpenNotes,
    this.revealNote,
    this.revealRequest = 0,
    this.onUnresolved,
    super.key,
  });
  final String content;
  final bool markdown;
  final double fontSize;
  final ReadingPosition position;
  final ValueChanged<String> onQuote;
  final List<Json> notes;
  final int section, revealRequest;
  final Json? revealNote;
  final ValueChanged<NotePassage>? onCreateNote;
  final void Function(NotePassage, List<Json>)? onOpenNotes;
  final VoidCallback? onUnresolved;
  @override
  State<TextDocumentView> createState() => _TextDocumentViewState();
}

class _TextDocumentViewState extends State<TextDocumentView> {
  final scroll = ScrollController();
  final article = AnnotatedArticleController();
  bool restoring = true;
  @override
  void initState() {
    super.initState();
    scroll.addListener(capture);
    restore();
    reveal();
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
    if (oldWidget.revealRequest != widget.revealRequest) reveal();
  }

  void reveal() {
    final note = widget.revealNote;
    if (note == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final found = await article.reveal(
          note['location'] as String? ?? '',
          note['quote'] as String? ?? '',
        );
        if (!found) widget.onUnresolved?.call();
      });
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DocumentSelection(
    plainText: widget.markdown ? null : widget.content,
    onQuote: widget.onQuote,
    scrollController: scroll,
    onCreateNote: widget.onCreateNote == null
        ? null
        : (quote, first, last) =>
              widget.onCreateNote!(article.selection(quote, first, last)),
    child: AnnotatedArticle(
      controller: article,
      notes: widget.notes,
      section: widget.section,
      scroll: scroll,
      onOpen: (passage, notes) => widget.onOpenNotes?.call(passage, notes),
      content: widget.content,
      markdown: widget.markdown,
      fontSize: widget.fontSize,
    ),
  );
}
