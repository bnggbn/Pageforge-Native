import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/ids.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';
import 'evidence_topics.dart';

class EvidenceWallViewModel extends ChangeNotifier {
  EvidenceWallViewModel(this.repository, Book book, Json config)
    : _book = book,
      width = (config['canvasWidth'] as num?)?.toDouble() ?? 6400,
      height = (config['canvasHeight'] as num?)?.toDouble() ?? 6400,
      maxTopics = (config['maxTopics'] as int?) ?? 32,
      nameLimit = (config['topicNameCharacters'] as int?) ?? 80,
      maxCards = (config['maxCards'] as int?) ?? 500,
      maxEdges = (config['maxEdges'] as int?) ?? 1000,
      debounce = Duration(
        milliseconds: (config['saveDebounceMs'] as int?) ?? 500,
      );
  final LibraryRepository repository;
  Book _book;
  final double width, height;
  final int maxCards, maxEdges, maxTopics, nameLimit;
  final Duration debounce;
  Json _wall = emptyEvidence();
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
    final source = _active['cards'];
    if (!identical(source, _cardSource)) {
      _cardSource = source;
      _cardCache = (source as List).cast<Json>();
    }
    return _cardCache;
  }

  List<Json> get edges {
    final source = _active['edges'];
    if (!identical(source, _edgeSource)) {
      _edgeSource = source;
      _edgeCache = (source as List).cast<Json>();
    }
    return _edgeCache;
  }

  Json get _active => activeEvidenceTopic(_wall);
  List<Json> get topics => evidenceTopics(_wall);
  String get activeTopicId => _wall['activeTopic'] as String;
  String get activeTopicName => _active['name'] as String;
  bool get isAllTopic => activeTopicId == allEvidenceTopic;
  void _replaceActive(Json update) {
    _wall = replaceEvidenceTopic(_wall, {..._active, ...update});
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
      _wall = normalizeEvidence(loaded);
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
    _wall = reconcileEvidence(_wall, notes, width, height, maxCards);
  }

  void selectTopic(String id) {
    if (!loaded ||
        busy ||
        !topics.any((t) => t['id'] == id) ||
        id == activeTopicId) {
      return;
    }
    _wall = {..._wall, 'activeTopic': id};
    linkSource = null;
    focusNote = null;
    focusRequest++;
    _changed();
  }

  bool _validName(String name) {
    if (name.isEmpty ||
        name.runes.length > nameLimit ||
        topics.any(
          (t) =>
              t['id'] != activeTopicId &&
              (t['name'] as String).toLowerCase() == name.toLowerCase(),
        )) {
      error = '主題名稱不可空白、重複或超過 $nameLimit 字';
      _notify();
      return false;
    }
    return true;
  }

  bool createTopic(String name) {
    name = name.trim();
    if (!loaded || busy) return false;
    if (topics.length >= maxTopics) {
      error = '主題數量已達上限';
      _notify();
      return false;
    }
    if (topics.any(
          (t) => (t['name'] as String).toLowerCase() == name.toLowerCase(),
        ) ||
        !_validName(name)) {
      error = '主題名稱不可空白、重複或超過 $nameLimit 字';
      _notify();
      return false;
    }
    final id = newId();
    _wall = {
      ..._wall,
      'activeTopic': id,
      'topics': <Json>[
        ...topics,
        {'id': id, 'name': name, 'cards': <Json>[], 'edges': <Json>[]},
      ],
    };
    linkSource = null;
    focusNote = null;
    focusRequest++;
    _changed();
    return true;
  }

  bool renameTopic(String name) {
    if (!loaded || busy || isAllTopic || !_validName(name.trim())) return false;
    _replaceActive({'name': name.trim()});
    _changed();
    return true;
  }

  void deleteTopic() {
    if (!loaded || busy || isAllTopic) return;
    _wall = {
      ..._wall,
      'topics': topics.where((t) => t['id'] != activeTopicId).toList(),
      'activeTopic': allEvidenceTopic,
    };
    linkSource = null;
    focusNote = null;
    focusRequest++;
    _changed();
  }

  bool setTopicNotes(Set<String> members) {
    if (!loaded || busy || isAllTopic) return false;
    if (members.length > maxCards ||
        members.any((id) => !notes.containsKey(id))) {
      error = '線索超過容量或來源已移除';
      _notify();
      return false;
    }
    _wall = replaceEvidenceTopic(
      _wall,
      reconcileTopic(_active, members, width, height, maxCards),
    );
    linkSource = null;
    focusNote = null;
    _changed();
    return true;
  }

  void updateBook(Book book) {
    _book = book;
    if (!loaded) return;
    _reconcile();
    _changed();
  }

  void move(String id, double x, double y) {
    if (!loaded || busy) return;
    _replaceActive({
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
    });
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
    _replaceActive({
      'edges': [
        ...edges,
        {'id': newId(), 'from': from, 'to': to, 'label': ''},
      ],
    });
    _changed();
  }

  void editEdge(String id, String label) {
    _replaceActive({
      'edges': [
        for (final edge in edges)
          if (edge['id'] == id) {...edge, 'label': label} else edge,
      ],
    });
    _changed();
  }

  void removeEdge(String id) {
    _replaceActive({'edges': edges.where((edge) => edge['id'] != id).toList()});
    _changed();
  }

  void focus(String noteId) {
    if (!cards.any((c) => c['noteId'] == noteId)) {
      final target = topics
          .where(
            (t) =>
                t['id'] != allEvidenceTopic &&
                (t['cards'] as List).any((c) => c['noteId'] == noteId),
          )
          .firstOrNull;
      selectTopic(target?['id'] as String? ?? allEvidenceTopic);
    }
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
