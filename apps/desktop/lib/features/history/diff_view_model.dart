import 'package:flutter/foundation.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';

class DiffViewModel extends ChangeNotifier {
  DiffViewModel(this.repository, this.book);
  final LibraryRepository repository;
  final Book book;
  List<Json> parts = [];
  bool busy = false, _disposed = false;
  String error = '';
  int _generation = 0;
  Future<void> compare(String from, String to) async {
    final generation = ++_generation;
    busy = true;
    error = '';
    notifyListeners();
    try {
      final result = await repository.diff(book.id, from, to);
      if (!_disposed && generation == _generation) parts = result;
    } catch (e) {
      if (!_disposed && generation == _generation) error = e.toString();
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
