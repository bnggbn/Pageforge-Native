import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../reader_view_model.dart';
import 'spreadsheet_view.dart';
import 'text_document_view.dart';

class DocumentView extends StatelessWidget {
  const DocumentView({required this.model, super.key});
  final ReaderViewModel model;
  @override
  Widget build(BuildContext context) {
    final book = model.book!;
    if (book.format == 'pdf') {
      return PdfViewer.file(
        book.originalPath,
        initialPageNumber: model.section + 1,
      );
    }
    if (book.format == 'xlsx') return SpreadsheetView(model: model);
    final sections = book.sections;
    final section = sections.isEmpty
        ? 0
        : model.section.clamp(0, sections.length - 1);
    final content = book.format == 'epub'
        ? (sections.isEmpty ? '' : sections[section]['text'] as String)
        : book.head.content;
    return Column(
      children: [
        if (sections.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: DropdownButton<int>(
              value: section,
              items: [
                for (var i = 0; i < sections.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(sections[i]['title'] as String),
                  ),
              ],
              onChanged: model.busy
                  ? null
                  : (value) {
                      if (value != null) model.selectSection(value);
                    },
            ),
          ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: TextDocumentView(
                key: ValueKey('${book.id}:$section:${model.contentEpoch}'),
                content: content,
                markdown: book.format == 'markdown',
                fontSize: model.fontSize,
                position: model.position!,
                onQuote: (value) => model.working!.change({'quote': value}),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
