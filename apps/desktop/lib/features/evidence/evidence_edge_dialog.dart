import 'package:flutter/material.dart';
import '../../data/models.dart';
import 'evidence_wall_view_model.dart';

Future<void> editEvidenceEdge(
  BuildContext context,
  EvidenceWallViewModel model,
  Json edge,
) async {
  final controller = TextEditingController(text: edge['label'] as String);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('這條紅線代表什麼？'),
      content: TextField(
        controller: controller,
        maxLength: 200,
        decoration: const InputDecoration(hintText: '例如：相互印證、存在矛盾、待查證'),
      ),
      actions: [
        TextButton(
          onPressed: () {
            model.removeEdge(edge['id'] as String);
            Navigator.pop(context);
          },
          child: const Text('移除紅線'),
        ),
        FilledButton(
          onPressed: () {
            model.editEdge(edge['id'] as String, controller.text.trim());
            Navigator.pop(context);
          },
          child: const Text('保存關係'),
        ),
      ],
    ),
  );
  controller.dispose();
}
