import 'package:flutter/foundation.dart';
import '../../data/ids.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';
import 'working_copy.dart';
import 'reading_position.dart';
import '../evidence/evidence_wall_view_model.dart';
import 'annotations/paragraph_location.dart';

enum ReaderTab { read, notes, edit, history }

class ReaderViewModel extends ChangeNotifier {
  bool _disposed = false;
  void _notify() {
    if (!_disposed) super.notifyListeners();
  }

  ReaderViewModel(this.repository, this.id);
  final LibraryRepository repository;
  final String id;
  Book? book;
  WorkingCopy? working;
  EvidenceWallViewModel? wall;
  Json? noteToReveal;
  int revealRequest = 0;
  ReadingPosition? position;
  String contentEpoch = '';
  Json config = {};
  ReaderTab tab = ReaderTab.read;
  bool busy = false;
  String error = '', message = '';
  int section = 0;
  double fontSize = 18;
  List<double> get fontSizes =>
      ((config['reading']?['fontSizes'] as List?) ?? [14, 16, 18, 20, 24, 28])
          .map((v) => (v as num).toDouble())
          .toList()
        ..sort();
  bool get canIncreaseFont => fontSizes.any((size) => size > fontSize);
  bool get canDecreaseFont => fontSizes.any((size) => size < fontSize);
  void increaseFont() {
    if (canIncreaseFont) {
      resize(fontSizes.firstWhere((size) => size > fontSize));
    }
  }

  void decreaseFont() {
    if (canDecreaseFont) {
      resize(fontSizes.lastWhere((size) => size < fontSize));
    }
  }

  Future<void> load() => _act(() async {
    config = await repository.settings();
    if (_disposed) return;
    final loaded = await repository.load(id);
    if (_disposed) return;
    book = loaded;
    contentEpoch = loaded.head.id;
    position = ReadingPosition(
      repository,
      loaded,
      Duration(milliseconds: config['reading']['progressDebounceMs'] as int),
      (e) {
        error = e.toString();
        _notify();
      },
    );
    fontSize = (config['reading']['defaultFontSize'] as num).toDouble();
    section = (loaded.progress?['section'] as int?) ?? 0;
    working = WorkingCopy(
      repository,
      Duration(milliseconds: config['reading']['draftDebounceMs'] as int),
    );
    await working!.open(loaded);
    if (_disposed) {
      working!.dispose();
      return;
    }
    wall = EvidenceWallViewModel(
      repository,
      loaded,
      (config['evidenceWall'] as Json?) ?? {},
    );
    await wall!.load();
    if (_disposed) return;
    if (working!.dirty) {
      tab = ReaderTab.edit;
    } else if (working!.body.isNotEmpty || working!.quote.isNotEmpty) {
      tab = ReaderTab.read;
    }
  });
  Future<bool> flush() async {
    try {
      await working?.flush();
      await position?.flush();
      await wall?.flush();
      if (error.isNotEmpty) {
        error = '';
        _notify();
      }
      return true;
    } catch (e) {
      error = e.toString();
      _notify();
      return false;
    }
  }

  Future<void> changeTab(ReaderTab value) async {
    if (busy || !await flush()) return;
    tab = value;
    error = '';
    message = '';
    _notify();
  }

  void resize(double value) {
    fontSize = value;
    _notify();
  }

  Future<void> selectSection(int value) => _act(() async {
    await position?.flush();
    section = value;
    position?.changeSection(value);
    await repository.saveProgress(id, {
      'revisionId': book!.head.id,
      'block': 'row-0',
      'ratio': 0,
      'percentage': 0,
      'section': value,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  });
  Future<void> showEvidence(String noteId) async {
    if (busy || !await flush()) return;
    wall?.focus(noteId);
    tab = ReaderTab.notes;
    _notify();
  }

  Future<void> revealNote(Json note) async {
    if (busy || !await flush()) return;
    final anchor = ParagraphLocation.parse(note['location'] as String);
    section = anchor?.section ?? 0;
    position?.changeSection(section);
    noteToReveal = note;
    revealRequest++;
    tab = ReaderTab.read;
    _notify();
  }

  Future<void> saveEdit() =>
      _commit('edit', working!.content, book!.head.notes, clearContent: true);
  Future<void> addNote() async {
    final copy = working!;
    if (copy.body.trim().isEmpty) return;
    final note = {
      'id': newId(),
      'body': copy.body.trim(),
      'quote': copy.quote,
      'location': copy.location,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _commit('note', book!.head.content, [
      ...book!.head.notes,
      note,
    ], clearNote: true);
  }

  Future<void> removeNote(String id) => _commit(
    'note',
    book!.head.content,
    book!.head.notes.where((n) => n['id'] != id).toList(),
  );
  Future<void> restore(Revision revision) => _commit(
    'restore',
    revision.content,
    revision.notes,
    restoredFrom: revision.id,
    clearContent: !working!.dirty,
  );
  Future<void> _commit(
    String kind,
    String content,
    List<Json> notes, {
    String? restoredFrom,
    bool clearContent = false,
    bool clearNote = false,
  }) => _act(() async {
    await working!.flush();
    await position?.flush();
    await wall?.flush();
    final updated = await repository.commit(
      book!,
      kind,
      content,
      notes,
      restoredFrom: restoredFrom,
    );
    final changed = book!.head.content != updated.head.content;
    if (changed) {
      contentEpoch = updated.head.id;
      section = 0;
    }
    position?.rebase(updated, changed);
    book = updated;
    wall?.updateBook(updated);
    // The version already exists even if subsequent draft housekeeping fails.
    message = '已保存第 ${updated.revisions.length} 版。';
    await working!.rebase(
      updated,
      clearContent: clearContent,
      clearNote: clearNote,
    );
    if (kind == 'edit') tab = ReaderTab.read;
  });
  Future<void> _act(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = '';
    _notify();
    try {
      await action();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    wall?.dispose();
    working?.dispose();
    position?.dispose();
    super.dispose();
  }
}
