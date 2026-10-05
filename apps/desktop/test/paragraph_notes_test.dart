import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/features/reader/annotations/note_cloud.dart';
import 'package:pageforge/features/reader/annotations/note_composer.dart';
import 'package:pageforge/features/reader/annotations/paragraph_index.dart';
import 'package:pageforge/features/reader/annotations/paragraph_location.dart';
import 'package:pageforge/features/reader/reader_screen.dart';
import 'package:pageforge/features/reader/reader_view_model.dart';
import 'package:pageforge/features/reader/reading_position.dart';
import 'package:pageforge/features/reader/views/text_document_view.dart';
import 'package:pageforge/features/evidence/evidence_card.dart';
import 'package:pageforge/ui/theme.dart';
import 'fake_repository.dart';

RenderParagraph paragraph(WidgetTester tester, String value) =>
    tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == value,
      ),
    );
Offset caret(RenderParagraph paragraph, int offset) => paragraph.localToGlobal(
  paragraph.getOffsetForCaret(TextPosition(offset: offset), Rect.zero) +
      Offset(0, paragraph.preferredLineHeight / 2),
);
void main() {
  test(
    'content anchors survive unrelated edits and reject ambiguous duplicate moves',
    () {
      String hash(String text) => sha256.convert(utf8.encode(text)).toString();
      final old = ParagraphIndex('Alpha\n\nBeta', 0);
      old.entries = [
        ParagraphEntry(
          'Alpha',
          hash('Alpha'),
          0,
          const Rect.fromLTWH(0, 0, 200, 20),
        ),
        ParagraphEntry(
          'Beta',
          hash('Beta'),
          0,
          const Rect.fromLTWH(0, 30, 200, 20),
        ),
      ];
      final anchor = old
          .passage('pha\nBeta', old.entries.first, old.entries.last)
          .location;
      expect(anchor.length, lessThan(300));
      expect(ParagraphLocation.parse(anchor), isNotNull);
      final edited = ParagraphIndex('Introduction\n\nAlpha\n\nBeta', 0)
        ..entries = old.entries;
      expect(edited.resolve(anchor, 'pha\nBeta'), hasLength(2));
      final duplicate = ParagraphIndex('Alpha\n\nAlpha\n\nBeta', 0)
        ..entries = [
          old.entries.first,
          ParagraphEntry(
            'Alpha',
            hash('Alpha'),
            1,
            const Rect.fromLTWH(0, 30, 200, 20),
          ),
          old.entries.last,
        ];
      expect(duplicate.resolve(anchor, 'pha\nBeta'), isEmpty);
      expect(edited.resolve('', 'Alpha'), hasLength(1));
    },
  );
  testWidgets(
    'desktop right-click notes span paragraphs; clouds exclude numbers from copy',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var clipboard = '';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String;
            }
            if (call.method == 'Clipboard.getData') return {'text': clipboard};
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final repo = FakeRepository();
      repo.data['revisions'][0]['content'] =
          '# Document title\n\nAlpha **bold** text.\n\nBeta middle.\n\nGamma ending.';
      await tester.pumpWidget(
        MaterialApp(
          theme: pageforgeTheme(),
          home: ReaderScreen(repository: repo, id: repo.data['id'] as String),
        ),
      );
      await tester.pumpAndSettle();
      final drag = await tester.startGesture(
        caret(paragraph(tester, 'Alpha bold text.'), 6),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(caret(paragraph(tester, 'Gamma ending.'), 5));
      await drag.up();
      await tester.pumpAndSettle();
      final right = await tester.startGesture(
        caret(paragraph(tester, 'Beta middle.'), 3),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await right.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('作筆記'));
      await tester.pumpAndSettle();
      expect(find.text('「bold text.\nBeta middle.\nGamma」'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('note-body')),
        '這三段互相呼應',
      );
      await tester.pump();
      await tester.tap(find.text('保存筆記'));
      await tester.pumpAndSettle();
      final note = repo.data['revisions'].last['notes'].single;
      expect(note['quote'], 'bold text.\nBeta middle.\nGamma');
      expect(ParagraphLocation.parse(note['location'] as String), isNotNull);
      expect(find.byType(NoteCloud), findsNWidgets(3));
      final click = await tester.startGesture(
        caret(paragraph(tester, 'Document title'), 0),
        kind: PointerDeviceKind.mouse,
      );
      await click.up();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
        clipboard,
        'Document title\nAlpha bold text.\nBeta middle.\nGamma ending.',
      );
      await tester.tap(find.byType(NoteCloud).first);
      await tester.pumpAndSettle();
      expect(find.text('這三段互相呼應'), findsOneWidget);
      await tester.tap(find.text('在線索牆查看'));
      await tester.pumpAndSettle();
      expect(find.byType(EvidenceCard), findsOneWidget);
      expect(find.text('線索牆'), findsOneWidget);
      await tester.tap(find.text('回到原文'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteCloud), findsNWidgets(3));
      await drag.removePointer();
      await right.removePointer();
      await click.removePointer();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );
  testWidgets(
    'touch long-press exposes annotate action on Android',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeRepository();
      final position = ReadingPosition(
        repo,
        await repo.load(repo.data['id'] as String),
        const Duration(milliseconds: 450),
        (_) {},
      );
      NotePassage? passage;
      await tester.pumpWidget(
        MaterialApp(
          theme: pageforgeTheme(),
          home: Scaffold(
            body: TextDocumentView(
              content: 'Alpha paragraph.',
              markdown: true,
              fontSize: 18,
              position: position,
              onQuote: (_) {},
              onCreateNote: (value) => passage = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final touch = await tester.startGesture(
        caret(paragraph(tester, 'Alpha paragraph.'), 2),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 700));
      await touch.up();
      await tester.pumpAndSettle();
      expect(find.text('作筆記'), findsOneWidget);
      await tester.tap(find.text('作筆記'));
      await tester.pumpAndSettle();
      expect(passage?.quote, 'Alpha');
      expect(ParagraphLocation.parse(passage!.location), isNotNull);
      await touch.removePointer();
      await tester.pumpWidget(const SizedBox());
      position.dispose();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
  testWidgets('oversized quote is rejected before changing persisted draft', (
    tester,
  ) async {
    final repo = FakeRepository();
    // Use the same repository so the working-copy baseline is a real synthetic book.
    final model = ReaderViewModel(repo, repo.data['id'] as String);
    await model.load();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: pageforgeTheme(),
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await openNoteComposer(context, model, NotePassage('字' * 2001, '全文筆記'));
    await tester.pump();
    expect(find.byType(NoteComposer), findsNothing);
    expect(model.working!.quote, isEmpty);
    expect(repo.savedDraft, isNull);
    model.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
