/// 읽는 지점 — /api/books/{id}/progress
class Progress {
  const Progress({required this.chapter, required this.lineNo});

  final int chapter;
  final int lineNo;

  factory Progress.fromJson(Map<String, dynamic> json) =>
      Progress(chapter: json['chapter'] as int, lineNo: json['lineNo'] as int);

  /// (chapter, lineNo) 가 이 진행도보다 뒤인가
  bool isAhead(int c, int l) => c > chapter || (c == chapter && l > lineNo);
}
