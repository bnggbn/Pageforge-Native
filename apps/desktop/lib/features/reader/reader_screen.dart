import 'package:flutter/material.dart';
import '../../data/library_repository.dart';
import '../../ui/theme.dart';
import 'reader_view_model.dart';
import 'views/reader_pane.dart';
import 'views/reader_toolbar.dart';
import 'views/working_copy_bar.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({required this.repository, required this.id, super.key});
  final LibraryRepository repository;
  final String id;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final ReaderViewModel model;
  bool leaving = false;
  @override
  void initState() {
    super.initState();
    model = ReaderViewModel(widget.repository, widget.id);
    model.load();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  Future<void> back() async {
    if (model.busy || !await model.flush() || !mounted) return;
    setState(() {
      leaving = true;
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) back();
    },
    child: Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: model,
          builder: (context, _) {
            final book = model.book;
            return Padding(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: model.busy ? null : back,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          book?.title ?? '正在驗證版本…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      if (book != null)
                        Text(
                          '${book.revisions.length} 個版本',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                    ],
                  ),
                  const Divider(),
                  if (book != null && model.working != null) ...[
                    ReaderToolbar(model: model),
                    WorkingCopyBar(copy: model.working!),
                  ],
                  if (model.error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: SelectableText(
                        model.error,
                        style: const TextStyle(color: rust),
                      ),
                    ),
                  if (model.message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        model.message,
                        style: const TextStyle(color: forest),
                      ),
                    ),
                  if (model.busy) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  if (book != null && model.working != null)
                    Expanded(child: ReaderPane(model: model)),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
