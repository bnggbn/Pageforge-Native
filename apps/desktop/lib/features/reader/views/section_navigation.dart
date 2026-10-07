import 'package:flutter/material.dart';

class SectionNavigation extends StatelessWidget {
  const SectionNavigation({
    required this.index,
    required this.count,
    required this.onChanged,
    super.key,
  });
  final int index, count;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: '第一節',
        onPressed: index == 0 || onChanged == null ? null : () => onChanged!(0),
        icon: const Icon(Icons.first_page),
      ),
      IconButton(
        tooltip: '上一節',
        onPressed: index == 0 || onChanged == null
            ? null
            : () => onChanged!(index - 1),
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: Center(
          child: DropdownButton<int>(
            value: index,
            isExpanded: true,
            items: [
              for (var i = 0; i < count; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(
                    '第 ${i + 1} / $count 節',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onChanged == null
                ? null
                : (value) {
                    if (value != null) onChanged!(value);
                  },
          ),
        ),
      ),
      IconButton(
        tooltip: '下一節',
        onPressed: index + 1 == count || onChanged == null
            ? null
            : () => onChanged!(index + 1),
        icon: const Icon(Icons.chevron_right),
      ),
      IconButton(
        tooltip: '最後一節',
        onPressed: index + 1 == count || onChanged == null
            ? null
            : () => onChanged!(count - 1),
        icon: const Icon(Icons.last_page),
      ),
    ],
  );
}
