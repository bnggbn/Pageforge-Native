import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../data/library_repository.dart';
import '../../ui/theme.dart';
import '../../ui/motion.dart';
import '../reader/reader_screen.dart';
import 'book_tile.dart';
import 'library_view_model.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.repository, super.key});
  final LibraryRepository repository;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final LibraryViewModel model;
  @override
  void initState() {
    super.initState();
    model = LibraryViewModel(widget.repository);
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
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          final visible = model.visible;
          final indices = {
            for (var i = 0; i < visible.length; i++) visible[i].id: i,
          };
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(48, 28, 48, 0),
                sliver: SliverToBoxAdapter(
                  child: MotionEntrance(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Pageforge',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const Text(
                              '.',
                              style: TextStyle(color: rust, fontSize: 30),
                            ),
                            const Spacer(),
                            const Icon(Icons.circle, color: forest, size: 7),
                            const SizedBox(width: 8),
                            const Text(
                              'LOCAL FIRST',
                              style: TextStyle(
                                color: muted,
                                fontSize: 10,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 34),
                        const Text(
                          'YOUR PERSONAL LIBRARY',
                          style: TextStyle(
                            color: muted,
                            fontSize: 10,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 24,
                          runSpacing: 20,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '為文字，留一個位置。',
                              style: Theme.of(context).textTheme.displaySmall,
                            ),
                            FilledButton.icon(
                              onPressed: model.busy ? null : import,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('匯入文件'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          '閱讀、記錄，讓每個想法都有回去的路。',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                        const SizedBox(height: 30),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xffe9ecdf),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Wrap(
                            spacing: 24,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Icon(
                                Icons.folder_outlined,
                                size: 18,
                                color: forest,
                              ),
                              const Text(
                                'library / collection',
                                style: TextStyle(fontSize: 12),
                              ),
                              TextButton(
                                onPressed: model.busy ? null : model.sync,
                                child: const Text('重新載入資料夾 ↗'),
                              ),
                              const Text(
                                '來源、筆記與版本保存在本機',
                                style: TextStyle(color: muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        if (model.error.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: SelectableText(
                              model.error,
                              style: const TextStyle(color: rust),
                            ),
                          ),
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            Text(
                              '我的書架 · ${model.books.length}',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 220,
                              child: TextField(
                                onChanged: model.search,
                                decoration: const InputDecoration(
                                  hintText: '尋找一份文件',
                                  prefixIcon: Icon(Icons.search, size: 18),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 25),
                        if (model.busy) const LinearProgressIndicator(),
                      ],
                    ),
                  ),
                ),
              ),
              if (!model.busy && visible.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(60),
                    child: Center(
                      child: Text(
                        '把文件放進 collection，或匯入第一份文字。',
                        style: TextStyle(color: muted),
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                sliver: SliverGrid.builder(
                  itemCount: visible.length,
                  findChildIndexCallback: (key) =>
                      indices[(key as ValueKey<String>).value],
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 250,
                    mainAxisExtent: 320,
                    crossAxisSpacing: 26,
                    mainAxisSpacing: 34,
                  ),
                  itemBuilder: (context, index) {
                    final book = visible[index];
                    return MotionEntrance(
                      key: ValueKey(book.id),
                      delay: Duration(milliseconds: index.clamp(0, 6) * 30),
                      child: BookTile(book: book, onOpen: () => open(book.id)),
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: Column(
                    children: [
                      Divider(),
                      SizedBox(height: 15),
                      Text(
                        'PAGEFORGE / 為閱讀留白。',
                        style: TextStyle(
                          color: muted,
                          fontSize: 10,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
