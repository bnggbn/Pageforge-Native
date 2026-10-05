import 'package:flutter/material.dart';
import '../../ui/theme.dart';

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
          border: Border.all(color: const Color(0xffdcded2)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.folder_outlined, size: 17, color: forest),
              const Text(
                'library / collection',
                style: TextStyle(color: muted, fontSize: 11),
              ),
              TextButton(onPressed: onSync, child: const Text('重新載入資料夾 ↗')),
            ],
          ),
        ),
      ),
      const SizedBox(height: 30),
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
            decoration: const InputDecoration(
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
                  children: [title, const SizedBox(height: 16), search],
                )
              : Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 20),
                    SizedBox(width: 220, child: search),
                  ],
                );
        },
      ),
    ],
  );
}
