import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../ui/theme.dart';

class BookTile extends StatelessWidget {
  const BookTile({required this.book, required this.onOpen, super.key});
  final BookSummary book;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
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
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x15000000),
                    blurRadius: 9,
                    offset: Offset(2, 4),
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
                  Text(
                    'PAGEFORGE',
                    style: TextStyle(
                      color: foreground.withValues(alpha: .75),
                      fontSize: 9,
                      letterSpacing: 2,
                    ),
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
    );
  }
}
