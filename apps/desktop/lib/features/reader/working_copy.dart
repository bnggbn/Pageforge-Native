import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/ids.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';

class WorkingCopy extends ChangeNotifier {
  WorkingCopy(this.repository, this.debounce);
  final LibraryRepository repository;
  final Duration debounce;
  late Book _book;
  String _id = newId(), _base = '', _baseline = '';
  String? _version;
  Json _values = {}, _saved = {};
  Future<void> _queue = Future.value();
  Timer? _timer;
  bool _disposed = false;
  String status = 'saved', error = '';
  String get content => _values['content'] as String? ?? '';
  String get body => _values['body'] as String? ?? '';
  String get quote => _values['quote'] as String? ?? '';
  String get location => _values['location'] as String? ?? '全文筆記';
  bool get dirty => content != _book.head.content;

  Future<void> open(Book book) async {
    _book = book;
    final copies = await repository.drafts(book.id);
    final copy = copies.isEmpty ? null : copies.first;
    final base = copy == null
        ? book.head
        : book.revisions.firstWhere((r) => r.id == copy['baseRevisionId']);
    _base = base.id;
    _baseline = base.content;
    _id = copy?['id'] as String? ?? newId();
    _version = copy?['version'] as String?;
    _values = {
      'content': copy?['content'] ?? base.content,
      'body': copy?['body'] ?? '',
      'quote': copy?['quote'] ?? '',
      'location': copy?['location'] ?? '全文筆記',
    };
    _saved = _values;
    _notify();
  }

  void change(Json patch) {
    if (patch.entries.every((e) => _values[e.key] == e.value)) return;
    _values = {..._values, ...patch};
    status = 'pending';
    error = '';
    _notify();
    _timer?.cancel();
    _timer = Timer(debounce, () {
      unawaited(flush().catchError((Object e) {}));
    });
  }

  Future<void> flush() async {
    _timer?.cancel();
    final values = _values;
    final operation = _queue.catchError((Object e) {}).then((_) async {
      if (identical(values, _saved)) return;
      status = 'saving';
      _notify();
      try {
        final clean =
            values['content'] == _baseline &&
            values['body'] == '' &&
            values['quote'] == '' &&
            values['location'] == '全文筆記';
        if (clean) {
          if (_version != null) {
            await repository.removeDraft({
              'id': _id,
              'documentId': _book.id,
              'version': _version,
            });
          }
          _version = null;
        } else {
          final copy = {
            'id': _id,
            'documentId': _book.id,
            'baseRevisionId': _base,
            'version': _version ?? '',
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
            'body': values['body'],
            'quote': values['quote'],
            'location': values['location'],
            if (values['content'] != _baseline) 'content': values['content'],
          };
          Json saved;
          try {
            saved = await repository.saveDraft(copy, _version);
          } on ApiException catch (e) {
            if (e.status != 409) rethrow;
            _id = newId();
            copy['id'] = _id;
            saved = await repository.saveDraft(copy, null);
          }
          _version = saved['version'] as String;
        }
        _saved = values;
        error = '';
        status = identical(values, _values) ? 'saved' : 'pending';
        _notify();
      } catch (e) {
        error = e.toString();
        status = 'error';
        _notify();
        rethrow;
      }
    });
    _queue = operation;
    await operation;
    if (!identical(values, _values)) await flush();
  }

  Future<void> rebase(
    Book book, {
    bool clearContent = false,
    bool clearNote = false,
  }) async {
    await flush();
    final preserve =
        !clearContent && content != _baseline && _baseline != book.head.content;
    _book = book;
    if (!preserve) {
      _base = book.head.id;
      _baseline = book.head.content;
    }
    _values = {
      ..._values,
      if (clearContent) 'content': book.head.content,
      if (clearNote) 'body': '',
      if (clearNote) 'quote': '',
      if (clearNote) 'location': '全文筆記',
    };
    _saved = {};
    _notify();
    await flush();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
