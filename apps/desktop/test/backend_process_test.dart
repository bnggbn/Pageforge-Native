import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend_process.dart';

void main() {
  late BackendFixture fixture;
  setUp(() => fixture = BackendFixture());
  tearDown(() => fixture.dispose());
  test(
    'split readiness frame and concurrent close release child once',
    () async {
      final child = FakeBackendProcess();
      final backend = await fixture.start(child);
      expect(backend.origin.toString(), 'http://127.0.0.1:12345');
      await Future.wait([backend.close(), backend.close()]);
      expect(child.inputCloses, 1);
      expect(child.kills, 0);
      expect(child.exited.isCompleted, true);
    },
  );
  test(
    'rejects untrusted endpoints and malformed tokens without echoing frame',
    () async {
      for (final origin in [
        'http://example.com:1234',
        'https://127.0.0.1:1234',
        'http://127.0.0.1',
        'http://127.0.0.1:0',
        'http://user@127.0.0.1:1234',
        'http://127.0.0.1:1234/path',
        'http://127.0.0.1:1234?x=1',
        'http://127.0.0.1:1234#x',
      ]) {
        final child = FakeBackendProcess();
        await expectLater(
          fixture.start(child, announce: () => child.ready(origin: origin)),
          throwsA(
            isA<StateError>().having(
              (e) => e.toString(),
              'message',
              isNot(contains(List.filled(64, '1').join())),
            ),
          ),
        );
        expect(child.inputCloses, 1);
      }
      final child = FakeBackendProcess();
      await expectLater(
        fixture.start(child, announce: () => child.ready(token: 'bad-token')),
        throwsStateError,
      );
      expect(child.inputCloses, 1);
    },
  );
  test('limits readiness frame and diagnostic accumulation', () async {
    final child = FakeBackendProcess();
    await expectLater(
      fixture.start(
        child,
        announce: () {
          child.errors.add(utf8.encode(List.filled(30000, 'x').join()));
          child.output.add(List.filled(4097, 65));
        },
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.toString().length,
          'diagnostic size',
          lessThan(16500),
        ),
      ),
    );
    expect(child.inputCloses, 1);
  });
  test('EOF without readiness newline cleans up child', () async {
    final child = FakeBackendProcess();
    await expectLater(
      fixture.start(
        child,
        announce: () {
          child.output.add(utf8.encode('{}'));
          unawaited(child.output.close());
        },
      ),
      throwsStateError,
    );
    expect(child.inputCloses, 1);
  });
  test('diagnostic pipe errors do not prevent readiness', () async {
    final child = FakeBackendProcess();
    final backend = await fixture.start(
      child,
      announce: () {
        child.errors.addError(StateError('diagnostic pipe closed'));
        child.errors.add([255]);
        child.ready();
      },
    );
    await backend.close();
    expect(child.inputCloses, 1);
  });
  test('startup timeout releases child', () async {
    final child = FakeBackendProcess();
    await expectLater(fixture.start(child, announce: () {}), throwsStateError);
    expect(child.inputCloses, 1);
    expect(child.kills, 0);
  });
  test('shutdown waits for forced exit after grace period', () async {
    final child = FakeBackendProcess(exitOnClose: false);
    final backend = await fixture.start(child);
    var closed = false;
    final closing = backend.close().then((_) => closed = true);
    expect(closed, false);
    await closing;
    expect(child.inputCloses, 1);
    expect(child.kills, 1);
    expect(closed, true);
  });
}
