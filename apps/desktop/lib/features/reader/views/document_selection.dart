import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// One selection scope for the article, excluding reader controls and notes.
class DocumentSelection extends StatefulWidget {
  const DocumentSelection({
    required this.child,
    required this.scrollController,
    required this.onQuote,
    this.onCreateNote,
    this.plainText,
    super.key,
  });
  final Widget child;

  /// Exact source for plain text; its Text children retain every source character.
  final String? plainText;
  final ScrollController scrollController;
  final ValueChanged<String> onQuote;
  final void Function(String quote, Offset? first, Offset? last)? onCreateNote;

  @override
  State<DocumentSelection> createState() => _DocumentSelectionState();
}

class _DocumentSelectionState extends State<DocumentSelection> {
  final delegate = _ParagraphSelectionDelegate();

  @override
  void dispose() {
    delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    delegate.plainText = widget.plainText;
    return SelectionArea(
      contextMenuBuilder: (context, region) {
        final selected = delegate.getSelectedContent()?.plainText ?? '';
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: region.contextMenuAnchors,
          buttonItems: [
            if (widget.onCreateNote != null && selected.isNotEmpty)
              ContextMenuButtonItem(
                label: '作筆記',
                onPressed: () {
                  final points = delegate.selectedPoints();
                  region.hideToolbar();
                  widget.onCreateNote!(selected, points.$1, points.$2);
                },
              ),
            ...region.contextMenuButtonItems,
          ],
        );
      },
      onSelectionChanged: (content) {
        if (content != null && content.plainText.isNotEmpty) {
          widget.onQuote(content.plainText);
        }
      },
      child: SingleChildScrollView(
        controller: widget.scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: SelectionContainer(delegate: delegate, child: widget.child),
      ),
    );
  }
}

/// Flutter concatenates selected Text widgets without paragraph separators.
/// Use the same text for the clipboard and quotation, with block boundaries.
class _ParagraphSelectionDelegate extends StaticSelectionContainerDelegate {
  String? plainText;
  SelectedContent? _plainSelection(String source) {
    int offset = 0;
    int? start, end;
    for (final selectable in selectables) {
      final range = selectable.getSelection();
      if (range != null) {
        final first =
            offset + math.min<int>(range.startOffset, range.endOffset);
        final last = offset + math.max<int>(range.startOffset, range.endOffset);
        start = start == null ? first : math.min<int>(start, first);
        end = end == null ? last : math.max<int>(end, last);
      }
      offset += selectable.contentLength;
    }
    // PlainArticle concatenates to the source exactly. Avoid inventing a quote
    // if the layout has not finished registering all of its Text children.
    if (offset != source.length ||
        start == null ||
        end == null ||
        start == end) {
      return null;
    }
    // Dragging past a Text may stop before its final newline. Bridge to the
    // last selected child using source offsets rather than concatenated fragments.
    return SelectedContent(plainText: source.substring(start, end));
  }

  (Offset?, Offset?) selectedPoints() {
    final selected = selectables
        .where(
          (selectable) =>
              selectable.getSelectedContent()?.plainText.isNotEmpty ?? false,
        )
        .toList();
    if (selected.isEmpty) return (null, null);
    Offset? point(Selectable child, bool start) {
      final selection = start
          ? child.value.startSelectionPoint
          : child.value.endSelectionPoint;
      return selection == null
          ? null
          : MatrixUtils.transformPoint(
              child.getTransformTo(null),
              selection.localPosition - const Offset(0, 2),
            );
    }

    return (point(selected.first, true), point(selected.last, false));
  }

  @override
  SelectedContent? getSelectedContent() {
    if (plainText case final source?) return _plainSelection(source);
    final fragments = [
      for (final selectable in selectables)
        if (selectable.getSelectedContent() case final content?)
          if (content.plainText.isNotEmpty) content.plainText,
    ];
    if (fragments.isEmpty) return null;
    final text = StringBuffer(fragments.first);
    for (var i = 1; i < fragments.length; i++) {
      if (!fragments[i - 1].endsWith('\n') && !fragments[i].startsWith('\n')) {
        text.write('\n');
      }
      text.write(fragments[i]);
    }
    return SelectedContent(plainText: text.toString());
  }
}
