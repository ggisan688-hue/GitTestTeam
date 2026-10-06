/// GET /api/books
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    this.description,
    this.coverImageUrl,
    this.category,
    this.createdAt,
    this.updatedAt,
    this.chapterCount = 0,
    this.isFavorite = false,
    this.favoriteCreatedAt,
  });

  final int id;
  final String title;
  final String? author;
  final String? description;
  final String? coverImageUrl;
  final String? category;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int chapterCount;
  final bool isFavorite;
  final DateTime? favoriteCreatedAt;

  factory Book.fromJson(Map<String, dynamic> json) => Book(
    id: json['id'] as int,
    title: json['title'] as String,
    author: json['author'] as String? ?? '',
    description: json['description'] as String?,
    coverImageUrl: json['coverImageUrl'] as String?,
    category: json['category'] as String?,
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
    chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
    isFavorite: json['isFavorite'] == true,
    favoriteCreatedAt: _date(json['favoriteCreatedAt']),
  );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

class RecentBook {
  const RecentBook({
    required this.book,
    required this.progressPercent,
    required this.lastReadPosition,
    required this.lastReadAt,
  });

  final Book book;
  final int progressPercent;
  final int lastReadPosition;
  final DateTime? lastReadAt;

  factory RecentBook.fromJson(Map<String, dynamic> json) => RecentBook(
    book: Book.fromJson(json),
    progressPercent: (json['progressPercent'] as num?)?.toInt() ?? 0,
    lastReadPosition: (json['lastReadPosition'] as num?)?.toInt() ?? 0,
    lastReadAt: Book._date(json['lastReadAt']),
  );
}

class BookParagraph {
  const BookParagraph({this.id, required this.order, required this.text});
  final int? id;
  final int order;
  final String text;
  factory BookParagraph.fromJson(Map<String, dynamic> json) => BookParagraph(
    id: (json['id'] as num?)?.toInt(),
    order: (json['order'] as num).toInt(),
    text: json['text'] as String,
  );
}

class ReaderChapter {
  const ReaderChapter({
    this.id,
    required this.number,
    required this.title,
    required this.startParagraphOrder,
  });
  final int? id;
  final int number;
  final String title;
  final int startParagraphOrder;
  factory ReaderChapter.fromJson(Map<String, dynamic> json) => ReaderChapter(
    id: (json['id'] as num?)?.toInt(),
    number: (json['chapterNumber'] as num).toInt(),
    title: json['title'] as String,
    startParagraphOrder: (json['startParagraphOrder'] as num).toInt(),
  );
}

enum ReaderNoteType { highlight, memo, bookmark }

extension ReaderNoteTypeJson on ReaderNoteType {
  String get api => name.toUpperCase();
}

class ReadingNote {
  const ReadingNote({
    required this.id,
    required this.type,
    required this.paragraphOrder,
    this.memoContent,
    this.selectedText,
    this.startOffset,
    this.endOffset,
    this.highlightColor,
    required this.preview,
    this.createdAt,
    this.updatedAt,
  });
  final int id;
  final ReaderNoteType type;
  final int paragraphOrder;
  final String? memoContent;
  final String? selectedText;
  final int? startOffset;
  final int? endOffset;
  final String? highlightColor;
  final String preview;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  factory ReadingNote.fromJson(Map<String, dynamic> json) => ReadingNote(
    id: (json['id'] as num).toInt(),
    type: ReaderNoteType.values.byName((json['type'] as String).toLowerCase()),
    paragraphOrder: (json['paragraphOrder'] as num).toInt(),
    memoContent: json['memoContent'] as String?,
    selectedText: json['selectedText'] as String?,
    startOffset: (json['startOffset'] as num?)?.toInt(),
    endOffset: (json['endOffset'] as num?)?.toInt(),
    highlightColor: json['highlightColor'] as String?,
    preview: json['paragraphPreview'] as String? ?? '',
    createdAt: Book._date(json['createdAt']),
    updatedAt: Book._date(json['updatedAt']),
  );
}

