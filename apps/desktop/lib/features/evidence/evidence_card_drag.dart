import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../../data/models.dart';

typedef CardDrag = ({String id, Offset origin, Offset grab, Offset position});

/// Transient scene geometry; the persistent model changes once on release.
class EvidenceCardDrag extends ValueNotifier<CardDrag?> {
  EvidenceCardDrag() : super(null);

  void begin(Json card, Offset pointer) {
    final origin = Offset(
      (card['x'] as num).toDouble(),
      (card['y'] as num).toDouble(),
    );
    value = (
      id: card['noteId'] as String,
      origin: origin,
      grab: pointer - origin,
      position: origin,
    );
  }

  void update(Offset pointer, double width, double height) {
    final current = value;
    if (current == null) return;
    final target = pointer - current.grab;
    final position = Offset(
      target.dx.clamp(0.0, width - 280),
      target.dy.clamp(0.0, height - 240),
    );
    if (position == current.position) return;
    value = (
      id: current.id,
      origin: current.origin,
      grab: current.grab,
      position: position,
    );
  }

  Offset positionOf(Json card) {
    final current = value;
    return current?.id == card['noteId']
        ? current!.position
        : Offset((card['x'] as num).toDouble(), (card['y'] as num).toDouble());
  }

  CardDrag? finish() {
    final current = value;
    value = null;
    return current;
  }

  void cancel() => value = null;
}
