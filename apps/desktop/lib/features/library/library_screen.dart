import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../data/library_repository.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../reader/reader_screen.dart';
import 'book_tile.dart';
import 'library_header.dart';
import 'library_view_model.dart';
import 'reading_invitation.dart';
import 'shelf_toolbar.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.repository, super.key});
  final LibraryRepository repository;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final model = LibraryViewModel(widget.repository);
  @override
  void initState() {
    super.initState();
    model.load();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  Future<void> open(String id) async {
    await Navigator.of(context).push(
      PageforgeMotion.route<void>(
        context,
        builder: (_) => ReaderScreen(repository: widget.repository, id: id),
      ),
    );
    if (mounted) await model.load();
  }

  Future<void> import() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Markdown / TXT',
          extensions: ['md', 'markdown', 'txt'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    final id = await model.import(file.path);
    if (id != null && mounted) await open(id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final margin = bounds.maxWidth < 700 ? 24.0 : 48.0;
          return ListenableBuilder(
            listenable: model,
            builder: (context, _) {
              final visible = model.visible;
              final indices = {
                for (var i = 0; i < visible.length; i++) visible[i].id: i,
              };
              final featured = model.books.isEmpty
                  ? null
                  : model.books.firstWhere(
                      (book) => book.progress > 0 && book.progress < 100,
                      orElse: () => model.books.first,
                    );
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(margin, 26, margin, 26),
                    sliver: SliverToBoxAdapter(
                      child: MotionEntrance(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LibraryHeader(onImport: model.busy ? null : import),
                            const SizedBox(height: 30),
                            ReadingInvitation(
                              book: featured,
                              onOpen: model.busy || featured == null
                                  ? null
                                  : () => open(featured.id),
                            ),
                            const SizedBox(height: 24),
                            ShelfToolbar(
                              count: model.books.length,
                              onSearch: model.search,
                              onSync: model.busy ? null : model.sync,
                            ),
                            if (model.error.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: SelectableText(
                                  model.error,
                                  style: const TextStyle(color: rust),
                                ),
                              ),
                            const SizedBox(height: 8),
                            if (model.busy) const LinearProgressIndicator(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!model.busy && visible.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            '把文件放進 collection，或匯入第一份文字。',
                            style: TextStyle(color: muted),
                          ),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: margin),
                    sliver: SliverGrid.builder(
                      itemCount: visible.length,
                      findChildIndexCallback: (key) =>
                          indices[(key as ValueKey<String>).value],
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 260,
                            mainAxisExtent: 365,
                            crossAxisSpacing: 28,
                            mainAxisSpacing: 32,
                          ),
                      itemBuilder: (context, index) {
                        final book = visible[index];
                        return MotionEntrance(
                          key: ValueKey(book.id),
                          delay: Duration(milliseconds: index.clamp(0, 6) * 30),
                          child: BookTile(
                            book: book,
                            onOpen: () => open(book.id),
                          ),
                        );
                      },
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Divider(),
                          SizedBox(height: 18),
                          Text(
                            'PAGEFORGE / 給文字時間，也給自己空間。',
                            style: TextStyle(
                              color: muted,
                              fontSize: 10,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}
