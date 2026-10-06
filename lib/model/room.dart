import 'dart:math';

/// 독서방. 지금은 기기 안(SharedPreferences)에만 저장되고, 서버 API 가 생기면
/// 같은 모양의 JSON 을 그대로 주고받는다 (docs/ROOM_DESIGN.md 의 계약).
class Room {
  const Room({
    required this.id,
    required this.name,
    required this.code,
    required this.ownerId,
    required this.members,
    required this.bookIds,
    required this.createdAt,
    this.personaMemberId,
    this.lastBookId,
  });

  final String id;
  final String name;

  /// 입장 코드 `RM-XXXX`
  final String code;
  final int ownerId;
  final List<RoomMember> members;

  /// 이 방에서 함께 읽는 책 (순서 = 추가 순)
  final List<int> bookIds;

  /// 방의 AI 독서 친구 (personas 의 memberId)
  final int? personaMemberId;

  /// 마지막으로 연 책 (이어 읽기)
  final int? lastBookId;
  final DateTime createdAt;

  bool isOwner(int memberId) => ownerId == memberId;
  int get humanCount => members.where((m) => !m.ai).length;

  Room copyWith({
    String? name,
    List<RoomMember>? members,
    List<int>? bookIds,
    int? personaMemberId,
    int? lastBookId,
    bool clearPersona = false,
  }) => Room(
    id: id,
    name: name ?? this.name,
    code: code,
    ownerId: ownerId,
    members: members ?? this.members,
    bookIds: bookIds ?? this.bookIds,
    personaMemberId: clearPersona
        ? null
        : (personaMemberId ?? this.personaMemberId),
    lastBookId: lastBookId ?? this.lastBookId,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'ownerId': ownerId,
    'members': members.map((m) => m.toJson()).toList(),
    'bookIds': bookIds,
    'personaMemberId': personaMemberId,
    'lastBookId': lastBookId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Room.fromJson(Map<String, dynamic> j) => Room(
    id: j['id'] as String,
    name: j['name'] as String,
    code: j['code'] as String,
    ownerId: j['ownerId'] as int,
    members: (j['members'] as List)
        .map((e) => RoomMember.fromJson(e as Map<String, dynamic>))
        .toList(),
    bookIds: (j['bookIds'] as List).cast<int>(),
    personaMemberId: j['personaMemberId'] as int?,
    lastBookId: j['lastBookId'] as int?,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );

  static final _rand = Random();
  static const _alphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 헷갈리는 글자(I,O,0,1) 제외

  static String newCode() =>
      'RM-${List.generate(4, (_) => _alphabet[_rand.nextInt(_alphabet.length)]).join()}';
  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}

class RoomMember {
  const RoomMember({
    required this.memberId,
    required this.name,
    this.ai = false,
    this.joinedAt,
  });

  final int memberId;
  final String name;
  final bool ai;
  final DateTime? joinedAt;

  /// 아바타용 첫 글자
  String get initial => name.isEmpty ? '?' : name[0];

  Map<String, dynamic> toJson() => {
    'memberId': memberId,
    'name': name,
    'ai': ai,
    'joinedAt': joinedAt?.toIso8601String(),
  };

  factory RoomMember.fromJson(Map<String, dynamic> j) => RoomMember(
    memberId: j['memberId'] as int,
    name: j['name'] as String,
    ai: j['ai'] as bool? ?? false,
    joinedAt: j['joinedAt'] == null
        ? null
        : DateTime.parse(j['joinedAt'] as String),
  );
}
