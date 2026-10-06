import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pageforge/data/library_repository.dart';
import 'package:pageforge/data/models.dart';
import 'package:pageforge/features/design/design_repository.dart';
import 'package:pageforge/features/reader/working_copy.dart';

import 'fake_repository.dart';

class ConflictRepository extends FakeRepository {
  ConflictRepository(this.code);
  final String? code;
  int attempts = 0;

  @override
  Future<Json> saveDraft(Json copy, String? expectedVersion) async {
    if (++attempts == 1) {
      throw ApiException('訊息可以更換', 409, code: code);
    }
    return super.saveDraft(copy, expectedVersion);
  }
}

http.Response jsonResponse(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'both repositories carry codes and tolerate legacy or malformed bodies',
    () async {
      final origin = Uri.parse('http://127.0.0.1:1234');
      final responses = [
        jsonResponse({'code': 'STORAGE_CORRUPT', 'error': '驗證失敗'}, 500),
        jsonResponse({'code': 'FUTURE_ERROR', 'error': '稍後新增'}, 409),
        jsonResponse({'error': '舊後端'}, 409),
        http.Response('<html>server error</html>', 500),
        jsonResponse({'code': 9, 'error': null}, 400),
      ];
      final codes = ['STORAGE_CORRUPT', 'FUTURE_ERROR', null, null, null];
      final messages = ['驗證失敗', '稍後新增', '舊後端', '後端請求失敗', '後端請求失敗'];
      for (var i = 0; i < responses.length; i++) {
        final library = HttpLibraryRepository(
          origin,
          'test',
          client: MockClient((_) async => responses[i]),
        );
        final design = HttpDesignRepository(
          origin,
          'test',
          client: MockClient((_) async => responses[i]),
        );
        for (final request in [() => library.list(), () => design.load()]) {
          await expectLater(
            request(),
            throwsA(
              isA<ApiException>()
                  .having((e) => e.code, 'code', codes[i])
                  .having((e) => e.status, 'status', responses[i].statusCode)
                  .having((e) => e.message, 'message', messages[i]),
            ),
          );
        }
        library.close();
        design.close();
      }
    },
  );

  test(
    'coded and legacy draft conflicts preserve input in a new copy',
    () async {
      for (final code in ['CONFLICT', null]) {
        final repository = ConflictRepository(code);
        final copy = WorkingCopy(repository, const Duration(seconds: 30));
        addTearDown(copy.dispose);
        await copy.open(await repository.load('book'));
        copy.change({'body': '保留心流與輸入'});
        await copy.flush();
        expect(repository.attempts, 2);
        expect(repository.savedDraft?['body'], '保留心流與輸入');
        expect(copy.pending, false);
      }
    },
  );

  test(
    'an unknown coded 409 does not silently create a conflict copy',
    () async {
      final repository = ConflictRepository('FUTURE_ERROR');
      final copy = WorkingCopy(repository, const Duration(seconds: 30));
      addTearDown(copy.dispose);
      await copy.open(await repository.load('book'));
      copy.change({'body': '仍保留未保存輸入'});
      await expectLater(
        copy.flush(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'FUTURE_ERROR'),
        ),
      );
      expect(repository.attempts, 1);
      expect(copy.body, '仍保留未保存輸入');
      expect(copy.pending, true);
      expect(repository.savedDraft, null);
    },
  );
}
