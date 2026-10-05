import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Static linework: the cover can be cached while its parent animates.
class CoverArt extends StatelessWidget {
  const CoverArt({required this.variant, required this.color, super.key});
  final int variant;
  final Color color;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: _CoverPainter(variant, color)),
  );
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.variant, this.color);
  final int variant;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final pen = Paint()
      ..color = color.withValues(alpha: .5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    final center = Offset(w * .56, h * .66);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (variant % 5) {
      case 0:
        for (var i = 0; i < 4; i++) {
          canvas.drawOval(
            Rect.fromCenter(
              center: center + Offset(i * w * .025, -i * h * .025),
              width: w * (.58 - i * .09),
              height: h * (.34 - i * .05),
            ),
            pen,
          );
        }
      case 1:
        canvas.translate(center.dx, center.dy);
        canvas.rotate(-math.pi / 9);
        for (var i = 0; i < 3; i++) {
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(i * w * .02, i * h * .018),
              width: w * (.52 - i * .1),
              height: h * (.32 - i * .06),
            ),
            pen,
          );
        }
      case 2:
        for (var i = 0; i < 5; i++) {
          final y = h * (.55 + i * .055);
          final path = Path()
            ..moveTo(w * .22, y)
            ..cubicTo(
              w * .42,
              y - h * .17,
              w * .57,
              y + h * .1,
              w * .84,
              y - h * .06,
            );
          canvas.drawPath(path, pen);
        }
      case 3:
        final leaf = Path()
          ..moveTo(w * .27, h * .8)
          ..cubicTo(w * .2, h * .49, w * .78, h * .42, w * .8, h * .52)
          ..cubicTo(w * .83, h * .73, w * .52, h * .86, w * .27, h * .8);
        canvas.drawPath(leaf, pen);
        canvas.drawLine(
          Offset(w * .25, h * .84),
          Offset(w * .72, h * .54),
          pen,
        );
        for (var i = 0; i < 4; i++) {
          final x = w * (.37 + i * .075), y = h * (.76 - i * .045);
          canvas.drawLine(Offset(x, y), Offset(x - w * .015, y - h * .14), pen);
        }
      case 4:
        canvas.drawArc(
          Rect.fromCenter(center: center, width: w * .62, height: h * .35),
          math.pi,
          math.pi,
          false,
          pen,
        );
        for (var i = 0; i < 6; i++) {
          final y = h * (.67 + i * .022);
          canvas.drawLine(Offset(w * .23, y), Offset(w * .87, y), pen);
        }
        canvas.drawCircle(Offset(w * .68, h * .48), w * .025, pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoverPainter oldDelegate) =>
      oldDelegate.variant != variant || oldDelegate.color != color;
}
