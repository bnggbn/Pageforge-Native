import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/features/reader/reading_position.dart';
import 'package:pageforge/features/reader/views/text_document_view.dart';
import 'package:pageforge/ui/theme.dart';
import 'fake_repository.dart';

RenderParagraph paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == text,
      ),
    );

Offset caret(RenderParagraph paragraph, int offset) {
  final local = paragraph.getOffsetForCaret(
    TextPosition(offset: offset),
    Rect.zero,
  );
  return paragraph.localToGlobal(
    local + Offset(0, paragraph.preferredLineHeight / 2),
  );
}

Future<void> shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  String clipboard = '';
  setUp(() {
    clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          } else if (call.method == 'Clipboard.getData') {
            return {'text': clipboard};
          } else if (call.method == 'Clipboard.hasStrings') {
            return {'value': clipboard.isNotEmpty};
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<ReadingPosition> showDocument(
    WidgetTester tester,
    String content,
    ValueChanged<String> onQuote, {
    bool markdown = true,
  }) async {
    final repository = FakeRepository();
    final position = ReadingPosition(
      repository,
      await repository.load(repository.data['id'] as String),
      const Duration(milliseconds: 450),
      (error) => fail(error.toString()),
    );
    addTearDown(position.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pageforgeTheme(),
        home: Scaffold(
          body: TextDocumentView(
            content: content,
            markdown: markdown,
            fontSize: 18,
            position: position,
            onQuote: onQuote,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return position;
  }

  testWidgets(
    'drag across Markdown paragraphs copies only the selected range',
    (tester) async {
      var quote = '';
      await showDocument(
        tester,
        '# Document title\n\nAlpha **bold** text.\n\nBeta middle.\n\nGamma ending.',
        (value) => quote = value,
      );
      final gesture = await tester.startGesture(
        caret(paragraph(tester, 'Alpha bold text.'), 6),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(caret(paragraph(tester, 'Gamma ending.'), 5));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(quote, 'bold text.\nBeta middle.\nGamma');
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(clipboard, quote);
      expect(clipboard, isNot(contains('Document title')));
      await gesture.removePointer();
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'select all includes heading and paragraphs below the viewport',
    (tester) async {
      final lines = List.generate(
        40,
        (i) => 'Paragraph $i with room to think.',
      );
      final content = '# Document title\n\n${lines.join('\n\n')}';
      var quote = '';
      final position = await showDocument(
        tester,
        content,
        (value) => quote = value,
      );
      final scroll = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(800));
      final gesture = await tester.startGesture(
        caret(paragraph(tester, 'Document title'), 0),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await tester.pump();
      await shortcut(tester, LogicalKeyboardKey.keyA);
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(clipboard, 'Document title\n${lines.join('\n')}');
      expect(quote, clipboard);
      clipboard = "not copied";
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(clipboard, quote);
      expect(position.ratio, closeTo(1, .001));
      await gesture.removePointer();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'drag across spaced plain paragraphs preserves the selected separators',
    (tester) async {
      var quote = '';
      await showDocument(
        tester,
        'First line\n\nSecond paragraph\nThird line',
        (value) => quote = value,
        markdown: false,
      );
      final gesture = await tester.startGesture(
        caret(paragraph(tester, 'First line\n\n'), 6),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        caret(paragraph(tester, 'Second paragraph\nThird line'), 21),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(quote, 'line\n\nSecond paragraph\nThir');
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(clipboard, quote);
      await gesture.removePointer();
      final reverse = await tester.startGesture(
        caret(paragraph(tester, 'Second paragraph\nThird line'), 21),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await reverse.moveTo(caret(paragraph(tester, 'First line\n\n'), 6));
      await reverse.up();
      await tester.pumpAndSettle();
      expect(quote, 'line\n\nSecond paragraph\nThir');
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(clipboard, quote);
      await reverse.removePointer();
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'plain text retains existing line breaks during selection',
    (tester) async {
      var quote = '';
      const content = 'First line\n\nSecond paragraph\nThird line';
      await showDocument(
        tester,
        content,
        (value) => quote = value,
        markdown: false,
      );
      final gesture = await tester.startGesture(
        caret(paragraph(tester, 'First line\n\n'), 0),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await tester.pump();
      await shortcut(tester, LogicalKeyboardKey.keyA);
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(quote, content);
      expect(clipboard, content);
      await gesture.removePointer();
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );
}
