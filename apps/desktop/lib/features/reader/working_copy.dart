import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/ids.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';
import 'sectioned_draft.dart';

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
  bool _disposed = false, _discarding = false;
  String status = 'saved', error = '';
  String get content => _text(_values['content']);
  static String _text(Object? value) =>
      value is SectionedDraft ? value.text : value as String? ?? '';
  SectionedDraft editSections(int units) {
    final value = _values['content'];
    return value is SectionedDraft
        ? value
        : SectionedDraft(_text(value), sectionUnits: units);
  }

  String get body => _values['body'] as String? ?? '';
  String get quote => _values['quote'] as String? ?? '';
  String get location => _values['location'] as String? ?? '全文筆記';
  bool get dirty {
    final value = _values['content'];
    return value is SectionedDraft
        ? !value.matches(_book.head.content)
        : value != _book.head.content;
  }

  bool get hasDraft =>
      dirty || body.isNotEmpty || quote.isNotEmpty || location != '全文筆記';
  bool get pending => !identical(_values, _saved);

  Future<void> open(Book book) async {
    _book = book;
    final copies = await repository.drafts(book.id);
    final copy = copies.isEmpty ? null : copies.first;
    final base = copy == null
        ? book.head
        : await repository.revision(book.id, copy['baseRevisionId'] as String);
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
    if (_discarding) return;
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
    if (_discarding) return;
    _timer?.cancel();
    final values = _values;
    final operation = _queue.catchError((Object e) {}).then((_) async {
      if (identical(values, _saved)) return;
      status = 'saving';
      _notify();
      try {
        final text = _text(values['content']);
        final clean =
            text == _baseline &&
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
            if (text != _baseline) 'content': text,
          };
          Json saved;
          try {
            saved = await repository.saveDraft(copy, _version);
          } on ApiException catch (e) {
            if (!e.isConflict) rethrow;
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
    if (!_discarding && !identical(values, _values)) await flush();
  }

  /// Deletes only this working copy using its last CAS token. Committed versions remain.
  Future<void> discard() async {
    _discarding = true;
    _timer?.cancel();
    try {
      await _queue.catchError((Object _) {});
      if (_version != null) {
        await repository.removeDraft({
          'id': _id,
          'documentId': _book.id,
          'version': _version,
        });
      }
      _version = null;
      _base = _book.head.id;
      _baseline = _book.head.content;
      _values = {
        'content': _baseline,
        'body': '',
        'quote': '',
        'location': '全文筆記',
      };
      _saved = _values;
      status = 'saved';
      error = '';
      _notify();
    } finally {
      _discarding = false;
    }
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
