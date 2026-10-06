import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../ui/design_theme.dart';
import '../../ui/motion.dart';
import '../reader/annotations/paragraph_location.dart';
import 'evidence_drag_surface.dart';

class EvidenceCard extends StatefulWidget {
  const EvidenceCard({
    required this.note,
    required this.number,
    required this.selected,
    required this.onTap,
    required this.onReveal,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onPinTap,
    required this.onPinStart,
    required this.onPinUpdate,
    required this.onPinEnd,
    super.key,
  });
  final Json note;
  final int number;
  final bool selected;
  final VoidCallback onTap, onReveal, onPinTap, onPinStart, onPinEnd;
  final ValueChanged<Offset> onDragStart, onDragUpdate, onPinUpdate;
  final VoidCallback onDragEnd, onDragCancel;

  @override
  State<EvidenceCard> createState() => _EvidenceCardState();
}

class _EvidenceCardState extends State<EvidenceCard> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = PageforgeMotion.reduced(context);
    final duration = reduced ? Duration.zero : PageforgeMotion.quick;
    final note = widget.note;
    return SizedBox.expand(
      child: AnimatedScale(
        scale: pressed && !reduced ? 1.012 : 1,
        duration: duration,
        curve: PageforgeMotion.curve,
        child: Material(
          color: Color.lerp(context.design.paper, Colors.white, .55),
          elevation: pressed ? 16 : (widget.selected ? 6 : 2),
          animationDuration: duration,
          shadowColor: context.design.ink.withValues(alpha: .5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(
              color: pressed || widget.selected
                  ? context.design.rust
                  : context.design.muted.withValues(alpha: .3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                key: ValueKey('pin-${note['id']}'),
                onTap: widget.onPinTap,
                onPanStart: (_) => widget.onPinStart(),
                onPanUpdate: (details) =>
                    widget.onPinUpdate(details.globalPosition),
                onPanEnd: (_) => widget.onPinEnd(),
                onPanCancel: widget.onPinEnd,
                child: Tooltip(
                  message: '拖曳圖釘到另一張卡片，或依序點兩個圖釘連紅線',
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 7),
                      child: Icon(
                        Icons.push_pin,
                        size: 18,
                        color: Color(0xffa83b35),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: EvidenceDragSurface(
                  key: ValueKey('move-${note['id']}'),
                  onTap: widget.onTap,
                  onPressed: (value) => setState(() => pressed = value),
                  onStart: widget.onDragStart,
                  onUpdate: widget.onDragUpdate,
                  onEnd: widget.onDragEnd,
                  onCancel: widget.onDragCancel,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '線索 ${widget.number}',
                                  style: TextStyle(
                                    color: context.design.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              Icon(
                                pressed
                                    ? Icons.open_with
                                    : Icons.drag_indicator,
                                size: 16,
                                color: pressed
                                    ? context.design.rust
                                    : context.design.muted,
                              ),
                            ],
                          ),
                        ),
                        if ((note['quote'] as String).isNotEmpty) ...[
                          Text(
                            '「${note['quote']}」',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.design.forest,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Expanded(
                          child: Text(
                            note['body'] as String,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: context.design.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ParagraphLocation.parse(note['location'] as String) ==
                                null
                            ? '筆記'
                            : '段落筆記',
                        style: TextStyle(
                          fontSize: 10,
                          color: context.design.muted,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onReveal,
                      child: const Text('回到原文', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
