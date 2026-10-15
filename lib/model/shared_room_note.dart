import 'note_range.dart';
class SharedRoomNote {
  const SharedRoomNote({
    required this.id,
    required this.userId,
    required this.nickname,
    this.profileImageUrl,
    required this.type,
    required this.paragraphOrder,
    this.startOffset,
    this.endOffset,
    this.ranges = const [],
    this.selectedText,
    this.content,
    this.highlightColor,
    required this.isSpoilerLocked,
    required this.commentCount,
    this.mine = false,
    this.canDelete = false,
    this.createdAt,
    this.version = 0,
    this.explicitlyRevealed = false,
  });
  final int id, userId, paragraphOrder, commentCount;
  final int version;
  final bool explicitlyRevealed;
  final String nickname, type;
  final String? profileImageUrl;
  final int? startOffset, endOffset;
  final List<NoteRange> ranges;
  final String? selectedText, content, highlightColor;
  final bool isSpoilerLocked;
  final bool mine;
  final bool canDelete;
  final DateTime? createdAt;
  factory SharedRoomNote.fromJson(Map<String, dynamic> json) => SharedRoomNote(
    explicitlyRevealed: json['explicitlyRevealed'] == true,
    version: (json['version'] as num?)?.toInt() ?? 0,
    id: (json['id'] as num).toInt(),
    userId: (json['userId'] as num).toInt(),
    nickname: json['nickname'] as String? ?? '알 수 없음',
    profileImageUrl: json['profileImageUrl'] as String?,
    type: json['type'] as String,
    paragraphOrder: (json['paragraphOrder'] as num).toInt(),
    startOffset: (json['startOffset'] as num?)?.toInt(),
    endOffset: (json['endOffset'] as num?)?.toInt(),
    ranges: (json['ranges'] as List? ?? const [])
        .map((item) => NoteRange.fromJson(item as Map<String, dynamic>)).toList(),
    selectedText: json['selectedText'] as String?,
    content: json['content'] as String?,
    highlightColor: json['highlightColor'] as String?,
    isSpoilerLocked: json['isSpoilerLocked'] == true,
    mine: json['mine'] == true,
    canDelete: json['canDelete'] == true || json['mine'] == true,
    commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
    createdAt: json['createdAt'] is String
        ? DateTime.tryParse(json['createdAt'] as String)
        : null,
  );
}

class SharedRoomNoteComment {
  const SharedRoomNoteComment({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.content,
    required this.mine,
    this.createdAt,
    this.canDelete = false,
  });
  final int id, userId;
  final String nickname, content;
  final bool mine;
  final bool canDelete;
  final DateTime? createdAt;
  factory SharedRoomNoteComment.fromJson(Map<String, dynamic> json) =>
      SharedRoomNoteComment(
        id: (json['id'] as num).toInt(),
        userId: (json['userId'] as num).toInt(),
        nickname: json['nickname'] as String? ?? '알 수 없음',
        content: json['content'] as String,
        mine: json['mine'] == true,
        canDelete: json['canDelete'] == true || json['mine'] == true,
        createdAt: json['createdAt'] is String
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
      );
}
