import 'package:flutter/foundation.dart';
import 'design_document.dart';
import 'design_repository.dart';

/// Only saved designs change the live app. The studio owns its own draft.
class DesignController extends ChangeNotifier {
  bool _disposed = false;
  DesignController(this.repository);
  final DesignRepository repository;
  DesignDocument document = DesignDocument.defaults;
  String revision = '';
  String error = '';
  Future<void> load() async {
    try {
      final snapshot = await repository.load();
      document = snapshot.document;
      revision = snapshot.revision;
      error = '';
    } catch (e) {
      error = '外觀設定未載入，先使用預設：$e';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> apply(DesignDocument next) async {
    final snapshot = await repository.save(next, revision);
    document = snapshot.document;
    revision = snapshot.revision;
    error = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
