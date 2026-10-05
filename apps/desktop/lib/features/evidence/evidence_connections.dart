import 'package:flutter/material.dart';
import '../../data/models.dart';
import 'evidence_geometry.dart';

class EvidenceConnections extends CustomPainter {
  const EvidenceConnections({
    required this.cards,
    required this.edges,
    required this.color,
    this.source,
    this.pointer,
  });
  final List<Json> cards, edges;
  final Color color;
  final String? source;
  final Offset? pointer;
  @override
  void paint(Canvas canvas, Size size) {
    final pins = {for (final card in cards) card['noteId']: evidencePin(card)};
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final edge in edges) {
      final a = pins[edge['from']], b = pins[edge['to']];
      if (a == null || b == null) continue;
      canvas.drawPath(evidencePath(a, b), paint);
      final label = edge['label'] as String;
      if (label.isNotEmpty) {
        final text = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              backgroundColor: const Color(0xfff5f2e9),
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 160);
        final center = curvePoint(a, b, .5);
        text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
      }
    }
    final pin = pins[source];
    if (pin != null && pointer != null) {
      canvas.drawPath(
        evidencePath(pin, pointer!),
        paint..color = color.withValues(alpha: .6),
      );
    }
  }

  @override
  bool shouldRepaint(EvidenceConnections old) =>
      !identical(cards, old.cards) ||
      !identical(edges, old.edges) ||
      source != old.source ||
      pointer != old.pointer ||
      color != old.color;
}

class EvidenceGrid extends CustomPainter {
  const EvidenceGrid(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: .1);
    for (var x = 0.0; x < size.width; x += 32) {
      for (var y = 0.0; y < size.height; y += 32) {
        canvas.drawCircle(Offset(x, y), .7, paint);
      }
    }
  }

  @override
  bool shouldRepaint(EvidenceGrid old) => color != old.color;
}
