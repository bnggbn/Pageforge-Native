// Opt-in layout control: editor widget copied from abc5c7b.
// Uses the current theme/WorkingCopy so this measures only whole-field layout.
// Production code must use EditorView, never this diagnostic fixture.
import 'package:flutter/material.dart';
import 'package:pageforge/features/reader/reader_view_model.dart';

class LegacyEditorView extends StatefulWidget {
  const LegacyEditorView({required this.model, super.key});
  final ReaderViewModel model;
  @override
  State<LegacyEditorView> createState() => _LegacyEditorViewState();
}

class _LegacyEditorViewState extends State<LegacyEditorView> {
  late final TextEditingController controller;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.model.working!.content);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: TextField(
          controller: controller,
          expands: true,
          minLines: null,
          maxLines: null,
          readOnly: widget.model.busy,
          onChanged: (value) =>
              widget.model.working!.change({'content': value}),
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontSize: 15,
            height: 1.8,
          ),
          decoration: const InputDecoration(contentPadding: EdgeInsets.all(24)),
        ),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: widget.model.busy ? null : widget.model.saveEdit,
          child: const Text('保存為新版本'),
        ),
      ),
    ],
  );
}
