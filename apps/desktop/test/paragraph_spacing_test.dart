import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/features/design/design_document.dart';
import 'package:pageforge/features/reader/views/text_document_view.dart';
import 'package:pageforge/features/reader/reading_position.dart';
import 'package:pageforge/ui/theme.dart';
import 'fake_repository.dart';

void main() {
  test('old design JSON defaults paragraph gap and rejects invalid ranges', () {
    final source = DesignDocument.defaults.toJson();
    source['reader'].remove('paragraphGapLines');
    expect(
      DesignDocument.parse(
        jsonEncode(source),
      ).number('reader', 'paragraphGapLines'),
      1,
    );
    expect(
      () => DesignDocument.defaults.change('reader', 'paragraphGapLines', 4),
      throwsFormatException,
    );
  });
  testWidgets(
    'spacing adds one visual line and preserves exact text across plain paragraphs',
    (tester) async {
      final repo = FakeRepository();
      final book = await repo.load(repo.data['id'] as String);
      final position = ReadingPosition(
        repo,
        book,
        const Duration(milliseconds: 450),
        (_) {},
      );
      const content = 'Alpha paragraph.\n\nBeta paragraph.\n\nGamma paragraph.';
      var clipboard = '', quote = '';
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
      Future<void> render(double gap, {double scale = 1}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: pageforgeTheme(
              DesignDocument.defaults.change(
                'reader',
                'paragraphGapLines',
                gap,
              ),
            ),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: TextDocumentView(
                  content: content,
                  markdown: false,
                  fontSize: 18,
                  position: position,
                  onQuote: (_) {},
                  onCreateNote: (passage) => quote = passage.quote,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await render(0);
      final before = tester.getTopLeft(find.text('Beta paragraph.\n\n')).dy;
      await render(1);
      final after = tester.getTopLeft(find.text('Beta paragraph.\n\n')).dy;
      expect(after - before, closeTo(18 * 1.95, .5));
      final text = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text('Alpha paragraph.\n\n'),
          matching: find.byType(RichText),
        ),
      );
      final start = text.localToGlobal(const Offset(5, 10));
      final click = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await click.up();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(clipboard, content);
      final right = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await right.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('作筆記'));
      await tester.pumpAndSettle();
      expect(quote, content);
      await click.removePointer();
      await right.removePointer();
      await render(0, scale: 2);
      final largeBefore = tester
          .getTopLeft(find.text('Beta paragraph.\n\n'))
          .dy;
      await render(1, scale: 2);
      final largeAfter = tester.getTopLeft(find.text('Beta paragraph.\n\n')).dy;
      expect(largeAfter - largeBefore, closeTo(36 * 1.95, .5));
      await tester.pumpWidget(const SizedBox());
      position.dispose();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );
}
