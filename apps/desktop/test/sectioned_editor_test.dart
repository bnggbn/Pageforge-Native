import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/features/reader/reader_view_model.dart';
import 'package:pageforge/features/reader/sectioned_draft.dart';
import 'package:pageforge/features/reader/views/editor_view.dart';
import 'package:pageforge/features/reader/working_copy.dart';
import 'package:pageforge/ui/theme.dart';
import 'fake_repository.dart';

class DelayedRepository extends FakeRepository {
  Completer<void>? gate;
  @override
  Future<Map<String, dynamic>> saveDraft(
    Map<String, dynamic> copy,
    String? expectedVersion,
  ) async {
    await gate?.future;
    return super.saveDraft(copy, expectedVersion);
  }
}

void main() {
  test(
    'sections retain every Unicode character and CRLF; local replacements compose in order',
    () {
      final source = '${'🌿文\r\n' * 8000}end';
      final value = SectionedDraft(source, sectionUnits: 1001);
      expect(value.length, greaterThan(20));
      expect(
        [for (var i = 0; i < value.length; i++) value.section(i)].join(),
        source,
      );
      for (var i = 0; i < value.length; i++) {
        final part = value.section(i);
        expect(part.length, lessThanOrEqualTo(1001));
        expect(part.endsWith('\r'), isFalse);
        expect(
          part.codeUnitAt(part.length - 1),
          isNot(inInclusiveRange(0xd800, 0xdbff)),
        );
        expect(part.codeUnitAt(0), isNot(inInclusiveRange(0xdc00, 0xdfff)));
      }
      final first = value.replace(0, '改\r\n${value.section(0)}');
      final second = first.replace(
        value.length - 1,
        '${value.section(value.length - 1)}尾',
      );
      expect(
        second.text,
        '改\r\n$source'
        '尾',
      );
      expect(first.text, '改\r\n$source');
      final reverted = first.replace(0, value.section(0));
      expect(reverted.matches(source), isTrue);
      expect(identical(reverted.text, source), isTrue);
    },
  );

  test(
    'queued saves snapshot immutable section edits and retain failed edits',
    () async {
      final repo = DelayedRepository();
      (repo.data['revisions'] as List).first['content'] = 'A\n\nB\n\nC';
      final working = WorkingCopy(repo, const Duration(days: 1));
      addTearDown(working.dispose);
      await working.open(await repo.load(repo.data['id']));
      var value = working.editSections(3);
      value = value.replace(0, 'first\n\n');
      working.change({'content': value});
      repo.gate = Completer<void>();
      final saving = working.flush();
      await Future<void>.delayed(Duration.zero);
      value = value.replace(value.length - 1, 'last');
      working.change({'content': value});
      repo.gate!.complete();
      await saving;
      expect(repo.savedDraft!['content'], 'first\n\nB\n\nlast');
      expect(working.pending, isFalse);
      repo.failDraft = true;
      working.change({'content': value.replace(0, 'keep\n\n')});
      await expectLater(working.flush(), throwsA(isA<Exception>()));
      expect(working.content, 'keep\n\nB\n\nlast');
      expect(working.pending, isTrue);
    },
  );

  testWidgets(
    'editor navigates bounded sections and saves one intact document',
    (tester) async {
      final repo = FakeRepository();
      tester.view.physicalSize = const Size(360, 750);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = '${'first paragraph.\n\n' * 3000}final paragraph.';
      (repo.data['revisions'] as List).first['content'] = source;
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = call.arguments['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final model = ReaderViewModel(repo, repo.data['id']);
      await model.load();
      addTearDown(model.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: pageforgeTheme(),
          home: Scaffold(body: EditorView(model: model)),
        ),
      );
      var field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text.length, lessThanOrEqualTo(16000));
      await tester.enterText(
        find.byType(TextField),
        'BEGIN\n\n${field.controller!.text}',
      );
      await tester.tap(find.byTooltip('最後一節'));
      await tester.pump();
      field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, endsWith('final paragraph.'));
      await tester.enterText(
        find.byType(TextField),
        '${field.controller!.text}\nEND',
      );
      await tester.tap(find.byTooltip('複製全文'));
      await tester.pump();
      expect(clipboard, 'BEGIN\n\n$source\nEND');
      await model.flush();
      expect(repo.savedDraft!['content'], 'BEGIN\n\n$source\nEND');
      await model.saveEdit();
      expect(model.book!.head.content, 'BEGIN\n\n$source\nEND');
      expect(model.book!.revisionCount, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );
}
