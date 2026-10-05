import 'package:flutter/material.dart';
import '../../ui/design_theme.dart';

class ShelfToolbar extends StatelessWidget {
  const ShelfToolbar({
    required this.count,
    required this.onSearch,
    required this.onSync,
    super.key,
  });
  final int count;
  final ValueChanged<String> onSearch;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Color(0xffdcded2)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                Icons.folder_outlined,
                size: 17,
                color: context.design.forest,
              ),
              Text(
                'library / collection',
                style: TextStyle(color: context.design.muted, fontSize: 11),
              ),
              TextButton(onPressed: onSync, child: Text('重新載入資料夾 ↗')),
            ],
          ),
        ),
      ),
      SizedBox(height: 30),
      LayoutBuilder(
        builder: (context, bounds) {
          final title = Text(
            '我的書架 · $count',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontSize: 22),
          );
          final search = TextField(
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: '尋找一份文件',
              prefixIcon: Icon(Icons.search, size: 17),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          );
          return bounds.maxWidth < 440
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, SizedBox(height: 16), search],
                )
              : Row(
                  children: [
                    Expanded(child: title),
                    SizedBox(width: 20),
                    SizedBox(width: 220, child: search),
                  ],
                );
        },
      ),
    ],
  );
}
