import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Real heading semantics let note boundaries follow Markdown's parsed blocks.
/// Inline formatting stays in one selectable Text, including emphasized titles.
class MarkdownHeadingBuilder extends MarkdownElementBuilder {
  MarkdownHeadingBuilder(this.styles);
  final MarkdownStyleSheet styles;

  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => Semantics(
    header: true,
    child: Text.rich(
      TextSpan(children: element.children?.map(_span).toList()),
      style: preferredStyle,
    ),
  );

  InlineSpan _span(md.Node node) {
    if (node is md.Text) {
      return TextSpan(text: node.text.replaceAll(RegExp(r' ?\n *'), ' '));
    }
    final element = node as md.Element;
    if (element.tag == 'br') return const TextSpan(text: '\n');
    if (element.tag == 'img') {
      final label =
          element.attributes['alt'] ?? element.attributes['title'] ?? '未提供說明';
      return TextSpan(text: '[圖片：$label]');
    }
    return TextSpan(
      style: styles.styles[element.tag],
      children: element.children?.map(_span).toList(),
    );
  }
}
