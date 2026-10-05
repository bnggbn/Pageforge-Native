import 'dart:async';
import 'package:flutter/foundation.dart';
import 'design_controller.dart';
import 'design_document.dart';

enum DesignScene { theme, library, reader }

class StudioViewModel extends ChangeNotifier {
  bool _disposed = false;
  StudioViewModel(this.live)
    : document = live.document,
      source = live.document.source;
  final DesignController live;
  DesignDocument document;
  String source, error = '', message = '';
  DesignScene scene = DesignScene.theme;
  bool busy = false;
  Timer? _timer;
  final _undo = <DesignDocument>[];
  final _redo = <DesignDocument>[];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get dirty => source != live.document.source;
  void select(DesignScene value) {
    scene = value;
    if (!_disposed) notifyListeners();
  }

  void editJson(String text) {
    source = text;
    message = '';
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 200), () => _parse());
  }

  bool _parse() {
    try {
      final next = DesignDocument.parse(source);
      if (next.source != document.source) {
        _remember();
        document = next;
      }
      error = '';
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
    return error.isEmpty;
  }

  void _remember() {
    _undo.add(document);
    if (_undo.length > 50) _undo.removeAt(0);
    _redo.clear();
  }

  void change(String group, String key, Object value) {
    _timer?.cancel();
    try {
      final next = document.change(group, key, value);
      if (next.source != document.source) {
        _remember();
        document = next;
      }
      source = document.source;
      error = message = '';
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  void undo() {
    _timer?.cancel();
    if (!canUndo) return;
    _redo.add(document);
    document = _undo.removeLast();
    source = document.source;
    error = message = '';
    notifyListeners();
  }

  void redo() {
    _timer?.cancel();
    if (!canRedo) return;
    _undo.add(document);
    document = _redo.removeLast();
    source = document.source;
    error = message = '';
    notifyListeners();
  }

  void preset(Map<String, String> colors) {
    _timer?.cancel();
    _remember();
    for (final entry in colors.entries) {
      document = document.change('theme', entry.key, entry.value);
    }
    source = document.source;
    error = message = '';
    notifyListeners();
  }

  void reset() {
    _timer?.cancel();
    _remember();
    document = DesignDocument.defaults;
    source = document.source;
    error = message = '';
    notifyListeners();
  }

  Future<void> reload() async {
    busy = true;
    notifyListeners();
    await live.load();
    if (live.error.isEmpty) {
      document = live.document;
      source = document.source;
      _undo.clear();
      _redo.clear();
      error = '';
      message = '已載入保存的外觀';
    } else {
      error = live.error;
    }
    busy = false;
    notifyListeners();
  }

  Future<bool> apply() async {
    if (busy) return false;
    _timer?.cancel();
    if (!_parse()) return false;
    busy = true;
    message = '';
    notifyListeners();
    try {
      await live.apply(document);
      document = live.document;
      source = document.source;
      message = '已套用並保存，重開仍會使用這個外觀';
      return true;
    } catch (e) {
      error = '$e';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
