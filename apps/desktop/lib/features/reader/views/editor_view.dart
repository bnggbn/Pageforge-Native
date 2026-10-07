import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../reader_view_model.dart';
import '../sectioned_draft.dart';
import 'section_navigation.dart';

class EditorView extends StatefulWidget {
  const EditorView({required this.model, super.key});
  final ReaderViewModel model;
  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  late SectionedDraft draft;
  late TextEditingController controller;
  int section = 0;
  @override
  void initState() {
    super.initState();
    draft = widget.model.working!.editSections(
      (widget.model.config['reading']?['editorSectionUnits'] as int?) ?? 16000,
    );
    controller = TextEditingController(text: draft.section(section));
  }

  void selectSection(int value) {
    if (value == section) return;
    setState(() {
      section = value;
      controller.value = TextEditingValue(
        text: draft.section(section),
        selection: const TextSelection.collapsed(offset: 0),
      );
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (draft.length > 1)
        Row(
          children: [
            Expanded(
              child: SectionNavigation(
                index: section,
                count: draft.length,
                onChanged: widget.model.busy ? null : selectSection,
              ),
            ),
            IconButton(
              tooltip: '複製全文',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: draft.text));
              },
            ),
          ],
        ),
      Expanded(
        child: TextField(
          key: ValueKey(section),
          controller: controller,
          expands: true,
          minLines: null,
          maxLines: null,
          readOnly: widget.model.busy,
          onChanged: (value) {
            draft = draft.replace(section, value);
            widget.model.working!.change({'content': draft});
          },
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontSize: 15,
            height: 1.8,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: draft.length > 1 ? '在這一節繼續寫……' : '在這裡繼續寫……',
            contentPadding: const EdgeInsets.all(24),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: widget.model.busy ? null : widget.model.saveEdit,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存為新版本'),
          ),
        ),
      ),
    ],
  );
}
