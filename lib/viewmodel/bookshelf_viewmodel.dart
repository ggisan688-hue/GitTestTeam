import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../model/book.dart';
import '../repository/book_repository.dart';

/// 내 책장: 책 목록 (로그인/회원별 책장은 아직 없어서 전체 책 = 내 책장)
class BookshelfViewModel extends ChangeNotifier {
  BookshelfViewModel(this._repository);

  final BookRepository _repository;

  List<Book> books = [];
  bool isLoading = false;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      books = await _repository.books();
    } on ApiException catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
