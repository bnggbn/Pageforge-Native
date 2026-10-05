import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../ui/motion.dart';
import '../../ui/design_theme.dart';
import 'book_cover.dart';

class BookTile extends StatefulWidget {
  const BookTile({required this.book, required this.onOpen, super.key});
  final BookSummary book;
  final VoidCallback onOpen;

  @override
  State<BookTile> createState() => _BookTileState();
}

class _BookTileState extends State<BookTile> {
  bool hovered = false, focused = false, pressed = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final active = hovered || focused;
    final duration = PageforgeMotion.reduced(context)
        ? Duration.zero
        : PageforgeMotion.quick;
    return Semantics(
      label: '${book.title}，${book.label}，${book.versions} 個版本',
      child: InkWell(
        onTap: widget.onOpen,
        onHover: (value) => setState(() => hovered = value),
        onFocusChange: (value) => setState(() => focused = value),
        onHighlightChanged: (value) => setState(() => pressed = value),
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: duration,
          curve: PageforgeMotion.curve,
          transform: Matrix4.translationValues(
            0,
            active && !pressed ? -6 : 0,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: duration,
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 22),
                  decoration: BoxDecoration(
                    color: active
                        ? Color.lerp(
                            context.design.paper,
                            context.design.ink,
                            .07,
                          )!
                        : Color.lerp(
                            context.design.paper,
                            context.design.ink,
                            .035,
                          )!,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: focused
                          ? context.design.rust.withValues(alpha: .55)
                          : Colors.transparent,
                    ),
                  ),
                  child: Center(child: BookCover(book: book)),
                ),
              ),
              SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    duration: duration,
                    opacity: active ? 1 : 0,
                    child: Icon(
                      Icons.north_east,
                      size: 14,
                      color: context.design.rust,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text(
                '${book.label} · ${book.versions} 個版本 · ${book.progress.round()}% 已讀',
                style: TextStyle(color: context.design.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
