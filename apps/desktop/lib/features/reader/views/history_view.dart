import 'package:flutter/material.dart';
import '../../../data/models.dart';
import '../../../ui/theme.dart';
import '../../history/diff_view_model.dart';
import '../reader_view_model.dart';

class HistoryView extends StatefulWidget {
  const HistoryView({required this.model, super.key});
  final ReaderViewModel model;
  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  late final DiffViewModel diff;
  late String from, to;
  @override
  void initState() {
    super.initState();
    final book = widget.model.book!;
    diff = DiffViewModel(widget.model.repository, book);
    from = book.revisions.length > 1
        ? book.revisions[book.revisions.length - 2].id
        : book.head.id;
    to = book.head.id;
    diff.compare(from, to);
  }

  @override
  void dispose() {
    diff.dispose();
    super.dispose();
  }

  Future<void> restore(Revision revision) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('把這份內容還原成新版本？'),
        content: const Text('既有版本會保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('還原'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.model.restore(revision);
  }

  Widget selector(String value, ValueChanged<String> change) =>
      DropdownButton<String>(
        value: value,
        items: [
          for (var i = 0; i < widget.model.book!.revisions.length; i++)
            DropdownMenuItem(
              value: widget.model.book!.revisions[i].id,
              child: Text(
                '第 ${i + 1} 版 · ${widget.model.book!.revisions[i].kind}',
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) change(value);
        },
      );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: diff,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            selector(from, (value) {
              setState(() {
                from = value;
              });
              diff.compare(from, to);
            }),
            const Icon(Icons.arrow_forward, size: 16),
            selector(to, (value) {
              setState(() {
                to = value;
              });
              diff.compare(from, to);
            }),
            TextButton(
              onPressed: widget.model.busy
                  ? null
                  : () => restore(
                      widget.model.book!.revisions.firstWhere(
                        (r) => r.id == to,
                      ),
                    ),
              child: const Text('還原所選版本為新版'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (diff.busy) const LinearProgressIndicator(),
        if (diff.error.isNotEmpty)
          Text(diff.error, style: const TextStyle(color: rust)),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: SelectableText.rich(
              TextSpan(
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 14,
                  height: 1.9,
                  color: ink,
                ),
                children: [
                  for (final part in diff.parts)
                    TextSpan(
                      text: part['text'] as String,
                      style: TextStyle(
                        color: part['kind'] == 'insert'
                            ? forest
                            : part['kind'] == 'delete'
                            ? rust
                            : ink,
                        backgroundColor: part['kind'] == 'insert'
                            ? const Color(0xffe1eddf)
                            : part['kind'] == 'delete'
                            ? const Color(0xfff3ddd7)
                            : null,
                        decoration: part['kind'] == 'delete'
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
