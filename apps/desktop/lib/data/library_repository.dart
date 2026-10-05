import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, this.status);
  final String message;
  final int status;
  @override
  String toString() => message;
}

abstract class LibraryRepository {
  Future<Json> settings();
  Future<List<BookSummary>> list();
  Future<Book> load(String id);
  Future<String> import(String path);
  Future<void> syncCollection();
  Future<Book> commit(
    Book book,
    String kind,
    String content,
    List<Json> notes, {
    String? restoredFrom,
  });
  Future<List<Json>> drafts(String id);
  Future<Json> saveDraft(Json copy, String? expectedVersion);
  Future<void> removeDraft(Json copy);
  Future<void> saveProgress(String id, Json progress);
  Future<List<Json>> diff(String id, String from, String to);
}

class HttpLibraryRepository implements LibraryRepository {
  HttpLibraryRepository(this.origin, this.token, {http.Client? client})
    : client = client ?? http.Client();
  final Uri origin;
  final String token;
  final http.Client client;

  Future<dynamic> _request(
    String method,
    String path, [
    Object? body,
    Map<String, String>? extra,
  ]) async {
    final request = http.Request(method, origin.resolve('/v1/$path'));
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      ...?extra,
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 30)),
    );
    final value = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(
        value is Map ? '${value['error']}' : '後端請求失敗',
        response.statusCode,
      );
    }
    return value;
  }

  @override
  Future<Json> settings() async =>
      (await _request('GET', 'status') as Json)['config'] as Json;
  @override
  Future<List<BookSummary>> list() async =>
      (await _request('GET', 'books') as List)
          .map((item) => BookSummary(item as Json))
          .toList();
  @override
  Future<Book> load(String id) async =>
      Book(await _request('GET', 'books/$id') as Json);
  @override
  Future<String> import(String path) async {
    final file = File(path);
    final config = await settings();
    if (await file.length() >
        (config['limits']['textMiB'] as int) * 1024 * 1024) {
      throw ApiException('文件超過設定容量。', 413);
    }
    final filename = file.uri.pathSegments.last;
    final result =
        await _request('POST', 'import', {
              'filename': filename,
              'source': base64Encode(await file.readAsBytes()),
            })
            as Json;
    return result['id'] as String;
  }

  @override
  Future<void> syncCollection() async {
    await _request('POST', 'collection/sync');
  }

  @override
  Future<Book> commit(
    Book book,
    String kind,
    String content,
    List<Json> notes, {
    String? restoredFrom,
  }) async => Book(
    await _request('POST', 'books/${book.id}/versions', {
          'expectedHead': book.head.id,
          'kind': kind,
          'content': content,
          'notes': notes,
          'restoredFrom': restoredFrom,
        })
        as Json,
  );
  @override
  Future<List<Json>> drafts(String id) async =>
      (await _request('GET', 'books/$id/drafts') as List).cast<Json>();
  @override
  Future<Json> saveDraft(Json copy, String? expectedVersion) async =>
      await _request('PUT', 'books/${copy['documentId']}/drafts', {
            'copy': copy,
            'expectedVersion': expectedVersion,
          })
          as Json;
  @override
  Future<void> removeDraft(Json copy) async {
    await _request(
      'DELETE',
      'books/${copy['documentId']}/drafts/${copy['id']}',
      null,
      {'X-Draft-Version': copy['version'] as String},
    );
  }

  @override
  Future<void> saveProgress(String id, Json progress) async {
    await _request('PUT', 'books/$id/progress', progress);
  }

  @override
  Future<List<Json>> diff(String id, String from, String to) async =>
      (await _request('POST', 'books/$id/diff', {'from': from, 'to': to})
              as List)
          .cast<Json>();
  void close() => client.close();
}
