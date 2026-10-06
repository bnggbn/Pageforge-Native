import 'package:pageforge/data/library_repository.dart';
import 'package:pageforge/data/models.dart';

class FakeRepository implements LibraryRepository {
  Json data = {
    'id': '10000000-0000-4000-8000-000000000001',
    'title': 'A place for words',
    'format': 'markdown',
    'originalPath': '',
    'sections': <Json>[],
    'sheets': <Json>[],
    'progress': null,
    'revisions': <Json>[
      {
        'id': 'head-1',
        'kind': 'import',
        'content': '# First draft\n\nRoom to think.',
        'createdAt': '2026-10-05T00:00:00Z',
        'notes': <Json>[],
      },
    ],
  };
  Json? savedWall;
  bool failWall = false;
  @override
  Future<Json> loadEvidence(String id) async =>
      savedWall ??
      {
        'schemaVersion': 1,
        'revision': '',
        'updatedAt': '',
        'cards': <Json>[],
        'edges': <Json>[],
      };
  @override
  Future<Json> saveEvidence(
    String id,
    Json wall,
    String expectedRevision,
    String expectedHead,
  ) async {
    if (failWall) throw ApiException('wall conflict', 409);
    savedWall = {...wall, 'revision': 'wall-token'};
    return savedWall!;
  }

  Json? savedDraft;
  bool failDraft = false;
  int saves = 0;
  @override
  Future<Json> settings() async => {
    'reading': {
      'defaultFontSize': 18,
      'draftDebounceMs': 500,
      'progressDebounceMs': 450,
    },
  };
  @override
  Future<List<BookSummary>> list() async => [
    BookSummary({
      'id': data['id'],
      'title': data['title'],
      'filename': 'writing.md',
      'format': 'markdown',
      'revisionCount': (data['revisions'] as List).length,
      'progress': 24,
    }),
  ];
  @override
  Future<Book> load(String id) async => Book(data);
  @override
  Future<Revision> revision(String id, String revisionId) async =>
      Book(data).revisions.firstWhere((r) => r.id == revisionId);
  @override
  Future<String> import(String path) async => data['id'] as String;
  @override
  Future<void> syncCollection() async {}
  @override
  Future<Book> commit(
    Book book,
    String kind,
    String content,
    List<Json> notes, {
    String? restoredFrom,
  }) async {
    final revisions = (data['revisions'] as List).cast<Json>();
    final restore = kind == 'restore'
        ? revisions.firstWhere((r) => r['id'] == restoredFrom)
        : null;
    final value = {
      'id': 'head-${revisions.length + 1}',
      'kind': kind,
      'content':
          restore?['content'] ?? (kind == 'note' ? book.head.content : content),
      'createdAt': '2026-10-05T00:00:00Z',
      'notes': restore?['notes'] ?? notes,
    };
    data = {
      ...data,
      'revisions': [...revisions, value],
    };
    return Book(data);
  }

  @override
  Future<List<Json>> drafts(String id) async =>
      savedDraft == null ? [] : [savedDraft!];
  @override
  Future<Json> saveDraft(Json copy, String? expectedVersion) async {
    if (failDraft) throw ApiException('模擬保存失敗', 500);
    savedDraft = {...copy, 'version': 'token-${++saves}'};
    return savedDraft!;
  }

  @override
  Future<void> removeDraft(Json copy) async {
    savedDraft = null;
  }

  @override
  Future<void> saveProgress(String id, Json progress) async {}
  @override
  Future<List<Json>> diff(String id, String from, String to) async => [
    {'kind': 'insert', 'text': 'New thought'},
  ];
}
