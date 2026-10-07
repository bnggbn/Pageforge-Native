import 'package:flutter/foundation.dart';
import 'design_document.dart';
import 'design_repository.dart';

/// Only a saved snapshot changes the live app. The studio owns its own draft.
class DesignController extends ChangeNotifier {
  DesignController(this.repository);
  final DesignRepository repository;
  bool _disposed = false;
  DesignSnapshot _saved = DesignSnapshot(DesignDocument.defaults, '');
  DesignDocument get document => _saved.document;
  String get revision => _saved.revision;
  String error = '';

  Future<void> load() async {
    if (_disposed) return;
    try {
      final saved = await repository.load();
      if (_disposed) return;
      _saved = saved;
      error = '';
    } catch (e) {
      if (_disposed) return;
      error = '外觀設定未載入，保留目前外觀：$e';
    }
    notifyListeners();
  }

  Future<void> apply(DesignDocument next) async {
    if (_disposed) return;
    final saved = await repository.save(next, revision);
    if (_disposed) return;
    _saved = saved;
    error = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
