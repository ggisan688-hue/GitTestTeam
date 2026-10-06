import 'package:flutter/foundation.dart';

import '../model/book.dart';
import '../repository/book_repository.dart';

/// The sole in-memory owner of the authenticated user's favorite books.
class FavoriteViewModel extends ChangeNotifier {
  FavoriteViewModel(this._repository);
  final BookRepository _repository;
  List<Book> _favorites = const [];
  bool _loading = false;
  Object? _error;

  List<Book> get favorites => List.unmodifiable(_favorites);
  bool get loading => _loading;
  Object? get error => _error;

  Future<void> load({bool clearFirst = false}) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    if (clearFirst) _favorites = const [];
    notifyListeners();
    try {
      _favorites = await _repository.favoriteBooks();
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setFavorite(int bookId, bool favorite) async {
    if (favorite) {
      await _repository.addFavorite(bookId);
    } else {
      await _repository.removeFavorite(bookId);
    }
    // Server returns the JOINed book representation, avoiding partial cards
    // and ensuring the shared state cannot contain duplicates.
    _favorites = await _repository.favoriteBooks();
    _error = null;
    notifyListeners();
  }

  void clear() {
    _favorites = const [];
    _error = null;
    _loading = false;
    notifyListeners();
  }
}
