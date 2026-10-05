import 'package:flutter/material.dart';
import '../../data/models.dart';

const evidenceCardSize = Size(280, 240);
Rect evidenceCardRect(Json card) => Rect.fromLTWH(
  (card['x'] as num).toDouble(),
  (card['y'] as num).toDouble(),
  280,
  240,
);
Offset evidencePin(Json card) =>
    evidenceCardRect(card).topCenter + const Offset(0, 15);
Offset curvePoint(Offset a, Offset b, double t) {
  final middle = (a + b) / 2 + const Offset(0, 24);
  return a * (1 - t) * (1 - t) + middle * 2 * t * (1 - t) + b * t * t;
}

Path evidencePath(Offset a, Offset b) {
  final middle = (a + b) / 2 + const Offset(0, 24);
  return Path()
    ..moveTo(a.dx, a.dy)
    ..quadraticBezierTo(middle.dx, middle.dy, b.dx, b.dy);
}

bool nearEvidenceLine(Offset point, Offset a, Offset b) {
  for (var i = 0; i < 24; i++) {
    final start = curvePoint(a, b, i / 24),
        end = curvePoint(a, b, (i + 1) / 24),
        delta = end - start;
    final length = delta.distanceSquared;
    final t = length == 0
        ? 0.0
        : ((point - start).dx * delta.dx + (point - start).dy * delta.dy) /
              length;
    if ((point - (start + delta * t.clamp(0.0, 1.0))).distance < 10) {
      return true;
    }
  }
  return false;
}
