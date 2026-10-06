import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../model/book.dart';
import '../repository/book_repository.dart';

enum BookLoadState { idle, loading, success, empty, networkError, serverError }

class BookViewModel extends ChangeNotifier {
  BookViewModel(this._repository);
  final BookRepository _repository;
  bool _isDisposed = false;
  List<Book> books = const [];
  List<RecentBook> recentBooks = const [];
  Book? selectedBook;
  BookContent? content;
  ReadingProgress? readingProgress;
  List<ReaderChapter> readerChapters = const [];
  List<ReadingNote> readingNotes = const [];
  ReaderSettings readerSettings = const ReaderSettings();
  bool isReaderLoading = false;
  // Serialize PATCHes.  Dropping a tap while an earlier color is saving makes
  // the UI and the persisted default diverge; concurrent PATCHes can also let
  // an older response overwrite a newer choice.
  Future<void> _readerSettingsSaveTail = Future.value();
  String? readerErrorMessage;
  int statsRevision = 0;
  BookLoadState state = BookLoadState.idle;
  String? errorMessage;

  Future<void> loadBooks() async {
    state = BookLoadState.loading;
    errorMessage = null;
    notifyListeners();
    try {
      books = await _repository.books();
      state = books.isEmpty ? BookLoadState.empty : BookLoadState.success;
    } on ApiException catch (e) {
      state = (e.statusCode == null || e.statusCode! >= 500) ? BookLoadState.networkError : BookLoadState.serverError;
      errorMessage = e.message;
    } catch (_) {
      state = BookLoadState.networkError;
      errorMessage = '서버에 연결할 수 없습니다.';
    }
    notifyListeners();
  }

  Future<void> loadBook(int bookId) async {
    state = BookLoadState.loading;
    errorMessage = null;
    notifyListeners();
    try {
      selectedBook = await _repository.book(bookId);
      state = BookLoadState.success;
    } on ApiException catch (e) {
      state = (e.statusCode == null || e.statusCode! >= 500) ? BookLoadState.networkError : BookLoadState.serverError;
      errorMessage = e.message;
    } catch (_) {
      state = BookLoadState.networkError;
      errorMessage = '서버에 연결할 수 없습니다.';
    }
    notifyListeners();
  }

  Future<void> loadRecentBooks() async {
    try {
      recentBooks = await _repository.recentBooks();
      notifyListeners();
    } on ApiException catch (e) {
      errorMessage = e.message;
      notifyListeners();
    }
  }

  Future<void> openBook(int bookId) async {
    await loadBook(bookId);
    try {
      await _repository.recordReading(bookId);
      await loadRecentBooks();
    } on ApiException catch (e) {
      errorMessage = e.message;
      notifyListeners();
    }
  }

  Future<void> loadReader(int bookId) async {
    isReaderLoading = true;
    readerErrorMessage = null;
    notifyListeners();
    try {
      final result = await Future.wait<Object>([
        _repository.content(bookId),
        _repository.readingProgress(bookId), _repository.readerChapters(bookId), _repository.readingNotes(bookId), _repository.readerSettings(),
      ]);
      content = result[0] as BookContent;
      readingProgress = result[1] as ReadingProgress;
      readerChapters = result[2] as List<ReaderChapter>;
      readingNotes = result[3] as List<ReadingNote>;
      readerSettings = result[4] as ReaderSettings;
      await _repository.recordReading(bookId);
      await loadRecentBooks();
    } on ApiException catch (e) {
      content = null;
      readerErrorMessage = e.message;
    } catch (_) {
      content = null;
      readerErrorMessage = '본문을 불러오지 못했습니다.';
    } finally {
      isReaderLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadReadingNotes(int bookId) async {
    final notes = await _repository.readingNotes(bookId);
    if (_isDisposed) return;
    readingNotes = notes;
    notifyListeners();
  }

  /// Login state owns the in-memory cache, not the records on the server.
  /// This prevents one user's notes being briefly rendered for the next user.
  void clearReaderSession() {
    content = null;
    readingProgress = null;
    readerChapters = const [];
    readingNotes = const [];
    readerErrorMessage = null;
    statsRevision++;
    notifyListeners();
  }

  Future<void> addNote(int bookId, ReaderNoteType type, int paragraphOrder, {String? memo, String? selectedText, int? startOffset, int? endOffset, String? color}) async {
    await _repository.addReadingNote(bookId, type: type, paragraphOrder: paragraphOrder, memoContent: memo, selectedText: selectedText, startOffset: startOffset, endOffset: endOffset, highlightColor: color);
    if (_isDisposed) return;
    await loadReadingNotes(bookId);
    if (type == ReaderNoteType.memo) { statsRevision++; notifyListeners(); }
  }
  Future<void> updateNote(int bookId,int noteId,{String? memo,String? color}) async { await _repository.updateReadingNote(bookId,noteId,memoContent:memo,highlightColor:color);await loadReadingNotes(bookId); }
  Future<void> deleteNote(int bookId,int noteId) async { final wasMemo=readingNotes.any((n)=>n.id==noteId&&n.type==ReaderNoteType.memo);await _repository.deleteReadingNote(bookId,noteId);await loadReadingNotes(bookId);if(wasMemo){statsRevision++;notifyListeners();} }
  Future<int> deleteNotes(int bookId, {ReaderNoteType? type}) async { final count=await _repository.deleteReadingNotes(bookId,type:type);await loadReadingNotes(bookId);return count; }
  Future<void> saveSettings(ReaderSettings settings) async {
    final previous = readerSettings;
    readerSettings = settings;
    notifyListeners();
    final operation = _readerSettingsSaveTail.catchError((_) {}).then((_) async {
      try {
        final saved = await _repository.saveReaderSettings(settings);
        // A later tap is already displayed optimistically; do not let an old
        // server response paint over it.
        if (identical(readerSettings, settings)) {
          readerSettings = saved;
          notifyListeners();
        }
      } catch (_) {
        if (identical(readerSettings, settings)) {
          readerSettings = previous;
          notifyListeners();
        }
        rethrow;
      }
    });
    // Keep the queue usable after an error while returning this operation to
    // its caller so the UI can still show a failure message.
    _readerSettingsSaveTail = operation.catchError((_) {});
    await operation;
  }

  Future<void> saveReaderProgress(int bookId, int position, int total) async {
    if (total <= 0) return;
    // Reader positions are paragraph_order values (1..N), not transient page
    // indexes, so progress survives pagination and typography changes.
    final percent = ((position / total) * 100).round().clamp(0, 100).toInt();
    try {
      await _repository.recordReading(bookId, progressPercent: percent, lastReadPosition: position);
      readingProgress = ReadingProgress(bookId: bookId, progressPercent: percent, lastReadPosition: position);
      statsRevision++;
      await loadRecentBooks();
    } on ApiException catch (e) {
      readerErrorMessage = e.message;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
