import 'package:flutter/material.dart';
import '../../../ui/motion.dart';
import '../reader_view_model.dart';
import 'document_view.dart';
import 'editor_view.dart';
import 'history_view.dart';
import '../../evidence/evidence_wall_view.dart';

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
      ReaderTab.notes => EvidenceWallView(reader: model),
      ReaderTab.read => DocumentView(model: model),
    },
  );
}
