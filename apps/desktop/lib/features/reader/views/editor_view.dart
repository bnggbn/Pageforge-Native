import 'package:flutter/material.dart';
import '../reader_view_model.dart';

class EditorView extends StatefulWidget {
  const EditorView({required this.model, super.key});
  final ReaderViewModel model;
  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
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
