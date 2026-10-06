import 'package:flutter/material.dart';
import '../../data/models.dart';
import 'evidence_card_drag.dart';

/// Subscribe to drag geometry, but rebuild only the card whose position changed.
class EvidencePositionedCard extends StatefulWidget {
  const EvidencePositionedCard({
    required this.card,
    required this.drag,
    required this.child,
    super.key,
  });
  final Json card;
  final EvidenceCardDrag drag;
  final Widget child;
  @override
  State<EvidencePositionedCard> createState() => _EvidencePositionedCardState();
}

class _EvidencePositionedCardState extends State<EvidencePositionedCard> {
  late Offset position;
  @override
  void initState() {
    super.initState();
    position = widget.drag.positionOf(widget.card);
    widget.drag.addListener(update);
  }

  void update() {
    final next = widget.drag.positionOf(widget.card);
    if (next != position) setState(() => position = next);
  }

  @override
  void didUpdateWidget(EvidencePositionedCard old) {
    super.didUpdateWidget(old);
    if (old.drag != widget.drag) {
      old.drag.removeListener(update);
      widget.drag.addListener(update);
    }
    position = widget.drag.positionOf(widget.card);
  }

  @override
  void dispose() {
    widget.drag.removeListener(update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned(
    left: position.dx,
    top: position.dy,
    width: 280,
    height: 240,
    child: widget.child,
  );
}
