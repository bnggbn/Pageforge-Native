import 'package:flutter/material.dart';
import '../../../ui/motion.dart';
import '../reader_view_model.dart';
import 'document_view.dart';
import 'editor_view.dart';
import 'history_view.dart';
import 'notes_view.dart';

class ReaderPane extends StatelessWidget {
  const ReaderPane({required this.model, super.key});
  final ReaderViewModel model;

  @override
  Widget build(BuildContext context) => MotionEntrance(
    key: ValueKey(model.tab),
    offset: const Offset(0, .015),
    child: switch (model.tab) {
      ReaderTab.edit => EditorView(model: model),
      ReaderTab.history => HistoryView(model: model),
      ReaderTab.notes => LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth > 800
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: DocumentView(model: model)),
                  const SizedBox(width: 32),
                  SizedBox(width: 330, child: NotesView(model: model)),
                ],
              )
            : NotesView(model: model),
      ),
      ReaderTab.read => DocumentView(model: model),
    },
  );
}
