import 'package:flutter/material.dart';
import '../../data/library_repository.dart';
import '../../ui/theme.dart';
import 'reader_view_model.dart';
import 'views/document_view.dart';
import 'views/editor_view.dart';
import 'views/history_view.dart';
import 'views/notes_view.dart';
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
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final entry in [
                          (ReaderTab.read, '閱讀'),
                          (ReaderTab.notes, '筆記'),
                          if (book.editable) (ReaderTab.edit, '編輯'),
                          (ReaderTab.history, '版本'),
                        ])
                          TextButton(
                            onPressed: model.busy
                                ? null
                                : () => model.changeTab(entry.$1),
                            style: TextButton.styleFrom(
                              foregroundColor: model.tab == entry.$1
                                  ? rust
                                  : muted,
                            ),
                            child: Text(entry.$2),
                          ),
                        const SizedBox(width: 16),
                        IconButton(
                          onPressed: model.canDecreaseFont
                              ? model.decreaseFont
                              : null,
                          icon: const Icon(Icons.text_decrease, size: 18),
                        ),
                        IconButton(
                          onPressed: model.canIncreaseFont
                              ? model.increaseFont
                              : null,
                          icon: const Icon(Icons.text_increase, size: 18),
                        ),
                      ],
                    ),
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
                    Expanded(
                      child: switch (model.tab) {
                        ReaderTab.edit => EditorView(model: model),
                        ReaderTab.history => HistoryView(model: model),
                        ReaderTab.notes => LayoutBuilder(
                          builder: (context, constraints) =>
                              constraints.maxWidth > 800
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: DocumentView(model: model)),
                                    const SizedBox(width: 32),
                                    SizedBox(
                                      width: 330,
                                      child: NotesView(model: model),
                                    ),
                                  ],
                                )
                              : NotesView(model: model),
                        ),
                        ReaderTab.read => DocumentView(model: model),
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
