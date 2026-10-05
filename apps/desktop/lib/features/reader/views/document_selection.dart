import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// One selection scope for the article, excluding reader controls and notes.
class DocumentSelection extends StatefulWidget {
  const DocumentSelection({
    required this.child,
    required this.scrollController,
    required this.onQuote,
    this.onCreateNote,
    super.key,
  });
  final Widget child;
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
  Widget build(BuildContext context) => SelectionArea(
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

/// Flutter concatenates selected Text widgets without paragraph separators.
/// Use the same text for the clipboard and quotation, with block boundaries.
class _ParagraphSelectionDelegate extends StaticSelectionContainerDelegate {
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
    final fragments = [
      for (final selectable in selectables)
        if (selectable.getSelectedContent() case final content?)
          if (content.plainText.isNotEmpty) content.plainText,
    ];
    return fragments.isEmpty
        ? null
        : SelectedContent(plainText: fragments.join('\n'));
  }
}
