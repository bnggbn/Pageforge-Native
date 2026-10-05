import 'package:flutter/material.dart';
import '../../ui/design_theme.dart';

class LibraryHeader extends StatelessWidget {
  const LibraryHeader({required this.onImport, this.onDesign, super.key});
  final VoidCallback? onImport;
  final VoidCallback? onDesign;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: 21,
            color: context.design.forest,
          ),
          SizedBox(width: 12),
          Text(
            'Pageforge.',
            style: TextStyle(
              fontFamily: context.design.headingFont,
              fontSize: 29,
              fontWeight: FontWeight.w600,
              letterSpacing: -1.2,
              color: context.design.ink,
            ),
          ),
          Spacer(),
          if (onDesign != null)
            IconButton(
              onPressed: onDesign,
              tooltip: '外觀工作室',
              icon: Icon(Icons.tune),
            ),
          Icon(Icons.circle, color: context.design.forest, size: 6),
          SizedBox(width: 8),
          Text(
            'LOCAL FIRST',
            style: TextStyle(
              color: context.design.muted,
              fontSize: 9,
              letterSpacing: 1.8,
            ),
          ),
        ],
      ),
      SizedBox(height: 24),
      Divider(),
      SizedBox(height: 32),
      Text(
        'THE READING ROOM / YOUR PERSONAL LIBRARY',
        style: TextStyle(
          color: context.design.muted,
          fontSize: 9,
          letterSpacing: 1.8,
        ),
      ),
      SizedBox(height: 13),
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
            icon: Icon(Icons.add, size: 17),
            label: Text('匯入文件'),
          );
          return bounds.maxWidth >= 650
              ? Row(
                  children: [
                    Expanded(child: title),
                    SizedBox(width: 24),
                    button,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, SizedBox(height: 18), button],
                );
        },
      ),
      SizedBox(height: 12),
      Text(
        '收藏值得停留的文字，讓每個想法都有回去的路。',
        style: TextStyle(
          color: context.design.muted,
          fontSize: 12,
          height: 1.8,
        ),
      ),
    ],
  );
}
