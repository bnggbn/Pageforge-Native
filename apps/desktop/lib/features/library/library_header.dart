import 'package:flutter/material.dart';
import '../../ui/theme.dart';

class LibraryHeader extends StatelessWidget {
  const LibraryHeader({required this.onImport, super.key});
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(Icons.description_outlined, size: 21, color: forest),
          const SizedBox(width: 12),
          const Text(
            'Pageforge.',
            style: TextStyle(
              fontFamily: editorialFace,
              fontSize: 29,
              fontWeight: FontWeight.w600,
              letterSpacing: -1.2,
              color: ink,
            ),
          ),
          const Spacer(),
          const Icon(Icons.circle, color: forest, size: 6),
          const SizedBox(width: 8),
          const Text(
            'LOCAL FIRST',
            style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.8),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const Divider(),
      const SizedBox(height: 32),
      const Text(
        'THE READING ROOM / YOUR PERSONAL LIBRARY',
        style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.8),
      ),
      const SizedBox(height: 13),
      LayoutBuilder(
        builder: (context, bounds) {
          final title = Text(
            '為文字，留一個位置。',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontSize: bounds.maxWidth < 600 ? 33 : 44,
              height: 1.5,
            ),
          );
          final button = FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add, size: 17),
            label: const Text('匯入文件'),
          );
          return bounds.maxWidth >= 650
              ? Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 24),
                    button,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 18), button],
                );
        },
      ),
      const SizedBox(height: 12),
      const Text(
        '收藏值得停留的文字，讓每個想法都有回去的路。',
        style: TextStyle(color: muted, fontSize: 12, height: 1.8),
      ),
    ],
  );
}
