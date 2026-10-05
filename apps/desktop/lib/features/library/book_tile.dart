import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';

class BookTile extends StatefulWidget {
  const BookTile({required this.book, required this.onOpen, super.key});
  final BookSummary book;
  final VoidCallback onOpen;

  @override
  State<BookTile> createState() => _BookTileState();
}

class _BookTileState extends State<BookTile> {
  bool hovered = false;
  bool focused = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    const covers = [
      Color(0xffe9e4d8),
      forest,
      rust,
      Color(0xffdfad54),
      Color(0xffbcc9d1),
    ];
    final index = int.tryParse(book.id.substring(0, 2), radix: 16) ?? 0;
    final color = covers[index % covers.length];
    final foreground = color == forest || color == rust ? paper : ink;
    final active = hovered || focused;
    final duration = PageforgeMotion.reduced(context)
        ? Duration.zero
        : PageforgeMotion.quick;
    return InkWell(
      onTap: widget.onOpen,
      onHover: (value) => setState(() => hovered = value),
      onFocusChange: (value) => setState(() => focused = value),
      onHighlightChanged: (value) => setState(() => pressed = value),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: duration,
        curve: PageforgeMotion.curve,
        transform: Matrix4.translationValues(0, active && !pressed ? -6 : 0, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: duration,
                curve: PageforgeMotion.curve,
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                  border: Border(
                    left: BorderSide(
                      color: foreground.withValues(alpha: .12),
                      width: 5,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(active ? 0x26000000 : 0x15000000),
                      blurRadius: active ? 18 : 9,
                      offset: Offset(2, active ? 10 : 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${book.label} / PERSONAL COLLECTION',
                      style: TextStyle(
                        color: foreground.withValues(alpha: .65),
                        fontSize: 9,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      book.title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 22,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Divider(color: foreground.withValues(alpha: .3)),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'PAGEFORGE',
                            style: TextStyle(
                              color: foreground.withValues(alpha: .75),
                              fontSize: 9,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        AnimatedOpacity(
                          duration: duration,
                          opacity: active ? 1 : 0,
                          child: Icon(
                            Icons.north_east,
                            size: 16,
                            color: foreground,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 13),
            Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '${book.versions} 個版本 · ${book.progress.round()}% 已讀',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
