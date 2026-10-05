import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// One selection scope for the article, excluding reader controls and notes.
class DocumentSelection extends StatefulWidget {
  const DocumentSelection({
    required this.child,
    required this.scrollController,
    required this.onQuote,
    super.key,
  });
  final Widget child;
  final ScrollController scrollController;
  final ValueChanged<String> onQuote;

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
