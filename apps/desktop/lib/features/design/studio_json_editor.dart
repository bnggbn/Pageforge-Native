import 'package:flutter/material.dart';

class StudioJsonEditor extends StatefulWidget {
  const StudioJsonEditor({
    required this.source,
    required this.onChanged,
    super.key,
  });
  final String source;
  final ValueChanged<String> onChanged;
  @override
  State<StudioJsonEditor> createState() => _StudioJsonEditorState();
}

class _StudioJsonEditorState extends State<StudioJsonEditor> {
  late final controller = TextEditingController(text: widget.source);
  @override
  void didUpdateWidget(StudioJsonEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.text != widget.source) controller.text = widget.source;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: TextField(
      key: const ValueKey('design-json'),
      controller: controller,
      onChanged: widget.onChanged,
      expands: true,
      maxLines: null,
      minLines: null,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontFamily: 'Consolas', fontSize: 12, height: 1.6),
      decoration: const InputDecoration(
        border: InputBorder.none,
        hintText: '外觀 JSON',
      ),
    ),
  );
}
