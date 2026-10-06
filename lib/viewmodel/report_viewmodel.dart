import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../repository/book_repository.dart';

/// 교환독서 리포트
class ReportViewModel extends ChangeNotifier {
  ReportViewModel(this._books);

  final BookRepository _books;

  Map<String, dynamic>? report;
  bool isLoading = false;
  String? errorMessage;

  Future<void> load(int bookId, {bool force = false}) async {
    isLoading = true;
    errorMessage = null;
    if (force) report = null;
    notifyListeners();
    try {
      report = await _books.report(bookId, force: force);
    } on ApiException catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
