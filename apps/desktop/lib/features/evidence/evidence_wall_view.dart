import 'package:flutter/material.dart';
import '../../ui/design_theme.dart';
import '../reader/reader_view_model.dart';
import '../reader/annotations/note_composer.dart';
import '../reader/annotations/paragraph_notes_dialog.dart';
import 'evidence_canvas.dart';

class EvidenceWallView extends StatelessWidget {
  const EvidenceWallView({required this.reader, super.key});
  final ReaderViewModel reader;
  @override
  Widget build(BuildContext context) {
    final wall = reader.wall!;
    return ListenableBuilder(
      listenable: wall,
      builder: (context, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '線索牆 · ${wall.notes.length} 則筆記',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  '${wall.edges.length} 條紅線',
                  style: TextStyle(color: context.design.muted, fontSize: 12),
                ),
                TextButton.icon(
                  onPressed: reader.busy
                      ? null
                      : () => openNoteComposer(context, reader),
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('新增線索'),
                ),
                TextButton(
                  onPressed: () => openParagraphNotes(
                    context,
                    reader,
                    null,
                    reader.book!.head.notes,
                  ),
                  child: const Text('全部筆記'),
                ),
                if (wall.linkSource != null)
                  TextButton(
                    onPressed: wall.cancelLink,
                    child: const Text('取消連線'),
                  ),
                if (wall.dirty || wall.error.isNotEmpty)
                  TextButton(
                    onPressed: wall.busy
                        ? null
                        : () async {
                            try {
                              if (!wall.loaded) {
                                await wall.load();
                              } else {
                                await wall.flush();
                              }
                            } catch (_) {}
                          },
                    child: const Text('重試保存'),
                  ),
                Text(
                  wall.status == 'pending'
                      ? '布局待保存'
                      : wall.status == 'saving'
                      ? '布局保存中…'
                      : wall.status == 'error'
                      ? '布局保存失敗'
                      : '布局已保存',
                  style: TextStyle(color: context.design.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (wall.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                wall.error,
                style: TextStyle(color: context.design.rust),
              ),
            ),
          if (wall.unplaced > 0) Text('另有 ${wall.unplaced} 則筆記可從「全部筆記」查看'),
          if (wall.busy) const LinearProgressIndicator(),
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              '拖動卡片標頭整理位置；拖曳圖釘，或依序點兩個圖釘連紅線。點紅線可描述關係。',
              style: TextStyle(fontSize: 11),
            ),
          ),
          Expanded(
            child: wall.cards.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hub_outlined,
                          size: 40,
                          color: context.design.muted,
                        ),
                        const SizedBox(height: 16),
                        const Text('從一段文字，開始整理線索。'),
                        const SizedBox(height: 10),
                        const Text('閱讀時選取文字，使用「作筆記」；筆記會出現在這裡。'),
                      ],
                    ),
                  )
                : IgnorePointer(
                    ignoring: reader.busy || wall.busy,
                    child: EvidenceCanvas(
                      model: wall,
                      onOpen: (note) =>
                          openParagraphNotes(context, reader, null, [note]),
                      onReveal: reader.revealNote,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
