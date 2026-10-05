import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:pageforge/features/reader/annotations/note_cloud.dart';
import 'package:pageforge/features/reader/annotations/paragraph_location.dart';
import 'package:pageforge/features/reader/reader_screen.dart';
import 'package:pageforge/ui/theme.dart';
import 'fake_repository.dart';
import 'paragraph_notes_test.dart' show paragraph, caret;

void main() {
  testWidgets(
    'hashes in code do not stop notes; formatted Setext titles do',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeRepository();
      repo.data['revisions'][0]['content'] =
          '# Guide\n\nBefore code.\n\n~~~\n# not a heading\n~~~\n\nAfter code.\n\nNext **chapter**\n---\n\nUnselected body.';
      await tester.pumpWidget(
        MaterialApp(
          theme: pageforgeTheme(),
          home: ReaderScreen(repository: repo, id: repo.data['id'] as String),
        ),
      );
      await tester.pumpAndSettle();
      final title = paragraph(tester, 'Next chapter');
      var hasBold = false;
      void visit(InlineSpan span) {
        hasBold |= span.style?.fontWeight == FontWeight.bold;
        if (span is TextSpan) {
          for (final child in span.children ?? <InlineSpan>[]) {
            visit(child);
          }
        }
      }

      visit(title.text);
      expect(hasBold, true);
      final pointer = await tester.startGesture(
        caret(paragraph(tester, 'Before code.'), 0),
        kind: PointerDeviceKind.mouse,
      );
      await pointer.moveTo(caret(paragraph(tester, 'Unselected body.'), 5));
      await pointer.up();
      await tester.pumpAndSettle();
      final right = await tester.startGesture(
        caret(paragraph(tester, 'Before code.'), 5),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await right.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('作筆記'));
      await tester.pumpAndSettle();
      final quote = tester
          .widget<SelectableText>(
            find.byWidgetPredicate(
              (w) =>
                  w is SelectableText &&
                  (w.data?.startsWith('「Before code.') ?? false),
            ),
          )
          .data!;
      expect(quote, contains('# not a heading'));
      expect(quote, endsWith('After code.」'));
      expect(quote, isNot(contains('Next chapter')));
      await tester.enterText(
        find.byKey(const ValueKey('note-body')),
        'Syntax boundaries',
      );
      await tester.pump();
      await tester.tap(find.text('保存筆記'));
      await tester.pumpAndSettle();
      final note = repo.data['revisions'].last['notes'].single;
      final anchor = ParagraphLocation.parse(note['location'] as String)!;
      expect(
        anchor.endHash,
        sha256.convert(utf8.encode('After code.')).toString(),
      );
      expect(find.byType(NoteCloud), findsNWidgets(3));
      await pointer.removePointer();
      await right.removePointer();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  for (final end in [0, 4, 99]) {
    testWidgets(
      'note stops before the next heading and keeps clipboard selection (endpoint $end)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = FakeRepository();
        repo.data['revisions'][0]['content'] =
            '# Guide\n\nFirst paragraph.\n\n## Next chapter\n\nUnselected body.';
        await tester.pumpWidget(
          MaterialApp(
            theme: pageforgeTheme(),
            home: ReaderScreen(repository: repo, id: repo.data['id'] as String),
          ),
        );
        await tester.pumpAndSettle();
        var clipboard = '';
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboard = (call.arguments as Map)['text'] as String;
              }
              if (call.method == 'Clipboard.getData') {
                return {'text': clipboard};
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final pointer = await tester.startGesture(
          caret(paragraph(tester, 'First paragraph.'), 0),
          kind: PointerDeviceKind.mouse,
        );
        await pointer.moveTo(
          end == 99
              ? caret(paragraph(tester, 'Unselected body.'), 5)
              : caret(paragraph(tester, 'Next chapter'), end),
        );
        await pointer.up();
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        final expectedClipboard = end == 0
            ? 'First paragraph.'
            : end == 99
            ? 'First paragraph.\nNext chapter\nUnsel'
            : 'First paragraph.\nNext';
        expect(clipboard, expectedClipboard);
        final right = await tester.startGesture(
          caret(paragraph(tester, 'First paragraph.'), 5),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await right.up();
        await tester.pumpAndSettle();
        await tester.tap(find.text('作筆記'));
        await tester.pumpAndSettle();
        const quote = 'First paragraph.';
        expect(find.text('「$quote」'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('note-body')),
          'Selection boundary check',
        );
        await tester.pump();
        await tester.tap(find.text('保存筆記'));
        await tester.pumpAndSettle();
        final note = repo.data['revisions'].last['notes'].single;
        expect(note['quote'], quote);
        final anchor = ParagraphLocation.parse(note['location'] as String)!;
        const expectedEnd = 'First paragraph.';
        expect(
          anchor.endHash,
          sha256.convert(utf8.encode(expectedEnd)).toString(),
        );
        expect(find.byType(NoteCloud), findsOneWidget);
        final unselected = paragraph(tester, 'Unselected body.');
        for (final cloud in find.byType(NoteCloud).evaluate()) {
          final position = (cloud.renderObject! as RenderBox).localToGlobal(
            Offset.zero,
          );
          expect(
            position.dy,
            lessThan(unselected.localToGlobal(Offset.zero).dy),
          );
        }
        await pointer.removePointer();
        await right.removePointer();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({TargetPlatform.windows}),
    );
  }
}
