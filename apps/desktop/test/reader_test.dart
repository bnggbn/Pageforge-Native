import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/features/reader/reader_view_model.dart';
import 'fake_repository.dart';

void main() {
  test(
    'note drafts reference base; saving notes preserves edited text',
    () async {
      final repo = FakeRepository();
      final reader = ReaderViewModel(repo, repo.data['id'] as String);
      await reader.load();
      reader.working!.change({'body': 'A thought'});
      await reader.flush();
      expect(repo.savedDraft!.containsKey('content'), isFalse);
      reader.working!.change({'content': 'Unsaved rewrite'});
      await reader.addNote();
      expect(reader.book!.head.content, contains('First draft'));
      expect(reader.book!.head.notes.single['body'], 'A thought');
      expect(reader.working!.content, 'Unsaved rewrite');
      reader.dispose();
    },
  );
  test('failed draft blocks navigation and keeps user input', () async {
    final repo = FakeRepository();
    final reader = ReaderViewModel(repo, repo.data['id'] as String);
    await reader.load();
    repo.failDraft = true;
    reader.working!.change({'content': 'Keep this'});
    await reader.changeTab(ReaderTab.history);
    expect(reader.tab, ReaderTab.read);
    expect(reader.error, contains('保存失敗'));
    expect(reader.working!.content, 'Keep this');
    repo.failDraft = false;
    await reader.changeTab(ReaderTab.edit);
    expect(reader.tab, ReaderTab.edit);
    reader.dispose();
  });
  test('reopening restores persisted working text', () async {
    final repo = FakeRepository();
    final first = ReaderViewModel(repo, repo.data['id'] as String);
    await first.load();
    first.working!.change({'content': 'Recovered draft'});
    await first.flush();
    first.dispose();
    final next = ReaderViewModel(repo, repo.data['id'] as String);
    await next.load();
    expect(next.tab, ReaderTab.edit);
    expect(next.working!.content, 'Recovered draft');
    next.dispose();
  });
}
