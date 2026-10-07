import '../core/api_client.dart';
import '../model/book.dart';
import '../model/ink.dart';
import '../model/memo.dart';
import '../model/progress.dart';
import '../model/reading_stats.dart';

class BookRepository {
  BookRepository(this._api);

  final ApiClient _api;

  Future<List<Book>> books() async {
    final res = await _api.get<List<Book>>(
      '/api/books',
      parse: (json) => (json as List<dynamic>)
          .map((e) => Book.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    return res.data ?? const [];
  }

  Future<Book> book(int bookId) async {
    final res = await _api.get<Book>(
      '/api/books/$bookId',
      parse: (json) => Book.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }

  Future<List<Book>> search(String query, {String? category}) async {
    final response = await _api.get<List<Book>>(
      '/api/books/search',
      query: {
        'query': query,
        if (category?.trim().isNotEmpty == true) 'category': category!.trim(),
      },
      parse: (json) => (json as List<dynamic>)
          .map((item) => Book.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
    return response.data ?? const [];
  }

  Future<BookSearchPage> searchPage(
    String query, {
    String? category,
    int page = 0,
    int size = 20,
  }) async {
    final response = await _api.get<BookSearchPage>(
      '/api/books/search/page',
      query: {
        'query': query,
        'page': '$page',
        'size': '$size',
        if (category?.trim().isNotEmpty == true) 'category': category!.trim(),
      },
      parse: (json) => BookSearchPage.fromJson(json as Map<String, dynamic>),
    );
    return response.data!;
  }

  Future<List<RecentBook>> recentBooks() async {
    final res = await _api.get<List<RecentBook>>(
      '/api/books/recent',
      parse: (json) => (json as List<dynamic>)
          .map((item) => RecentBook.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
    return res.data ?? const [];
  }

  Future<ReadingStats> readingStats({String period = 'week'}) async {
    final r = await _api.get<ReadingStats>(
      '/api/reading-stats',
      query: {'period': period},
      parse: (json) => ReadingStats.fromJson(json as Map<String, dynamic>),
    );
    return r.data!;
  }

  Future<List<Book>> favoriteBooks() async {
    final res = await _api.get<List<Book>>(
      '/api/books/favorites',
      parse: (json) => (json as List<dynamic>)
          .map((item) => Book.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
    return res.data ?? const [];
  }

  Future<bool> favoriteStatus(int bookId) async {
    final res = await _api.get<bool>(
      '/api/books/$bookId/favorite-status',
      parse: (json) => (json as Map<String, dynamic>)['isFavorite'] == true,
    );
    return res.data ?? false;
  }

  Future<void> addFavorite(int bookId) =>
      _api.post('/api/books/$bookId/favorite');
  Future<void> removeFavorite(int bookId) =>
      _api.delete('/api/books/$bookId/favorite');

  Future<void> recordReading(
    int bookId, {
    int? progressPercent,
    int? lastReadPosition,
  }) async {
    await _api.post<Object>(
      '/api/books/$bookId/reading-progress',
      body: {
        if (progressPercent != null) 'progressPercent': progressPercent,
        if (lastReadPosition != null) 'lastReadPosition': lastReadPosition,
      },
    );
  }

  Future<BookContent> content(int bookId) async {
    final res = await _api.get<BookContent>(
      '/api/books/$bookId/content',
      parse: (json) => BookContent.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }

  Future<ReadingProgress> readingProgress(int bookId) async {
    final res = await _api.get<ReadingProgress>(
      '/api/books/$bookId/reading-progress',
      parse: (json) => ReadingProgress.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }

  Future<List<ReaderChapter>> readerChapters(int bookId) async {
    final res = await _api.get<List<ReaderChapter>>(
      '/api/books/$bookId/chapters',
      parse: (json) => (json as List)
          .map((e) => ReaderChapter.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    return res.data ?? const [];
  }

  Future<List<ReadingNote>> readingNotes(
    int bookId, {
    ReaderNoteType? type,
  }) async {
    final res = await _api.get<List<ReadingNote>>(
      '/api/books/$bookId/reading-notes',
      query: type == null ? null : {'type': type.api},
      parse: (json) => (json as List)
          .map((e) => ReadingNote.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    return res.data ?? const [];
  }

  Future<ReadingNote> addReadingNote(
    int bookId, {
    required ReaderNoteType type,
    required int paragraphOrder,
    String? memoContent,
    String? selectedText,
    int? startOffset,
    int? endOffset,
    String? highlightColor,
  }) async {
    final res = await _api.post<ReadingNote>(
      '/api/books/$bookId/reading-notes',
      body: {
        'noteType': type.api,
        'paragraphOrder': paragraphOrder,
        if (memoContent != null) 'memoContent': memoContent,
        if (selectedText != null) 'selectedText': selectedText,
        if (startOffset != null) 'startOffset': startOffset,
        if (endOffset != null) 'endOffset': endOffset,
        if (highlightColor != null) 'highlightColor': highlightColor,
      },
      parse: (json) => ReadingNote.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }

  Future<ReadingNote> updateReadingNote(
    int bookId,
    int noteId, {
    String? memoContent,
    String? highlightColor,
  }) async {
    final res = await _api.patch<ReadingNote>(
      '/api/books/$bookId/reading-notes/$noteId',
      body: {
        if (memoContent != null) 'memoContent': memoContent,
        if (highlightColor != null) 'highlightColor': highlightColor,
      },
      parse: (json) => ReadingNote.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }

  Future<void> deleteReadingNote(int bookId, int noteId) =>
      _api.delete('/api/books/$bookId/reading-notes/$noteId');
  Future<int> deleteReadingNotes(int bookId, {ReaderNoteType? type}) async {
    final result = await _api.delete<Map<String, dynamic>>(
      '/api/books/$bookId/reading-notes',
      query: type == null ? null : {'type': type.api},
      parse: (json) => json as Map<String, dynamic>,
    );
    return (result.data?['deletedCount'] as num?)?.toInt() ?? 0;
  }

  Future<ReaderSettings> readerSettings() async {
    final r = await _api.get<ReaderSettings>(
      '/api/reader-settings',
      parse: (json) => ReaderSettings.fromJson(json as Map<String, dynamic>),
    );
    return r.data!;
  }

  Future<ReaderSettings> saveReaderSettings(ReaderSettings settings) async {
    final r = await _api.patch<ReaderSettings>(
      '/api/reader-settings',
      body: settings.toJson(),
      parse: (json) => ReaderSettings.fromJson(json as Map<String, dynamic>),
    );
    return r.data!;
  }

  Future<Chapter> chapter(int bookId, int chapter) async {
    final res = await _api.get<Chapter>(
      '/api/books/$bookId/chapters/$chapter',
      parse: (json) => Chapter.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }

  Future<List<Memo>> memos(int bookId, {int? chapter}) async {
    final res = await _api.get<List<Memo>>(
      '/api/books/$bookId/memos',
      query: chapter == null ? null : {'chapter': '$chapter'},
      parse: (json) => (json as List<dynamic>)
          .map((e) => Memo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    return res.data ?? const [];
  }

  Future<Memo> addMemo(
    int bookId, {
    required int chapter,
    required int lineNo,
    required String text,
  }) async {
    final res = await _api.post<Memo>(
      '/api/books/$bookId/memos',
      body: {'chapter': chapter, 'lineNo': lineNo, 'text': text},
      parse: (json) => Memo.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }

  /// 나에게 공개한 친구들 + 내 AI 캐릭터의 메모 (내 진행도보다 뒤는 spoiler=true, 내용 비어 있음)
  Future<List<Memo>> friendMemos(int bookId, int chapter) async {
    final res = await _api.get<List<Memo>>(
      '/api/books/$bookId/friend-memos',
      query: {'chapter': '$chapter'},
      parse: (json) => (json as List<dynamic>)
          .map((e) => Memo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    return res.data ?? const [];
  }

  /// 완독 여부 / 리포트
  Future<bool> isComplete(int bookId) async =>
      (await _api.get<bool>(
        '/api/books/$bookId/complete',
        parse: (j) => (j as Map<String, dynamic>)['complete'] == true,
      )).data ??
      false;

  Future<Map<String, dynamic>> report(int bookId, {bool force = false}) async =>
      (await _api.get<Map<String, dynamic>>(
        '/api/books/$bookId/report',
        query: {'force': '$force'},
        parse: (j) => j as Map<String, dynamic>,
      )).data!;

  Future<Memo> addInk(
    int bookId, {
    required int chapter,
    required InkMemo ink,
  }) async {
    final res = await _api.post<Memo>(
      '/api/books/$bookId/memos',
      body: {
        'chapter': chapter,
        'lineNo': ink.strokes.first.lineNo,
        'kind': 'ink',
        'ink': ink.toJson(),
      },
      parse: (json) => Memo.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }

  Future<void> deleteMemo(int bookId, int memoId) =>
      _api.delete('/api/books/$bookId/memos/$memoId');

  // ---------- 읽는 지점 ----------
  Future<Progress> progress(int bookId) async => (await _api.get<Progress>(
    '/api/books/$bookId/progress',
    parse: (j) => Progress.fromJson(j as Map<String, dynamic>),
  )).data!;

  Future<Progress> updateProgress(
    int bookId, {
    required int chapter,
    required int lineNo,
  }) async => (await _api.put<Progress>(
    '/api/books/$bookId/progress',
    body: {'chapter': chapter, 'lineNo': lineNo},
    parse: (j) => Progress.fromJson(j as Map<String, dynamic>),
  )).data!;
}

class BookSearchPage {
  const BookSearchPage({
    required this.items,
    required this.page,
    required this.total,
    required this.hasNext,
  });
  final List<Book> items;
  final int page;
  final int total;
  final bool hasNext;
  factory BookSearchPage.fromJson(Map<String, dynamic> json) => BookSearchPage(
    items: (json['items'] as List<dynamic>? ?? const [])
        .map((e) => Book.fromJson(e as Map<String, dynamic>))
        .toList(),
    page: (json['page'] as num?)?.toInt() ?? 0,
    total: (json['total'] as num?)?.toInt() ?? 0,
    hasNext: json['hasNext'] == true,
  );
}
