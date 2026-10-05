import 'package:flutter/material.dart';
import '../../../data/models.dart';
import '../../../ui/design_theme.dart';
import '../reader_view_model.dart';
import 'note_composer.dart';
import 'paragraph_location.dart';

Future<void> openParagraphNotes(
  BuildContext context,
  ReaderViewModel model,
  NotePassage? passage,
  List<Json> notes,
) async {
  final ids = notes.map((note) => note['id']).toSet();
  var create = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => ListenableBuilder(
      listenable: model,
      builder: (context, _) => AlertDialog(
        title: Text(passage == null ? '筆記與線索' : '這一段的筆記'),
        content: SizedBox(
          width: 580,
          height: 420,
          child: ListView(
            children: [
              if (passage != null) ...[
                SelectableText(
                  passage.quote,
                  style: TextStyle(
                    color: context.design.muted,
                    fontSize: 12,
                    height: 1.7,
                  ),
                ),
                const Divider(height: 32),
              ],
              for (final note in model.book!.head.notes.where(
                (note) => ids.contains(note['id']),
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((note['quote'] as String).isNotEmpty)
                        SelectableText(
                          '「${note['quote']}」',
                          style: TextStyle(
                            color: context.design.forest,
                            fontSize: 12,
                            height: 1.7,
                          ),
                        ),
                      const SizedBox(height: 8),
                      SelectableText(
                        note['body'] as String,
                        style: const TextStyle(height: 1.8),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              model.showEvidence(note['id'] as String);
                            },
                            child: const Text('在線索牆查看'),
                          ),
                          TextButton(
                            onPressed: model.busy
                                ? null
                                : () => model.removeNote(note['id'] as String),
                            child: const Text('移除筆記'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (model.error.isNotEmpty)
                Text(model.error, style: TextStyle(color: context.design.rust)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('關閉'),
          ),
          if (passage != null)
            FilledButton(
              onPressed: model.busy
                  ? null
                  : () {
                      create = true;
                      Navigator.pop(dialogContext);
                    },
              child: const Text('新增這段筆記'),
            ),
        ],
      ),
    ),
  );
  if (create && context.mounted) {
    await openNoteComposer(context, model, passage);
  }
}
