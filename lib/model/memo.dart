import 'ink.dart';

/// /api/books/{id}/memos, /api/books/{id}/friend-memos
class Memo {
  const Memo({
    required this.id,
    required this.chapter,
    required this.lineNo,
    required this.text,
    required this.author,
    required this.mine,
    required this.spoiler,
    required this.createdAt,
    this.memberId,
    this.kind = 'text',
    this.ink,
    this.ai = false,
    this.commentCount = 0,
  });

  final int id;
  final int chapter;
  final int lineNo;
  final String text; // spoiler 면 서버가 빈 문자열로 내려줌
  final int? memberId;
  final String author;
  final bool mine;
  final bool ai; // AI 독서 친구 캐릭터의 메모
  final bool spoiler;
  final int commentCount;
  final DateTime createdAt;
  final String kind; // text | ink
  final InkMemo? ink; // kind=ink 일 때. 스포일러면 null

  bool get isInk => kind == 'ink';

  factory Memo.fromJson(Map<String, dynamic> json) => Memo(
        id: json['id'] as int,
        chapter: json['chapter'] as int,
        lineNo: json['lineNo'] as int,
        text: json['text'] as String? ?? '',
        memberId: json['memberId'] as int?,
        author: json['author'] as String? ?? '나',
        mine: json['mine'] as bool? ?? true,
        ai: json['ai'] as bool? ?? false,
        spoiler: json['spoiler'] as bool? ?? false,
        commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        kind: json['kind'] as String? ?? 'text',
        ink: InkMemo.fromJson(json['lineNo'] as int, json['ink']),
      );

  Memo copyWith({int? commentCount}) => Memo(
        id: id, chapter: chapter, lineNo: lineNo, text: text, author: author, mine: mine, spoiler: spoiler,
        createdAt: createdAt, memberId: memberId, kind: kind, ink: ink, ai: ai, commentCount: commentCount ?? this.commentCount);

  /// "오후 2:10" 형식
  String get timeLabel {
    final h = createdAt.hour;
    final ampm = h < 12 ? '오전' : '오후';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$ampm $h12:${createdAt.minute.toString().padLeft(2, '0')}';
  }
}
