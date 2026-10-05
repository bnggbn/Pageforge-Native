import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../data/models.dart';
import '../../ui/design_theme.dart';
import '../reader/annotations/paragraph_location.dart';

class EvidenceCard extends StatelessWidget {
  const EvidenceCard({
    required this.note,
    required this.number,
    required this.selected,
    required this.onTap,
    required this.onReveal,
    required this.onDrag,
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
  final ValueChanged<Offset> onDrag, onPinUpdate;
  @override
  Widget build(BuildContext context) => Material(
    color: Color.lerp(context.design.paper, Colors.white, .55),
    elevation: selected ? 6 : 2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(
        color: selected
            ? context.design.rust
            : context.design.muted.withValues(alpha: .3),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          key: ValueKey('pin-${note['id']}'),
          onTap: onPinTap,
          onPanStart: (_) => onPinStart(),
          onPanUpdate: (details) => onPinUpdate(details.globalPosition),
          onPanEnd: (_) => onPinEnd(),
          onPanCancel: onPinEnd,
          child: Tooltip(
            message: '拖曳圖釘到另一張卡片，或依序點兩個圖釘連紅線',
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Icon(
                  Icons.push_pin,
                  size: 18,
                  color: const Color(0xffa83b35),
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          dragStartBehavior: DragStartBehavior.down,
          key: ValueKey('move-${note['id']}'),
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => onDrag(details.delta),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '線索 $number',
                    style: TextStyle(color: context.design.muted, fontSize: 11),
                  ),
                ),
                Icon(
                  Icons.drag_indicator,
                  size: 16,
                  color: context.design.muted,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  ParagraphLocation.parse(note['location'] as String) == null
                      ? '筆記'
                      : '段落筆記',
                  style: TextStyle(fontSize: 10, color: context.design.muted),
                ),
              ),
              TextButton(
                onPressed: onReveal,
                child: const Text('回到原文', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
