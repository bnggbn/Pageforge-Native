import 'package:flutter/material.dart';
import 'studio_view_model.dart';

class StudioToolbar extends StatelessWidget {
  const StudioToolbar({required this.model, required this.onBack, super.key});
  final StudioViewModel model;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          onPressed: model.busy ? null : onBack,
          tooltip: '返回書架',
          icon: const Icon(Icons.arrow_back),
        ),
        const Text('外觀工作室', style: TextStyle(fontSize: 22)),
        IconButton(
          onPressed: model.canUndo && !model.busy ? model.undo : null,
          tooltip: '復原外觀',
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          onPressed: model.canRedo && !model.busy ? model.redo : null,
          tooltip: '重做外觀',
          icon: const Icon(Icons.redo),
        ),
        TextButton(
          onPressed: model.busy ? null : model.reset,
          child: const Text('預設外觀'),
        ),
        TextButton(
          onPressed: model.busy ? null : model.reload,
          child: const Text('重新載入'),
        ),
        FilledButton(
          onPressed: model.busy || model.error.isNotEmpty ? null : model.apply,
          child: Text(model.busy ? '保存中…' : '套用並保存'),
        ),
      ],
    ),
  );
}