enum ReaderPaperTheme { light, sepia, dark }

class ReaderSettings {
  const ReaderSettings({
    this.fontScale = 1,
    this.lineHeightStep = 1,
    this.theme = ReaderPaperTheme.light,
    this.twoColumn = false,
    this.keepScreenOn = false,
    this.defaultHighlightColor = '#FFF59D',
  });
  final double fontScale;
  final int lineHeightStep;
  final ReaderPaperTheme theme;
  final bool twoColumn;
  final bool keepScreenOn;
  final String defaultHighlightColor;
  // Backward-compatible convenience for existing reader call sites.
  String get highlightColor => defaultHighlightColor;
  factory ReaderSettings.fromJson(Map<String, dynamic> json) => ReaderSettings(
    fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1,
    lineHeightStep: (json['lineHeightStep'] as num?)?.toInt() ?? 1,
    theme: ReaderPaperTheme.values.byName(
      (json['theme'] as String? ?? 'LIGHT').toLowerCase(),
    ),
    twoColumn: json['twoColumn'] == true,
    keepScreenOn: json['keepScreenOn'] == true,
    defaultHighlightColor:
        json['defaultHighlightColor'] as String? ??
        json['highlightColor'] as String? ??
        '#FFF59D',
  );
  ReaderSettings copyWith({
    double? fontScale,
    int? lineHeightStep,
    ReaderPaperTheme? theme,
    bool? twoColumn,
    bool? keepScreenOn,
    String? defaultHighlightColor,
  }) => ReaderSettings(
    fontScale: fontScale ?? this.fontScale,
    lineHeightStep: lineHeightStep ?? this.lineHeightStep,
    theme: theme ?? this.theme,
    twoColumn: twoColumn ?? this.twoColumn,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    defaultHighlightColor: defaultHighlightColor ?? this.defaultHighlightColor,
  );
  Map<String, dynamic> toJson() => {
    'fontScale': fontScale,
    'lineHeightStep': lineHeightStep,
    'theme': theme.name.toUpperCase(),
    'twoColumn': twoColumn,
    'keepScreenOn': keepScreenOn,
    'defaultHighlightColor': defaultHighlightColor,
  };
}

class BookContent {
  const BookContent({
    required this.bookId,
    required this.title,
    required this.paragraphs,
  });
  final int bookId;
  final String title;
  final List<BookParagraph> paragraphs;
  factory BookContent.fromJson(Map<String, dynamic> json) => BookContent(
    bookId: (json['bookId'] as num).toInt(),
    title: json['title'] as String,
    paragraphs: (json['paragraphs'] as List<dynamic>)
        .map((item) => BookParagraph.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.progressPercent,
    required this.lastReadPosition,
  });
  final int bookId;
  final int progressPercent;
  final int lastReadPosition;
  factory ReadingProgress.fromJson(Map<String, dynamic> json) =>
      ReadingProgress(
        bookId: (json['bookId'] as num).toInt(),
        progressPercent: (json['progressPercent'] as num?)?.toInt() ?? 0,
        lastReadPosition: (json['lastReadPosition'] as num?)?.toInt() ?? 0,
      );
}

/// GET /api/books/{id}/chapters/{n} 의 lines[] 한 줄
class Line {
  const Line({required this.lineNo, required this.text});

  final int lineNo;
  final String text;

  factory Line.fromJson(Map<String, dynamic> json) =>
      Line(lineNo: json['lineNo'] as int, text: json['text'] as String);
}

class Chapter {
  const Chapter({
    required this.bookId,
    required this.title,
    required this.chapter,
    required this.lines,
  });

  final int bookId;
  final String title;
  final int chapter;
  final List<Line> lines;

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
    bookId: json['bookId'] as int,
    title: json['title'] as String,
    chapter: json['chapter'] as int,
    lines: (json['lines'] as List<dynamic>)
        .map((e) => Line.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
