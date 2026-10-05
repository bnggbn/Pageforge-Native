import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../ui/design_theme.dart';
import '../../ui/theme.dart';
import '../library/book_tile.dart';
import '../library/library_header.dart';
import '../library/reading_invitation.dart';
import '../reader/views/article_body.dart';
import '../reader/views/document_selection.dart';
import 'design_document.dart';
import 'studio_view_model.dart';

class StudioPreview extends StatelessWidget {
  const StudioPreview({required this.document, required this.scene, super.key});
  final DesignDocument document;
  final DesignScene scene;
  static final books = [
    for (var i = 0; i < 4; i++)
      BookSummary({
        'id': 'design-preview-$i',
        'title': ['紙上的光', '慢慢讀的日子', '思想的留白', '手稿與遠方'][i],
        'filename': 'preview.md',
        'format': 'markdown',
        'revisionCount': 3,
        'progress': i * 12,
      }),
  ];
  @override
  Widget build(BuildContext context) => Theme(
    data: pageforgeTheme(document),
    child: Builder(
      builder: (context) => ColoredBox(
        key: const ValueKey('design-preview'),
        color: context.design.paper,
        child: RepaintBoundary(
          child: scene == DesignScene.reader
              ? const _ReaderPreview()
              : const _ShelfPreview(),
        ),
      ),
    ),
  );
}

class _ShelfPreview extends StatelessWidget {
  const _ShelfPreview();
  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.all(24),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LibraryHeader(onImport: null),
              const SizedBox(height: 24),
              if (context.design.showInvitation)
                ReadingInvitation(
                  book: StudioPreview.books.first,
                  onOpen: null,
                ),
              const SizedBox(height: 24),
              Text(
                '我的書架 · 預覽文件',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        sliver: SliverGrid.builder(
          itemCount: StudioPreview.books.length,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: context.design.cardWidth,
            mainAxisExtent: 365,
            crossAxisSpacing: context.design.gap,
            mainAxisSpacing: context.design.gap,
          ),
          itemBuilder: (context, index) =>
              BookTile(book: StudioPreview.books[index], onOpen: () {}),
        ),
      ),
    ],
  );
}

class _ReaderPreview extends StatefulWidget {
  const _ReaderPreview();
  @override
  State<_ReaderPreview> createState() => _ReaderPreviewState();
}

class _ReaderPreviewState extends State<_ReaderPreview> {
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: context.design.pageWidth),
      child: DocumentSelection(
        scrollController: scroll,
        onQuote: (_) {},
        child: const ArticleBody(
          content:
              '# 為文字，留一個位置。\n\n午後的光落在紙上，每一行字都多了一點停留的空間。這是一份專供外觀預覽的短文。\n\n## 留白，也是一種節奏\n\n調整行高、紙張與文字色彩，看閱讀的節奏如何改變。你可以跨段落選取與複製這些文字。\n\n好的版面，讓文字先被看見。',
          markdown: true,
          fontSize: 18,
        ),
      ),
    ),
  );
}
