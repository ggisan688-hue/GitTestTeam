import '../core/api_client.dart';
import '../model/book.dart';
import '../model/shelf.dart';

class ShelfRepository {
  ShelfRepository(this._api);

  final ApiClient _api;

  Future<List<Shelf>> list() async {
    final response = await _api.get<List<Shelf>>(
      '/api/shelves',
      parse: (json) => (json as List<dynamic>)
          .map((item) => Shelf.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
    return response.data ?? const [];
  }

  Future<ShelfDetail> detail(int shelfId) async {
    final response = await _api.get<ShelfDetail>(
      '/api/shelves/$shelfId',
      parse: (json) => ShelfDetail.fromJson(json as Map<String, dynamic>),
    );
    return response.data!;
  }

  Future<Shelf> create({
    required String name,
    String? description,
    required bool isPublic,
    List<int> bookIds = const [],
  }) => _save(
    '/api/shelves',
    'POST',
    name,
    description,
    isPublic,
    bookIds: bookIds,
  );

  Future<Shelf> update(
    int shelfId, {
    required String name,
    String? description,
    required bool isPublic,
  }) => _save('/api/shelves/$shelfId', 'PATCH', name, description, isPublic);

  Future<Shelf> _save(
    String path,
    String method,
    String name,
    String? description,
    bool isPublic, {
    List<int>? bookIds,
  }) async {
    final body = {
      'name': name.trim(),
      'description': description?.trim().isEmpty == true
          ? null
          : description?.trim(),
      'isPublic': isPublic,
      if (bookIds != null) 'bookIds': bookIds,
    };
    final response = method == 'POST'
        ? await _api.post<Shelf>(
            path,
            body: body,
            parse: (json) => Shelf.fromJson(json as Map<String, dynamic>),
          )
        : await _api.patch<Shelf>(
            path,
            body: body,
            parse: (json) => Shelf.fromJson(json as Map<String, dynamic>),
          );
    return response.data!;
  }

  Future<void> delete(int shelfId) => _api.delete('/api/shelves/$shelfId');

  Future<int> deleteAll() async {
    final response = await _api.delete<int>(
      '/api/shelves',
      parse: (json) =>
          (json as Map<String, dynamic>)['deletedCount'] as int? ?? 0,
    );
    return response.data ?? 0;
  }

  Future<void> addBook(int shelfId, int bookId) =>
      _api.post('/api/shelves/$shelfId/books/$bookId');

  /// Server-side exclusion is authoritative; callers also receive a stable
  /// list suitable for a second, local stale-state filter.
  Future<List<Book>> candidates(int shelfId) async {
    final response = await _api.get<List<Book>>(
      '/api/shelves/$shelfId/book-candidates',
      parse: (json) => (json as List)
          .map((item) => Book.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
    return response.data ?? const [];
  }

  Future<void> removeBook(int shelfId, int bookId) =>
      _api.delete('/api/shelves/$shelfId/books/$bookId');
}
