import 'package:flutter/material.dart';
import 'studio_view_model.dart';

class StudioSceneList extends StatelessWidget {
  const StudioSceneList({
    required this.model,
    required this.compact,
    super.key,
  });
  final StudioViewModel model;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final items = [
      for (final entry in {
        DesignScene.theme: '全域主題',
        DesignScene.library: '書架',
        DesignScene.reader: '文字閱讀器',
      }.entries)
        Padding(
          padding: const EdgeInsets.all(4),
          child: ChoiceChip(
            label: Text(entry.value),
            selected: model.scene == entry.key,
            onSelected: model.busy ? null : (_) => model.select(entry.key),
          ),
        ),
    ];
    return compact
        ? Wrap(children: items)
        : ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text('場景', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              ...items,
            ],
          );
  }
}
