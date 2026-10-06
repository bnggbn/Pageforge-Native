import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/platform/close_boundary.dart';
import 'package:pageforge/features/reader/reader_view_model.dart';
import 'fake_repository.dart';

Future<bool> requestClose(WidgetTester tester) async {
  final response = Completer<bool>();
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'pageforge/window',
    const StandardMethodCodec().encodeMethodCall(
      const MethodCall('requestClose'),
    ),
    (data) => response.complete(
      const StandardMethodCodec().decodeEnvelope(data!) as bool,
    ),
  );
  return response.future;
}

void main() {
  testWidgets(
    'cancel, failed save, retry preserve last keystroke and shutdown order',
    (tester) async {
      final repo = FakeRepository();
      final reader = ReaderViewModel(repo, repo.data['id'] as String);
      await reader.load();
      var shutdown = 0;
      await tester.pumpWidget(
        CloseBoundary(
          beforeClose: () async {
            expect(repo.savedDraft!['content'], 'last keystroke');
            shutdown++;
          },
          builder: (_, key) => MaterialApp(
            navigatorKey: key,
            home: CloseParticipant(
              task: CloseTask(
                dirty: () => reader.hasUnsavedChanges,
                busy: () => reader.busy,
                save: reader.flush,
                discard: reader.discardDraftForClose,
                description: '保留草稿',
                error: () => reader.error,
              ),
              child: const Scaffold(body: Text('reader')),
            ),
          ),
        ),
      );
      reader.working!.change({
        'content': 'last keystroke',
        'body': 'last note',
      });
      final cancel = requestClose(tester);
      await tester.pumpAndSettle();
      expect(find.text('還有尚未保存的內容'), findsOneWidget);
      final duplicate = requestClose(tester);
      expect(await duplicate, false);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await cancel, false);
      expect(shutdown, 0);
      reader.working!.change({'content': 'last keystroke!'});
      repo.failDraft = true;
      final retry = requestClose(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存並關閉'));
      await tester.pumpAndSettle();
      expect(find.textContaining('視窗已保留'), findsOneWidget);
      expect(shutdown, 0);
      reader.working!.change({'content': 'last keystroke'});
      repo.failDraft = false;
      await tester.tap(find.text('保存並關閉'));
      await tester.pumpAndSettle();
      expect(await retry, true);
      expect(shutdown, 1);
      expect(repo.savedDraft!['body'], 'last note');
      reader.dispose();
      final reopened = ReaderViewModel(repo, repo.data['id'] as String);
      await reopened.load();
      expect(reopened.working!.content, 'last keystroke');
      expect(reopened.book!.head.content, contains('First draft'));
      reopened.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'discard deletes current draft, preserves versions; busy refuses closing',
    () async {
      final repo = FakeRepository();
      final reader = ReaderViewModel(repo, repo.data['id'] as String);
      await reader.load();
      final original = reader.book!.head.id;
      reader.working!.change({'content': 'temporary'});
      await reader.flush();
      expect(repo.savedDraft, isNotNull);
      final controller = CloseController()
        ..tasks.add(
          CloseTask(
            dirty: () => reader.hasUnsavedChanges,
            busy: () => reader.busy,
            save: reader.flush,
            discard: reader.discardDraftForClose,
            description: 'draft',
            error: () => reader.error,
          ),
        );
      reader.busy = true;
      expect(await controller.prepare(discard: true), false);
      expect(repo.savedDraft, isNotNull);
      reader.busy = false;
      expect(await controller.prepare(discard: true), true);
      expect(repo.savedDraft, isNull);
      expect(reader.book!.head.id, original);
      expect(reader.working!.content, reader.book!.head.content);
      reader.dispose();
    },
  );
}
