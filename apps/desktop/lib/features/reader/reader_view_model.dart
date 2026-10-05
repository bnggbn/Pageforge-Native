import 'package:flutter/foundation.dart';
import '../../data/ids.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';
import 'working_copy.dart';
import 'reading_position.dart';

enum ReaderTab { read, notes, edit, history }

class ReaderViewModel extends ChangeNotifier {
  ReaderViewModel(this.repository, this.id);
  final LibraryRepository repository;
  final String id;
  Book? book;
  WorkingCopy? working;
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
    final loaded = await repository.load(id);
    book = loaded;
    contentEpoch = loaded.head.id;
    position = ReadingPosition(
      repository,
      loaded,
      Duration(milliseconds: config['reading']['progressDebounceMs'] as int),
      (e) {
        error = e.toString();
        notifyListeners();
      },
    );
    fontSize = (config['reading']['defaultFontSize'] as num).toDouble();
    section = (loaded.progress?['section'] as int?) ?? 0;
    working = WorkingCopy(
      repository,
      Duration(milliseconds: config['reading']['draftDebounceMs'] as int),
    );
    await working!.open(loaded);
    if (working!.dirty) {
      tab = ReaderTab.edit;
    } else if (working!.body.isNotEmpty || working!.quote.isNotEmpty) {
      tab = ReaderTab.notes;
    }
  });
  Future<bool> flush() async {
    try {
      await working?.flush();
      await position?.flush();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> changeTab(ReaderTab value) async {
    if (busy || !await flush()) return;
    tab = value;
    error = '';
    message = '';
    notifyListeners();
  }

  void resize(double value) {
    fontSize = value;
    notifyListeners();
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
    notifyListeners();
    try {
      await action();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    working?.dispose();
    position?.dispose();
    super.dispose();
  }
}
