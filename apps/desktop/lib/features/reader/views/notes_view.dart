import 'package:flutter/material.dart';
import '../../../ui/theme.dart';
import '../reader_view_model.dart';

class NotesView extends StatefulWidget {
  const NotesView({required this.model, super.key});
  final ReaderViewModel model;
  @override
  State<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<NotesView> {
  late final TextEditingController body, quote, location;
  @override
  void initState() {
    super.initState();
    final copy = widget.model.working!;
    body = TextEditingController(text: copy.body);
    quote = TextEditingController(text: copy.quote);
    location = TextEditingController(text: copy.location);
    copy.addListener(sync);
  }

  void sync() {
    final copy = widget.model.working!;
    if (body.text != copy.body) body.text = copy.body;
    if (quote.text != copy.quote) quote.text = copy.quote;
    if (location.text != copy.location) location.text = copy.location;
  }

  @override
  void dispose() {
    widget.model.working!.removeListener(sync);
    body.dispose();
    quote.dispose();
    location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const Text('留下一個想法', style: TextStyle(fontSize: 21)),
      const SizedBox(height: 16),
      TextField(
        controller: body,
        maxLines: 5,
        readOnly: widget.model.busy,
        onChanged: (value) => widget.model.working!.change({'body': value}),
        decoration: const InputDecoration(labelText: '筆記'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: quote,
        maxLines: 3,
        readOnly: widget.model.busy,
        onChanged: (value) => widget.model.working!.change({'quote': value}),
        decoration: const InputDecoration(labelText: '引用文字'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: location,
        readOnly: widget.model.busy,
        onChanged: (value) => widget.model.working!.change({'location': value}),
        decoration: const InputDecoration(labelText: '位置'),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: widget.model.busy ? null : widget.model.addNote,
        child: const Text('保存筆記'),
      ),
      const SizedBox(height: 26),
      const Divider(),
      for (final note in widget.model.book!.head.notes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${note['location']}',
                style: const TextStyle(color: muted, fontSize: 11),
              ),
              if ('${note['quote']}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: SelectableText(
                    '「${note['quote']}」',
                    style: const TextStyle(color: forest),
                  ),
                ),
              SelectableText('${note['body']}'),
              TextButton(
                onPressed: widget.model.busy
                    ? null
                    : () => widget.model.removeNote(note['id'] as String),
                child: const Text('移除筆記'),
              ),
            ],
          ),
        ),
    ],
  );
}
