import 'dart:convert';

class ApiException implements Exception {
  ApiException(this.message, this.status, {this.code, this.diagnostic});

  factory ApiException.fromResponse(Object? value, int status) {
    final message = value is Map ? value['error'] : null;
    final rawCode = value is Map ? value['code'] : null;
    final code = rawCode is String && rawCode.isNotEmpty ? rawCode : null;
    final diagnostic = message is String && message.isNotEmpty ? message : null;
    return ApiException(
      _messages[code] ?? diagnostic ?? '後端請求失敗',
      status,
      code: code,
      diagnostic: diagnostic,
    );
  }

  factory ApiException.decodeResponse(String body, int status) {
    try {
      return ApiException.fromResponse(jsonDecode(body), status);
    } on FormatException {
      return ApiException('後端請求失敗', status);
    }
  }

  // Display text belongs to the client; preserve the backend text for diagnostics.
  static const _messages = {
    'INVALID_REQUEST': '輸入資料無效，請檢查內容與設定。',
    'UNSAFE_PATH': '資料路徑無效或包含不允許的連結。',
    'NOT_FOUND': '找不到要求的資源。',
    'CONFLICT': '資料已被更新，請重新載入；目前輸入仍保留。',
    'LIMIT_EXCEEDED': '內容超過設定容量或結構上限。',
    'UNAUTHORIZED': '請求未通過驗證。',
    'FORBIDDEN': '此請求不被允許。',
    'METHOD_NOT_ALLOWED': '此資源不支援這個請求方式。',
    'STORAGE_MISSING': '書庫依賴檔案缺失，請檢查檔案或備份。',
    'STORAGE_CORRUPT': '書庫內容驗證失敗，請檢查檔案或備份。',
    'STORAGE_IO': '書庫讀寫失敗，請檢查儲存空間與權限。',
    'UNSUPPORTED_STORAGE': '此書庫儲存格式尚不支援，請使用相容版本。',
    'INTERNAL_ERROR': '後端處理失敗。',
  };

  final String message;
  final String? diagnostic;
  final int status;
  // Unknown future codes are preserved; only code-less legacy responses use status fallback.
  final String? code;
  bool get isConflict => code == null ? status == 409 : code == 'CONFLICT';

  @override
  String toString() => message;
}
