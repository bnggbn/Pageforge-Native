import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pageforge/data/library_repository.dart';

class StreamClient extends http.BaseClient {
  StreamClient(this.controller, {this.length});
  final StreamController<List<int>> controller;
  final int? length;
  http.BaseRequest? request;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    return http.StreamedResponse(controller.stream, 200, contentLength: length);
  }
}

void main() {
  test('deadline includes stalled body and cancels stream', () async {
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final client = StreamClient(stream);
    final repo = HttpLibraryRepository(
      Uri.parse('http://127.0.0.1:1234'),
      'test',
      client: client,
      timeout: const Duration(milliseconds: 100),
    );
    Object? error;
    final result = repo.list().then<void>(
      (_) {},
      onError: (Object e) {
        error = e;
      },
    );
    await result;
    expect(error, isA<TimeoutException>());
    expect(cancelled, true);
    expect(client.request, isA<http.AbortableRequest>());
    await stream.close();
    repo.close();
  });
  test('chunked body and declared length are bounded', () async {
    for (final length in [null, 100]) {
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final client = StreamClient(stream, length: length);
      final repo = HttpLibraryRepository(
        Uri.parse('http://127.0.0.1:1234'),
        'test',
        client: client,
        maxResponseBytes: 8,
      );
      final result = repo.list();
      final expectation = expectLater(result, throwsA(isA<StateError>()));
      if (length == null) {
        stream.add(utf8.encode('[1,2,3,4,5]'));
      }
      await expectation;
      expect(cancelled, true);
      await stream.close();
      repo.close();
    }
  });
}
