import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/data/models.dart';
import 'package:pageforge/features/reader/annotations/note_cloud.dart';
import 'package:pageforge/features/reader/annotations/note_section.dart';
import 'package:pageforge/features/reader/annotations/paragraph_location.dart';
import 'package:pageforge/features/reader/reader_view_model.dart';
import 'package:pageforge/features/reader/views/document_view.dart';
import 'package:pageforge/ui/theme.dart';
import 'fake_repository.dart';

const shared = 'A paragraph repeated in both chapters.';
const chapters = <Json>[
  {'title': 'Opening', 'text': 'First chapter.\n\n$shared'},
  {'title': 'Discovery', 'text': 'Second chapter.\n\n$shared'},
];
Json note(String id, String location, [String quote = shared]) => {
  'id': id,
  'body': 'A chapter clue.',
  'quote': quote,
  'location': location,
  'createdAt': '2026-10-05T00:00:00Z',
};
String anchor(int chapter) {
  String hash(String value) => sha256.convert(utf8.encode(value)).toString();
  return ParagraphLocation(
    section: chapter,
    contentHash: hash(chapters[chapter]['text'] as String),
    startHash: hash(shared),
    startOccurrence: 0,
    endHash: hash(shared),
    endOccurrence: 0,
  ).encoded;
}

void main() {
  test(
    'EPUB chapter identity resolves new and old notes without guessing duplicate quotations',
    () {
      expect(noteSection(note('new', anchor(1)), chapters), 1);
      expect(noteSection(note('old', 'Discovery / row-2'), chapters), 1);
      expect(noteSection(note('unique', '全文', 'First chapter.'), chapters), 0);
      expect(noteSection(note('ambiguous', '全文'), chapters), isNull);
      expect(noteSection(note('wrong', 'Unknown / row-2'), chapters), isNull);
      expect(noteSection(note('empty', '全文', ''), chapters), isNull);
      final duplicateTitles = <Json>[
        {'title': 'Same', 'text': 'only here'},
        {'title': 'Same', 'text': 'elsewhere'},
      ];
      expect(
        noteSection(
          note('ambiguous-title', 'Same / row-0', 'only here'),
          duplicateTitles,
        ),
        0,
      );
    },
  );
  testWidgets(
    'EPUB clouds follow paragraph tails after reflow and navigate to the right chapter',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeRepository();
      final saved = note('40000000-0000-4000-8000-000000000001', anchor(1));
      final old = note(
        '40000000-0000-4000-8000-000000000002',
        'Discovery / row-2',
      );
      repo.data['format'] = 'epub';
      repo.data['sections'] = chapters;
      repo.data['revisions'][0]['notes'] = [saved, old];
      final model = ReaderViewModel(repo, repo.data['id'] as String);
      await model.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: pageforgeTheme(),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: model,
              builder: (context, _) => DocumentView(model: model),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NoteCloud), findsNothing);
      await model.revealNote(saved);
      await tester.pumpAndSettle();
      expect(model.section, 1);
      expect(find.byType(NoteCloud), findsOneWidget);
      expect(tester.widget<NoteCloud>(find.byType(NoteCloud)).count, 2);
      void checkPlacement() {
        final content = chapters[1]['text'] as String;
        final render = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text(content),
            matching: find.byType(RichText),
          ),
        );
        final end = render.getOffsetForCaret(
          TextPosition(offset: content.length),
          Rect.zero,
        );
        final box = render
            .getBoxesForSelection(
              TextSelection(
                baseOffset: content.length - 1,
                extentOffset: content.length,
              ),
            )
            .last;
        final expected = render.localToGlobal(
          Offset(end.dx, (box.top + box.bottom) / 2),
        );
        final cloud = tester.getRect(find.byType(NoteCloud));
        expect(cloud.left, closeTo(expected.dx + 4, .5));
        expect(cloud.center.dy, closeTo(expected.dy, .5));
        expect(cloud.right, lessThanOrEqualTo(tester.view.physicalSize.width));
        expect(render.localToGlobal(Offset.zero).dy, lessThan(150));
      }

      checkPlacement();
      model.resize(28);
      tester.view.physicalSize = const Size(420, 800);
      await tester.pumpAndSettle();
      expect(find.byType(NoteCloud), findsOneWidget);
      checkPlacement();
      await model.selectSection(0);
      await tester.pumpAndSettle();
      expect(find.byType(NoteCloud), findsNothing);
      expect(model.noteToReveal, isNull);
      expect(find.text('原段落已變動或引用不唯一；筆記保留了當時選取的原文。'), findsNothing);
      await model.revealNote(old);
      await tester.pumpAndSettle();
      expect(model.section, 1);
      expect(find.byType(NoteCloud), findsOneWidget);
      await model.showEvidence(saved['id'] as String);
      await model.revealNote(note('ambiguous', '全文'));
      expect(model.tab, ReaderTab.notes);
      expect(model.error, contains('無法唯一定位'));
      expect(
        repo.data['revisions'][0]['notes'][1]['location'],
        'Discovery / row-2',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
      await tester.pumpAndSettle();
    },
  );
}
