import 'package:flutter/foundation.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';

class LibraryViewModel extends ChangeNotifier {
  LibraryViewModel(this.repository);
  final LibraryRepository repository;
  List<BookSummary> books = [];
  bool busy = false;
  String error = '', query = '';
  List<BookSummary> get visible => books
      .where(
        (b) => '${b.title} ${b.filename}'.toLowerCase().contains(
          query.toLowerCase(),
        ),
      )
      .toList();

  Future<void> load() => _act(() async {
    await repository.settings();
    books = await repository.list();
  });
  Future<void> sync() => _act(() async {
    await repository.syncCollection();
    books = await repository.list();
  });
  Future<String?> import(String path) async {
    String? id;
    await _act(() async {
      id = await repository.import(path);
      books = await repository.list();
    });
    return id;
  }

  void search(String value) {
    query = value;
    notifyListeners();
  }

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
}
