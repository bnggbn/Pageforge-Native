import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/ids.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';

class EvidenceWallViewModel extends ChangeNotifier {
  EvidenceWallViewModel(this.repository, Book book, Json config)
    : _book = book,
      width = (config['canvasWidth'] as num?)?.toDouble() ?? 6400,
      height = (config['canvasHeight'] as num?)?.toDouble() ?? 6400,
      maxCards = (config['maxCards'] as int?) ?? 500,
      maxEdges = (config['maxEdges'] as int?) ?? 1000,
      debounce = Duration(
        milliseconds: (config['saveDebounceMs'] as int?) ?? 500,
      );
  final LibraryRepository repository;
  Book _book;
  final double width, height;
  final int maxCards, maxEdges;
  final Duration debounce;
  Json _wall = {
    'schemaVersion': 1,
    'revision': '',
    'updatedAt': '',
    'cards': <Json>[],
    'edges': <Json>[],
  };
  Json? _saved;
  String _revision = '';
  bool loaded = false, busy = false, _disposed = false;
  String error = '', status = 'saved';
  String? linkSource, focusNote;
  int focusRequest = 0;
  Timer? _timer;
  Future<void> _queue = Future.value();
  Map<String, Json> notes = {};
  Object? _cardSource, _edgeSource;
  List<Json> _cardCache = [], _edgeCache = [];
  List<Json> get cards {
    final source = _wall['cards'];
    if (!identical(source, _cardSource)) {
      _cardSource = source;
      _cardCache = (source as List).cast<Json>();
    }
    return _cardCache;
  }

  List<Json> get edges {
    final source = _wall['edges'];
    if (!identical(source, _edgeSource)) {
      _edgeSource = source;
      _edgeCache = (source as List).cast<Json>();
    }
    return _edgeCache;
  }

  bool get dirty => loaded && !identical(_wall, _saved);
  int get unplaced => notes.length - cards.length;
  Json? card(String id) {
    for (final card in cards) {
      if (card['noteId'] == id) return card;
    }
    return null;
  }

  Future<void> load() async {
    busy = true;
    _notify();
    try {
      final loaded = await repository.loadEvidence(_book.id);
      _revision = loaded['revision'] as String;
      _wall = loaded;
      _reconcile();
      _saved = _wall;
      this.loaded = true;
      error = '';
      status = 'saved';
    } catch (e) {
      error = '$e';
      status = 'error';
    } finally {
      busy = false;
      _notify();
    }
  }

  void _reconcile() {
    notes = {for (final note in _book.head.notes) note['id'] as String: note};
    final kept = cards
        .where((card) => notes.containsKey(card['noteId']))
        .take(maxCards)
        .toList();
    final seen = kept.map((card) => card['noteId']).toSet();
    final columns = ((width - 80) / 320).floor();
    for (final id in notes.keys) {
      if (kept.length >= maxCards) break;
      if (seen.add(id)) {
        final n = kept.length;
        kept.add({
          'noteId': id,
          'x': 40.0 + (n % columns) * 320,
          'y': (40.0 + (n ~/ columns) * 280).clamp(0.0, height - 240),
        });
      }
    }
    _wall = {
      ..._wall,
      'cards': kept,
      'edges': edges
          .where(
            (edge) => seen.contains(edge['from']) && seen.contains(edge['to']),
          )
          .toList(),
    };
  }

  void updateBook(Book book) {
    _book = book;
    if (!loaded) return;
    _reconcile();
    _changed();
  }

  void move(String id, double x, double y) {
    if (!loaded || busy) return;
    _wall = {
      ..._wall,
      'cards': [
        for (final item in cards)
          if (item['noteId'] == id)
            {
              ...item,
              'x': x.clamp(0.0, width - 280),
              'y': y.clamp(0.0, height - 240),
            }
          else
            item,
      ],
    };
    _changed();
  }

  void beginLink(String id) {
    linkSource = id;
    _notify();
  }

  void cancelLink() {
    linkSource = null;
    _notify();
  }

  void connect(String to) {
    final from = linkSource;
    linkSource = null;
    if (from == null || from == to) {
      _notify();
      return;
    }
    if (edges.length >= maxEdges) {
      error = '紅線數量已達上限';
      _notify();
      return;
    }
    if (edges.any(
      (edge) =>
          (edge['from'] == from && edge['to'] == to) ||
          (edge['from'] == to && edge['to'] == from),
    )) {
      _notify();
      return;
    }
    _wall = {
      ..._wall,
      'edges': [
        ...edges,
        {'id': newId(), 'from': from, 'to': to, 'label': ''},
      ],
    };
    _changed();
  }

  void editEdge(String id, String label) {
    _wall = {
      ..._wall,
      'edges': [
        for (final edge in edges)
          if (edge['id'] == id) {...edge, 'label': label} else edge,
      ],
    };
    _changed();
  }

  void removeEdge(String id) {
    _wall = {
      ..._wall,
      'edges': edges.where((edge) => edge['id'] != id).toList(),
    };
    _changed();
  }

  void focus(String noteId) {
    focusNote = noteId;
    focusRequest++;
    _notify();
  }

  void _changed() {
    error = '';
    status = 'pending';
    _notify();
    _timer?.cancel();
    _timer = Timer(
      debounce,
      () => unawaited(flush().catchError((Object e) {})),
    );
  }

  Future<void> flush() async {
    _timer?.cancel();
    if (!loaded) return;
    final wall = _wall, head = _book.head.id;
    final operation = _queue.catchError((Object e) {}).then((_) async {
      if (identical(wall, _saved)) return;
      status = 'saving';
      _notify();
      try {
        final saved = await repository.saveEvidence(
          _book.id,
          wall,
          _revision,
          head,
        );
        _revision = saved['revision'] as String;
        _saved = wall;
        error = '';
        status = identical(wall, _wall) ? 'saved' : 'pending';
        _notify();
      } catch (e) {
        error = '$e';
        status = 'error';
        _notify();
        rethrow;
      }
    });
    _queue = operation;
    await operation;
    if (!identical(wall, _wall)) await flush();
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
