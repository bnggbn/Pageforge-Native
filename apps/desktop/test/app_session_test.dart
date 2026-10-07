import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pageforge/app_session.dart';
import 'package:pageforge/features/design/design_document.dart';
import 'support/fake_backend_process.dart';

class TrackedClient extends MockClient {
  TrackedClient(super.handler);
  int closes = 0;
  @override
  void close() {
    closes++;
    super.close();
  }
}

void main() {
  late BackendFixture fixture;
  setUp(() => fixture = BackendFixture());
  tearDown(() => fixture.dispose());
  for (final fallback in [false, true]) {
    test(
      'session loads settings (fallback=$fallback) and closes all resources once',
      () async {
        final child = FakeBackendProcess();
        final clients = <TrackedClient>[];
        final session = await AppSession.open(
          startBackend: () => fixture.start(child),
          createClient: () {
            final client = TrackedClient(
              (request) async => http.Response(
                jsonEncode({
                  'document': fallback
                      ? {'schemaVersion': 99}
                      : DesignDocument.defaults
                            .change('theme', 'accent', '#335577')
                            .toJson(),
                  'revision': 'saved',
                }),
                200,
              ),
            );
            clients.add(client);
            return client;
          },
        );
        expect(session.design.error.isNotEmpty, fallback);
        if (!fallback) {
          expect(
            session.design.document.get<String>('theme', 'accent'),
            '#335577',
          );
        }
        await Future.wait([session.close(), session.close()]);
        expect(clients.map((c) => c.closes), [1, 1]);
        expect(child.inputCloses, 1);
      },
    );
  }
  test(
    'partial setup failure releases previously acquired client and backend',
    () async {
      final child = FakeBackendProcess();
      final client = TrackedClient((_) async => http.Response('{}', 200));
      var calls = 0;
      await expectLater(
        AppSession.open(
          startBackend: () => fixture.start(child),
          createClient: () {
            if (++calls == 2) throw StateError('client construction failed');
            return client;
          },
        ),
        throwsStateError,
      );
      expect(client.closes, 1);
      expect(child.inputCloses, 1);
    },
  );
}
