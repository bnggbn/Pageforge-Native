import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../../ui/design_theme.dart';
import 'plain_article.dart';

/// Shared by the live reader and the appearance preview.
class ArticleBody extends StatelessWidget {
  const ArticleBody({
    required this.content,
    required this.markdown,
    required this.fontSize,
    super.key,
  });
  final String content;
  final bool markdown;
  final double fontSize;
  @override
  Widget build(BuildContext context) {
    final body = TextStyle(
      fontSize: fontSize,
      height: context.design.lineHeight,
      color: context.design.ink,
    );
    final lineSize =
        MediaQuery.textScalerOf(context).scale(fontSize) *
        context.design.lineHeight;
    final gap = lineSize * context.design.paragraphGapLines;
    return markdown
        ? MarkdownBody(
            data: content,
            selectable: false,
            fitContent: false,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
                  p: body,
                  blockSpacing: 8 + gap,
                  h1: body.copyWith(
                    fontSize: fontSize * 1.8,
                    height: 1.7,
                    fontFamily: context.design.headingFont,
                  ),
                  h2: body.copyWith(
                    fontSize: fontSize * 1.4,
                    height: 1.7,
                    fontFamily: context.design.headingFont,
                  ),
                ),
            imageBuilder: (uri, title, alt) =>
                Text('[圖片：${alt ?? title ?? '未提供說明'}]'),
          )
        : PlainArticle(content: content, style: body, gap: gap);
  }
}
