import 'dart:convert';
import 'dart:async';
import '../../data/bounded_response.dart';
import 'package:http/http.dart' as http;
import '../../data/api_exception.dart';
import 'design_document.dart';

class DesignSnapshot {
  const DesignSnapshot(this.document, this.revision);
  final DesignDocument document;
  final String revision;
}

abstract class DesignRepository {
  Future<DesignSnapshot> load();
  Future<DesignSnapshot> save(DesignDocument document, String expectedRevision);
}

/// The transport returns opaque settings; this adapter validates the UI schema.
class HttpDesignRepository implements DesignRepository {
  HttpDesignRepository(this.origin, this.token, {http.Client? client})
    : _client = client ?? http.Client();
  final Uri origin;
  final String token;
  final http.Client _client;
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
      throw ApiException.decodeResponse(response.body, response.statusCode);
    }
    final json = jsonDecode(response.body);
    return DesignSnapshot(
      DesignDocument.fromJson(json['document']),
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
