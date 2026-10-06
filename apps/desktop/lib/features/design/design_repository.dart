import 'dart:convert';
import 'dart:async';
import '../../data/bounded_response.dart';
import 'package:http/http.dart' as http;
import '../../data/library_repository.dart';
import 'design_document.dart';

class DesignSnapshot {
  DesignSnapshot(this.document, this.revision);
  final DesignDocument document;
  final String revision;
}

abstract class DesignRepository {
  Future<DesignSnapshot> load();
  Future<DesignSnapshot> save(DesignDocument document, String expectedRevision);
}

class HttpDesignRepository implements DesignRepository {
  HttpDesignRepository(this.origin, this.token);
  final Uri origin;
  final String token;
  final _client = http.Client();
  Future<DesignSnapshot> _request(String method, [Object? body]) async {
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      method,
      origin.resolve('/v1/design'),
      abortTrigger: abort.future,
    );
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await boundedResponse(
      _client,
      request,
      abort,
      timeout: const Duration(seconds: 10),
      maxBytes: 1024 * 1024,
    );
    if (response.statusCode >= 400) {
      final json = jsonDecode(response.body);
      throw ApiException('${json['error']}', response.statusCode);
    }
    final json = jsonDecode(response.body);
    return DesignSnapshot(
      DesignDocument.parse(jsonEncode(json['document'])),
      json['revision'] as String,
    );
  }

  @override
  Future<DesignSnapshot> load() => _request('GET');
  @override
  Future<DesignSnapshot> save(
    DesignDocument document,
    String expectedRevision,
  ) => _request('PUT', {
    'document': document.toJson(),
    'expectedRevision': expectedRevision,
  });
  void close() => _client.close();
}
