import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pageforge/data/library_repository.dart';
import 'package:pageforge/data/models.dart';
import 'package:pageforge/features/reader/reader_view_model.dart';
import 'fake_repository.dart';

void main() {
  test(
    'compact HTTP book retains count and metadata; old draft fetches only its base',
    () async {
      final fake = FakeRepository();
      final original = (fake.data['revisions'] as List).first as Json;
      final current = {
        ...original,
        'id': 'head-2',
        'kind': 'edit',
        'content': 'new',
      };
      final requests = <String>[];
      final repo = HttpLibraryRepository(
        Uri.parse('http://127.0.0.1:1234'),
        'test',
        client: MockClient((r) async {
          requests.add(r.url.path + (r.url.hasQuery ? '?${r.url.query}' : ''));
          final Object value;
          if (r.url.path.endsWith('/status')) {
            value = {'config': await fake.settings()};
          } else if (r.url.path.endsWith('/drafts')) {
            value = [
              {
                'id': 'draft',
                'baseRevisionId': 'head-1',
                'version': 'token',
                'body': 'old thought',
                'quote': '',
                'location': '全文筆記',
              },
            ];
          } else if (r.url.path.endsWith('/versions/head-1')) {
            value = original;
          } else if (r.url.path.endsWith('/evidence-wall')) {
            value = await fake.loadEvidence('book');
          } else {
            value = {
              ...fake.data,
              'revisions': [current],
              'revisionCount': 2,
              'history': [
                for (final revision in [original, current])
                  {
                    'id': revision['id'],
                    'kind': revision['kind'],
                    'createdAt': revision['createdAt'],
                  },
              ],
            };
          }
          return http.Response(
            jsonEncode(value),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final reader = ReaderViewModel(repo, fake.data['id'] as String);
      await reader.load();
      expect(reader.error, isEmpty);
      expect(reader.book!.revisionCount, 2);
      expect(reader.book!.revisions.length, 1);
      expect(reader.book!.history.length, 2);
      expect(reader.book!.history.first, isNot(isA<Revision>()));
      expect(reader.working!.content, original['content']);
      expect(reader.working!.body, 'old thought');
      expect(requests.where((p) => p.contains('?view=reader')), hasLength(1));
      expect(
        requests.where((p) => p.contains('/versions/head-1')),
        hasLength(1),
      );
      reader.dispose();
      repo.close();
    },
  );
  test(
    'restore from metadata creates new version and preserves uncommitted working text',
    () async {
      final repo = FakeRepository();
      final reader = ReaderViewModel(repo, repo.data['id'] as String);
      await reader.load();
      final old = reader.book!.history.first;
      final original = reader.book!.head.content;
      reader.working!.change({'content': 'published rewrite'});
      await reader.saveEdit();
      reader.working!.change({'content': 'uncommitted rewrite'});
      await reader.restore(old);
      expect(reader.error, isEmpty);
      expect(reader.book!.revisionCount, 3);
      expect(reader.book!.head.content, original);
      expect(reader.working!.content, 'uncommitted rewrite');
      reader.dispose();
    },
  );
}
