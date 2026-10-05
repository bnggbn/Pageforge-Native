import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../ui/theme.dart';
import 'cover_art.dart';

class BookCover extends StatelessWidget {
  const BookCover({required this.book, super.key});
  final BookSummary book;

  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xffe7e0cf),
      forest,
      rust,
      Color(0xffdba951),
      Color(0xffb7c6ca),
    ];
    final seed = book.id.codeUnits.fold<int>(
      17,
      (value, unit) => (value * 31 + unit) & 0xffff,
    );
    final color = colors[seed % colors.length];
    final foreground = color == forest || color == rust ? paper : ink;
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: LayoutBuilder(
        builder: (context, bounds) {
          final scale = bounds.maxWidth / 200;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(2),
                right: Radius.circular(5),
              ),
              gradient: LinearGradient(
                colors: [
                  Color.lerp(color, Colors.black, .1)!,
                  color,
                  Color.lerp(color, Colors.white, .035)!,
                ],
                stops: const [0, .08, 1],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 12,
                  offset: Offset(5, 7),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CoverArt(variant: seed ~/ 5, color: foreground),
                Positioned(
                  left: 7 * scale,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 1,
                    color: foreground.withValues(alpha: .14),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    22 * scale,
                    19 * scale,
                    16 * scale,
                    18 * scale,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PAGEFORGE / ${book.label}',
                        style: TextStyle(
                          color: foreground.withValues(alpha: .7),
                          fontSize: 8 * scale,
                          letterSpacing: 1.2 * scale,
                        ),
                      ),
                      SizedBox(height: 16 * scale),
                      Text(
                        book.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: editorialFace,
                          fontFamilyFallback: editorialFallback,
                          color: foreground,
                          fontSize: 23 * scale,
                          height: 1.45,
                          letterSpacing: -.3,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'A PLACE FOR WORDS',
                        style: TextStyle(
                          color: foreground.withValues(alpha: .65),
                          fontSize: 7 * scale,
                          letterSpacing: 1.3 * scale,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
