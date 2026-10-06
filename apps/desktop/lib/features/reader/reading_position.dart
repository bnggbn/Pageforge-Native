import 'dart:async';
import '../../data/library_repository.dart';
import '../../data/models.dart';

class ReadingPosition {
  ReadingPosition(this.repository, Book book, this.debounce, this.onError)
    : _book = book,
      section = (book.progress?['section'] as int?) ?? 0,
      ratio = book.progress?['block'] == 'native-scroll'
          ? (book.progress?['ratio'] as num?)?.toDouble() ?? 0
          : ((book.progress?['percentage'] as num?)?.toDouble() ?? 0) / 100;
  final LibraryRepository repository;
  final Duration debounce;
  final void Function(Object) onError;
  Book _book;
  int section;
  double ratio;
  Json? _pending;
  Timer? _timer;
  Future<void> _queue = Future.value();
  bool get pending => _pending != null;
  void remember(double offset, double extent) {
    ratio = extent <= 0 ? 0 : (offset / extent).clamp(0, 1);
    final count = _book.format == 'epub'
        ? _book.sections.length
        : _book.format == 'xlsx'
        ? _book.sheets.length
        : 1;
    _pending = {
      'revisionId': _book.head.id,
      'block': 'native-scroll',
      'ratio': ratio,
      'percentage': ((section + ratio) / (count < 1 ? 1 : count) * 100).clamp(
        0,
        100,
      ),
      'section': section,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    _timer?.cancel();
    _timer = Timer(debounce, () {
      flush().catchError((Object e) {
        onError(e);
      });
    });
  }

  Future<void> flush() async {
    _timer?.cancel();
    final pending = _pending;
    if (pending == null) {
      await _queue;
      return;
    }
    final operation = _queue.catchError((Object e) {}).then((_) async {
      await repository.saveProgress(_book.id, pending);
      if (identical(pending, _pending)) _pending = null;
    });
    _queue = operation;
    await operation;
  }

  void rebase(Book book, bool textChanged) {
    _book = book;
    if (textChanged) {
      ratio = 0;
      section = 0;
      _pending = null;
      _timer?.cancel();
    }
  }

  void changeSection(int value) {
    section = value;
    ratio = 0;
  }

  void dispose() => _timer?.cancel();
}
