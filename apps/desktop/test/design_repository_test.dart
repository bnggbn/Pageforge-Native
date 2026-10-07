import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pageforge/data/api_exception.dart';
import 'package:pageforge/features/design/design_controller.dart';
import 'package:pageforge/features/design/design_document.dart';
import 'package:pageforge/features/design/design_repository.dart';

http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'repository interprets stored JSON and writes the client-owned schema',
    () async {
      var document = DesignDocument.defaults
          .change('reader', 'lineHeight', 2.2)
          .toJson();
      var revision = 'opaque-file-token-1';
      final repo = HttpDesignRepository(
        Uri.parse('http://127.0.0.1:1234'),
        'test',
        client: MockClient((request) async {
          expect(request.url.path, '/v1/design');
          if (request.method == 'PUT') {
            final body = jsonDecode(request.body);
            expect(body['expectedRevision'], revision);
            document = body['document'];
            revision = 'opaque-file-token-2';
          }
          return response({'document': document, 'revision': revision});
        }),
      );
      addTearDown(repo.close);
      final before = await repo.load();
      expect(before.document.number('reader', 'lineHeight'), 2.2);
      final next = before.document.change('theme', 'accent', '#335577');
      final saved = await repo.save(next, before.revision);
      expect(saved.document.source, next.source);
      expect(saved.revision, revision);
    },
  );

  test(
    'unusable stored UI schema falls back locally without overwriting it',
    () async {
      var saves = 0;
      final stored = {'schemaVersion': 99, 'futureRenderer': true};
      final repo = HttpDesignRepository(
        Uri.parse('http://127.0.0.1:1234'),
        'test',
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return response({
              'document': stored,
              'revision': 'preserved-future-token',
            });
          }
          saves++;
          expect(jsonDecode(request.body)['expectedRevision'], '');
          return response({
            'code': 'CONFLICT',
            'error': 'client settings changed',
          }, 409);
        }),
      );
      addTearDown(repo.close);
      final live = DesignController(repo);
      addTearDown(live.dispose);
      await live.load();
      expect(live.error, isNotEmpty);
      expect(live.document.source, DesignDocument.defaults.source);
      expect(live.revision, '');
      expect(saves, 0);
      await expectLater(
        live.apply(DesignDocument.defaults),
        throwsA(isA<ApiException>()),
      );
      expect(saves, 1);
      expect(live.revision, '');
      expect(stored, {'schemaVersion': 99, 'futureRenderer': true});
    },
  );
}
