import 'package:flutter/material.dart';
import 'evidence_wall_view_model.dart';
import 'evidence_note_picker.dart';

Future<String?> topicNameDialog(
  BuildContext context,
  EvidenceWallViewModel model, {
  bool rename = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TopicNameDialog(model: model, rename: rename),
);

class _TopicNameDialog extends StatefulWidget {
  const _TopicNameDialog({required this.model, required this.rename});
  final EvidenceWallViewModel model;
  final bool rename;
  @override
  State<_TopicNameDialog> createState() => _TopicNameDialogState();
}

class _TopicNameDialogState extends State<_TopicNameDialog> {
  late final text = TextEditingController(
    text: widget.rename ? widget.model.activeTopicName : '',
  );
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.rename ? '重新命名主題' : '新增線索主題'),
    content: TextField(
      key: const ValueKey('evidence-topic-name'),
      controller: text,
      autofocus: true,
      maxLength: widget.model.nameLimit,
      decoration: const InputDecoration(hintText: '例如：人物關係、待查證、矛盾與疑問'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, text.text.trim()),
        child: const Text('保存主題'),
      ),
    ],
  );
}

class EvidenceTopicBar extends StatelessWidget {
  const EvidenceTopicBar({
    required this.model,
    required this.disabled,
    super.key,
  });
  final EvidenceWallViewModel model;
  final bool disabled;
  Future<void> create(BuildContext context) async {
    final name = await topicNameDialog(context, model);
    if (name == null || !context.mounted || !model.createTopic(name)) return;
    await pickEvidenceNotes(context, model);
  }

  Future<void> manage(BuildContext context, String action) async {
    if (action == 'rename') {
      final name = await topicNameDialog(context, model, rename: true);
      if (name != null && context.mounted) model.renameTopic(name);
    } else {
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('刪除這個主題？'),
          content: const Text('本主題的布局與紅線會移除，原始筆記及其他主題保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('刪除主題'),
            ),
          ],
        ),
      );
      if (remove == true && context.mounted) model.deleteTopic();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 250,
          child: DropdownButtonFormField<String>(
            key: ValueKey('topic-${model.activeTopicId}'),
            initialValue: model.activeTopicId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '線索主題', isDense: true),
            items: [
              for (final topic in model.topics)
                DropdownMenuItem(
                  value: topic['id'] as String,
                  child: Text(
                    topic['name'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: disabled
                ? null
                : (id) {
                    if (id != null) model.selectTopic(id);
                  },
          ),
        ),
        OutlinedButton.icon(
          onPressed: disabled ? null : () => create(context),
          icon: const Icon(Icons.add, size: 17),
          label: const Text('新增主題'),
        ),
        if (!model.isAllTopic)
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => pickEvidenceNotes(context, model),
            icon: const Icon(Icons.checklist, size: 17),
            label: const Text('挑選線索'),
          ),
        if (!model.isAllTopic)
          PopupMenuButton<String>(
            enabled: !disabled,
            tooltip: '主題管理',
            onSelected: (action) => manage(context, action),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('重新命名')),
              const PopupMenuItem(value: 'delete', child: Text('刪除主題')),
            ],
            icon: const Icon(Icons.more_horiz),
          ),
      ],
    ),
  );
}
