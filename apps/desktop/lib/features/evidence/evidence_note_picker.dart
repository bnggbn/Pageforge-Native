import 'package:flutter/material.dart';
import 'evidence_wall_view_model.dart';

Future<void> pickEvidenceNotes(
  BuildContext context,
  EvidenceWallViewModel model,
) => showDialog<void>(
  context: context,
  builder: (_) => EvidenceNotePicker(model: model),
);

class EvidenceNotePicker extends StatefulWidget {
  const EvidenceNotePicker({required this.model, super.key});
  final EvidenceWallViewModel model;
  @override
  State<EvidenceNotePicker> createState() => _EvidenceNotePickerState();
}

class _EvidenceNotePickerState extends State<EvidenceNotePicker> {
  late final selected = widget.model.cards
      .map((c) => c['noteId'] as String)
      .toSet();
  String query = '', error = '';
  @override
  Widget build(BuildContext context) {
    final notes = widget.model.notes.values
        .where(
          (n) => ('${n['body']} ${n['quote']}').toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return AlertDialog(
      title: Text('挑選線索 · ${widget.model.activeTopicName}'),
      content: SizedBox(
        width: 580,
        height: 440,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('evidence-note-search'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜尋筆記或引用',
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 12),
            const Text(
              '同一則筆記可加入多個主題。取消勾選會移除本主題的卡片與相關紅線，原筆記保留。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final note in notes)
                    CheckboxListTile(
                      key: ValueKey('choose-${note['id'] as String}'),
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(note['id']),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          selected.add(note['id'] as String);
                        } else {
                          selected.remove(note['id']);
                        }
                      }),
                      title: Text(
                        note['body'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        note['quote'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (error.isNotEmpty) Text(error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (widget.model.setTopicNotes(selected)) {
              Navigator.pop(context);
            } else {
              setState(() => error = widget.model.error);
            }
          },
          child: Text('保存選擇（${selected.length}）'),
        ),
      ],
    );
  }
}
