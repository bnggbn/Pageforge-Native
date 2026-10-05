import 'package:flutter/material.dart';

class StudioPresets extends StatelessWidget {
  const StudioPresets({required this.onSelect, super.key});
  final ValueChanged<Map<String, String>> onSelect;
  static const presets = {
    '書店': {
      'paper': '#f5f2e9',
      'ink': '#343a32',
      'accent': '#a84b36',
      'forest': '#344a42',
      'muted': '#858879',
    },
    '晨光': {
      'paper': '#fff7ea',
      'ink': '#443b30',
      'accent': '#a66438',
      'forest': '#575943',
      'muted': '#82786a',
    },
    '墨藍': {
      'paper': '#edf2f5',
      'ink': '#273b4b',
      'accent': '#356888',
      'forest': '#354f63',
      'muted': '#74838d',
    },
  };
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final preset in presets.entries)
        OutlinedButton.icon(
          onPressed: () => onSelect(preset.value),
          icon: Icon(
            Icons.circle,
            size: 12,
            color: Color(
              int.parse('ff${preset.value['accent']!.substring(1)}', radix: 16),
            ),
          ),
          label: Text(preset.key),
        ),
    ],
  );
}
