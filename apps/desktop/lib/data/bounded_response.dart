import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// One deadline covers headers and the complete body. Cancels the body subscription.
Future<http.Response> boundedResponse(
  http.Client client,
  http.AbortableRequest request,
  Completer<void> abort, {
  required Duration timeout,
  required int maxBytes,
}) async {
  StreamSubscription<List<int>>? subscription;
  final result = Completer<http.Response>();
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  void fail(Object error, [StackTrace? stack]) {
    if (result.isCompleted) return;
    result.completeError(error, stack);
    if (!abort.isCompleted) abort.complete();
    unawaited(subscription?.cancel());
  }

  final timer = Timer(timeout, () => fail(TimeoutException('後端讀取逾時', timeout)));
  unawaited(() async {
    try {
      final response = await client.send(request);
      if (result.isCompleted) {
        await response.stream.listen((_) {}).cancel();
        return;
      }
      if ((response.contentLength ?? 0) > maxBytes) {
        await response.stream.listen((_) {}).cancel();
        fail(StateError('後端回應超過容量'));
        return;
      }
      subscription = response.stream.listen(
        (chunk) {
          if (result.isCompleted) return;
          length += chunk.length;
          if (length > maxBytes) {
            fail(StateError('後端回應超過容量'));
            return;
          }
          bytes.add(chunk);
        },
        onError: fail,
        onDone: () {
          if (!result.isCompleted) {
            result.complete(
              http.Response.bytes(
                bytes.takeBytes(),
                response.statusCode,
                headers: response.headers,
                request: response.request,
              ),
            );
          }
        },
        cancelOnError: true,
      );
    } catch (error, stack) {
      fail(error, stack);
    }
  }());
  try {
    return await result.future;
  } finally {
    timer.cancel();
  }
}
