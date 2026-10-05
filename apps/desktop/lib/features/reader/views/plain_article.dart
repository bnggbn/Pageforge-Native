import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Preserve actual separators for selection; padding adds only visual space.
class PlainArticle extends StatelessWidget {
  const PlainArticle({
    required this.content,
    required this.style,
    required this.gap,
    super.key,
  });
  final String content;
  final TextStyle style;
  final double gap;
  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    var start = 0;
    for (final separator in RegExp(
      r'\r?\n[ \t]*\r?\n(?:[ \t]*\r?\n)*',
    ).allMatches(content)) {
      parts.add(content.substring(start, separator.end));
      start = separator.end;
    }
    if (start < content.length || parts.isEmpty) {
      parts.add(content.substring(start));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < parts.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
            child: i == parts.length - 1
                ? Text(parts[i], style: style)
                : _TrimTrailingLine(
                    lineHeight:
                        MediaQuery.textScalerOf(
                          context,
                        ).scale(style.fontSize!) *
                        style.height!,
                    child: Text(parts[i], style: style),
                  ),
          ),
      ],
    );
  }
}

/// Each preserved separator ends with one unpainted line in Text's layout.
/// Remove that line's box; the next paragraph supplies the real following line.
class _TrimTrailingLine extends SingleChildRenderObjectWidget {
  const _TrimTrailingLine({required this.lineHeight, required super.child});
  final double lineHeight;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _TrimLineRender(lineHeight);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _TrimLineRender object,
  ) {
    object.lineHeight = lineHeight;
  }
}

class _TrimLineRender extends RenderProxyBox {
  _TrimLineRender(this._lineHeight);
  double _lineHeight;
  set lineHeight(double value) {
    if (value != _lineHeight) {
      _lineHeight = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    final text = child!;
    text.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(
      Size(
        text.size.width,
        (text.size.height - _lineHeight).clamp(0.0, double.infinity),
      ),
    );
  }
}
