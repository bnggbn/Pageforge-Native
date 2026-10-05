import 'package:flutter/material.dart';
import '../../../ui/design_theme.dart';
import '../reader_view_model.dart';
import 'paragraph_location.dart';

Future<void> openNoteComposer(
  BuildContext context,
  ReaderViewModel model, [
  NotePassage? passage,
]) async {
  if (model.busy || model.working == null) return;
  final limit = (model.config['limits']?['quoteCharacters'] as int?) ?? 2000;
  if (passage != null && passage.quote.runes.length > limit) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('選取範圍超過 $limit 字，請縮小選取後再作筆記。')));
    return;
  }
  final copy = model.working!;
  if (copy.body.trim().isEmpty && passage != null) {
    copy.change({'quote': passage.quote, 'location': passage.location});
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => NoteComposer(model: model),
  );
}

class NoteComposer extends StatefulWidget {
  const NoteComposer({required this.model, super.key});
  final ReaderViewModel model;
  @override
  State<NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends State<NoteComposer> {
  late final body = TextEditingController(text: widget.model.working!.body);
  bool leaving = false;
  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  Future<void> leave() async {
    if (widget.model.busy || !await widget.model.flush() || !mounted) return;
    setState(() => leaving = true);
    Navigator.pop(context);
  }

  Future<void> save() async {
    await widget.model.addNote();
    if (!mounted || widget.model.working!.body.isNotEmpty) return;
    setState(() => leaving = true);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.model, widget.model.working!]),
    builder: (context, _) => PopScope(
      canPop: leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) leave();
      },
      child: AlertDialog(
        title: const Text('作筆記'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.model.working!.quote.isNotEmpty) ...[
                  Text(
                    ParagraphLocation.label(widget.model.working!.location),
                    style: TextStyle(color: context.design.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    '「${widget.model.working!.quote}」',
                    style: TextStyle(
                      color: context.design.forest,
                      fontSize: 13,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                TextField(
                  key: const ValueKey('note-body'),
                  controller: body,
                  maxLines: 6,
                  minLines: 3,
                  maxLength:
                      (widget.model.config['limits']?['noteCharacters']
                          as int?) ??
                      10000,
                  readOnly: widget.model.busy,
                  onChanged: (value) =>
                      widget.model.working!.change({'body': value}),
                  decoration: const InputDecoration(
                    labelText: '我的想法',
                    hintText: '這段文字讓你想到什麼？',
                    counterText: '',
                  ),
                ),
                if (widget.model.error.isNotEmpty)
                  Text(
                    widget.model.error,
                    style: TextStyle(color: context.design.rust),
                  ),
                if (widget.model.working!.error.isNotEmpty)
                  Text(
                    widget.model.working!.error,
                    style: TextStyle(color: context.design.rust),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: widget.model.busy ? null : leave,
            child: const Text('稍後再寫'),
          ),
          FilledButton(
            onPressed: widget.model.busy || body.text.trim().isEmpty
                ? null
                : save,
            child: const Text('保存筆記'),
          ),
        ],
      ),
    ),
  );
}
