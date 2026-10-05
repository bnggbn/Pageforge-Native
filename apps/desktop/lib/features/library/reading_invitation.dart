import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../ui/theme.dart';
import 'book_cover.dart';
import 'cover_art.dart';

class ReadingInvitation extends StatelessWidget {
  const ReadingInvitation({
    required this.book,
    required this.onOpen,
    super.key,
  });
  final BookSummary? book;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xffe7ebdf),
    borderRadius: BorderRadius.circular(7),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: book == null ? null : onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 26),
        child: LayoutBuilder(
          builder: (context, bounds) => Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'A LITTLE SPACE TO READ',
                      style: TextStyle(
                        color: forest,
                        fontSize: 9,
                        letterSpacing: 1.7,
                      ),
                    ),
                    const SizedBox(height: 17),
                    Text(
                      book == null ? '第一頁，從這裡開始。' : '慢一點，\n把一頁讀進心裡。',
                      style: const TextStyle(
                        fontFamily: editorialFace,
                        fontFamilyFallback: editorialFallback,
                        fontSize: 30,
                        height: 1.6,
                        color: forest,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      book?.title ?? '把文件放上書架，留下一個想法。',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: forest, fontSize: 12),
                    ),
                    if (book != null) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 180,
                        child: LinearProgressIndicator(
                          value: (book!.progress / 100).clamp(0, 1),
                          minHeight: 2,
                          color: forest.withValues(alpha: .55),
                          backgroundColor: forest.withValues(alpha: .12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        book!.progress > 0 ? '接續上次的閱讀  →' : '從一頁開始  →',
                        style: const TextStyle(
                          color: forest,
                          fontSize: 11,
                          letterSpacing: .5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (bounds.maxWidth > 540) ...[
                const SizedBox(width: 32),
                if (book != null)
                  Transform.rotate(
                    angle: math.pi / 20,
                    child: SizedBox(
                      width: 140,
                      height: 210,
                      child: BookCover(book: book!),
                    ),
                  )
                else
                  const SizedBox(
                    width: 160,
                    height: 210,
                    child: CoverArt(variant: 3, color: forest),
                  ),
                const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
