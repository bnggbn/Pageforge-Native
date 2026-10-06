import 'dart:convert';

class ApiException implements Exception {
  ApiException(this.message, this.status, {this.code});

  factory ApiException.fromResponse(Object? value, int status) {
    final message = value is Map ? value['error'] : null;
    final code = value is Map ? value['code'] : null;
    return ApiException(
      message is String && message.isNotEmpty ? message : '後端請求失敗',
      status,
      code: code is String && code.isNotEmpty ? code : null,
    );
  }

  factory ApiException.decodeResponse(String body, int status) {
    try {
      return ApiException.fromResponse(jsonDecode(body), status);
    } on FormatException {
      return ApiException('後端請求失敗', status);
    }
  }

  final String message;
  final int status;
  // Unknown future codes are preserved; only code-less legacy responses use status fallback.
  final String? code;
  bool get isConflict => code == null ? status == 409 : code == 'CONFLICT';

  @override
  String toString() => message;
}
