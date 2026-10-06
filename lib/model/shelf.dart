import 'book.dart';

class Shelf {
  const Shelf({
    required this.id,
    required this.name,
    this.description,
    required this.isPublic,
    required this.bookCount,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String? description;
  final bool isPublic;
  final int bookCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Shelf.fromJson(Map<String, dynamic> json) => Shelf(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        description: json['description'] as String?,
        isPublic: json['isPublic'] == true,
        bookCount: (json['bookCount'] as num?)?.toInt() ?? 0,
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

class ShelfDetail {
  const ShelfDetail({required this.shelf, required this.books});

  final Shelf shelf;
  final List<Book> books;

  factory ShelfDetail.fromJson(Map<String, dynamic> json) => ShelfDetail(
        shelf: Shelf.fromJson(json),
        books: (json['books'] as List<dynamic>? ?? const [])
            .map((item) => Book.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}
