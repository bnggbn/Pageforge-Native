import 'package:flutter/material.dart';
import '../../../data/models.dart';
import '../views/article_body.dart';
import 'note_cloud.dart';
import 'paragraph_index.dart';
import 'paragraph_location.dart';

class AnnotatedArticleController {
  _AnnotatedArticleState? _state;
  NotePassage selection(
    String quote,
    Offset? first,
    Offset? last,
    String Function(Offset) clipBefore,
  ) =>
      _state?.selection(quote, first, last, clipBefore) ??
      NotePassage(quote, '全文筆記');
  Future<bool> reveal(String location, String quote) =>
      _state?.reveal(location, quote) ?? Future.value(false);
}

class AnnotatedArticle extends StatefulWidget {
  const AnnotatedArticle({
    required this.controller,
    required this.content,
    required this.markdown,
    required this.fontSize,
    required this.section,
    required this.notes,
    required this.scroll,
    required this.onOpen,
    super.key,
  });
  final AnnotatedArticleController controller;
  final String content;
  final bool markdown;
  final double fontSize;
  final int section;
  final List<Json> notes;
  final ScrollController scroll;
  final void Function(NotePassage, List<Json>) onOpen;
  @override
  State<AnnotatedArticle> createState() => _AnnotatedArticleState();
}

class _AnnotatedArticleState extends State<AnnotatedArticle> {
  final articleKey = GlobalKey(), rootKey = GlobalKey();
  late ParagraphIndex index = ParagraphIndex(widget.content, widget.section);
  bool scheduled = false;
  double width = 0;
  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    measure();
  }

  @override
  void didUpdateWidget(AnnotatedArticle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._state = null;
      widget.controller._state = this;
    }
    if (oldWidget.content != widget.content ||
        oldWidget.section != widget.section) {
      index = ParagraphIndex(widget.content, widget.section);
    }
    measure();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    measure();
  }

  void measure() {
    if (scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!mounted) return;
      final root = rootKey.currentContext?.findRenderObject(),
          article = articleKey.currentContext?.findRenderObject();
      if (root is RenderBox && article != null) {
        index.measure(root, article, plainText: !widget.markdown);
        setState(() {});
      }
    });
  }

  NotePassage selection(
    String quote,
    Offset? first,
    Offset? last,
    String Function(Offset) clipBefore,
  ) {
    final root = rootKey.currentContext?.findRenderObject();
    if (root is RenderBox && first != null && last != null) {
      final a = index.at(root.globalToLocal(first)),
          b = index.at(root.globalToLocal(last));
      if (a != null && b != null) return noteSelection(quote, a, b, clipBefore);
    }
    final matched = index.resolve('', quote);
    return matched.isEmpty
        ? NotePassage(quote, '全文筆記')
        : noteSelection(quote, matched.first, matched.last, clipBefore);
  }

  NotePassage noteSelection(
    String quote,
    ParagraphEntry first,
    ParagraphEntry last,
    String Function(Offset) clipBefore,
  ) {
    final selected = index.entries;
    final start = selected.indexOf(first), end = selected.indexOf(last);
    final root = rootKey.currentContext?.findRenderObject();
    if (root is RenderBox) {
      for (var i = start + 1; i <= end; i++) {
        if (!selected[i].isHeading) continue;
        final boundary = root.localToGlobal(Offset(0, selected[i].bounds.top));
        return index.passage(clipBefore(boundary), first, selected[i - 1]);
      }
    }
    return index.passage(quote, first, last);
  }

  Future<bool> reveal(String location, String quote) async {
    final matched = index.resolve(location, quote);
    if (matched.isEmpty || !widget.scroll.hasClients) return false;
    final offset = (matched.first.bounds.top - 40).clamp(
      0.0,
      widget.scroll.position.maxScrollExtent,
    );
    widget.scroll.jumpTo(offset);
    return true;
  }

  @override
  void dispose() {
    widget.controller._state = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      if (width != bounds.maxWidth) {
        width = bounds.maxWidth;
        measure();
      }
      final grouped = <ParagraphEntry, List<Json>>{};
      for (final note in widget.notes) {
        for (final paragraph in index.resolve(
          note['location'] as String? ?? '',
          note['quote'] as String? ?? '',
        )) {
          grouped.putIfAbsent(paragraph, () => []).add(note);
        }
      }
      return Stack(
        key: rootKey,
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, NoteCloud.extent + 8, 12),
            child: ArticleBody(
              key: articleKey,
              content: widget.content,
              markdown: widget.markdown,
              fontSize: widget.fontSize,
            ),
          ),
          for (final entry in grouped.entries)
            Positioned(
              left: entry.key.endPoint.dx + 4,
              top: (entry.key.endPoint.dy - NoteCloud.extent / 2).clamp(
                0.0,
                double.infinity,
              ),
              child: NoteCloud(
                key: ValueKey(
                  'cloud-${entry.key.hash}-${entry.key.occurrence}',
                ),
                count: entry.value.length,
                onTap: () => widget.onOpen(
                  index.passage(entry.key.text, entry.key, entry.key),
                  entry.value,
                ),
              ),
            ),
        ],
      );
    },
  );
}
