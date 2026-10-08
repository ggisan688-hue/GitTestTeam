int _jsonInt(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String _jsonString(Object? value, String fallback) =>
    value?.toString() ?? fallback;

String? _jsonNullableString(Object? value) => value?.toString();

bool _jsonBool(Object? value) =>
    value == true || value?.toString().toLowerCase() == 'true';

class ReadingRoomBook {
  const ReadingRoomBook({
    required this.id,
    required this.title,
    required this.author,
    this.coverImageUrl,
  });

  final int id;
  final String title;
  final String author;
  final String? coverImageUrl;

  factory ReadingRoomBook.fromJson(Map<String, dynamic> json) =>
      ReadingRoomBook(
        id: _jsonInt(json['id']),
        title: _jsonString(json['title'], ''),
        author: _jsonString(json['author'], ''),
        coverImageUrl: _jsonNullableString(json['coverImageUrl']),
      );
}

class ReadingRoomMember {
  const ReadingRoomMember({
    required this.userId,
    required this.nickname,
    required this.role,
    this.roomProfileImageUrl,
  });
  final int userId;
  final String nickname;
  final String role;

  /// The room-specific photo when present; the API falls back to the member's
  /// account photo so callers can render one consistent avatar field.
  final String? roomProfileImageUrl;
  factory ReadingRoomMember.fromJson(Map<String, dynamic> json) =>
      ReadingRoomMember(
        userId: _jsonInt(json['userId']),
        nickname: _jsonString(json['nickname'], '알 수 없음'),
        role: _jsonString(json['role'], 'MEMBER'),
        roomProfileImageUrl: _jsonNullableString(json['roomProfileImageUrl']),
      );
}

class ReadingRoom {
  const ReadingRoom({
    required this.id,
    required this.name,
    this.description,
    this.bookId,
    required this.members,
    required this.maxMembers,
    required this.isPublic,
    required this.ownerNickname,
    this.ownerId,
    this.createdAt,
    this.joined = false,
    this.isOwner = false,
    this.joinCode,
    this.spoilerLockEnabled = false,
    this.selectedAiFriendType,
    this.book,
    this.coverBook,
    this.myRole,
    this.participants = const [],
    this.passwordRequired = false,
    this.currentBookId,
    this.books = const [],
  });

  final int id;
  final String name;
  final String? description;
  final int? bookId;
  final int members;
  final int maxMembers;
  final bool isPublic;
  final String ownerNickname;
  final int? ownerId;

  /// Authoritative server creation time, retained when a create/join response
  /// is inserted into the local room list before the next reconciliation.
  final DateTime? createdAt;
  final bool joined;
  final bool isOwner;
  final String? joinCode;
  final bool spoilerLockEnabled;
  final String? selectedAiFriendType;
  final ReadingRoomBook? book;

  /// Current room book, or the first linked book for legacy rooms. Used as
  /// the stable visual cover without adding a mutable duplicate DB column.
  final ReadingRoomBook? coverBook;
  final String? myRole;
  final List<ReadingRoomMember> participants;
  final bool passwordRequired;
  final int? currentBookId;
  final List<ReadingRoomBookItem> books;

  factory ReadingRoom.fromJson(Map<String, dynamic> json) => ReadingRoom(
    id: _jsonInt(json['id']),
    name: _jsonString(json['name'], '이름 없는 독서방'),
    description: _jsonNullableString(json['description']),
    bookId: json['bookId'] == null ? null : _jsonInt(json['bookId']),
    members: _jsonInt(json['members']),
    maxMembers: _jsonInt(json['maxMembers']),
    isPublic: _jsonBool(json['isPublic']),
    ownerNickname: _jsonString(json['ownerNickname'], '알 수 없음'),
    ownerId: json['ownerId'] == null ? null : _jsonInt(json['ownerId']),
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'].toString())
        : null,
    joined: _jsonBool(json['joined']),
    isOwner: _jsonBool(json['owner']),
    joinCode: _jsonNullableString(json['joinCode']),
    spoilerLockEnabled: _jsonBool(json['spoilerLockEnabled']),
    selectedAiFriendType: _jsonNullableString(json['selectedAiFriendType']),
    book: json['book'] is Map
        ? ReadingRoomBook.fromJson(
            Map<String, dynamic>.from(json['book'] as Map),
          )
        : null,
    coverBook: json['coverBook'] is Map
        ? ReadingRoomBook.fromJson(
            Map<String, dynamic>.from(json['coverBook'] as Map),
          )
        : null,
    myRole: _jsonNullableString(json['myRole']),
    participants:
        (json['participants'] is List ? json['participants'] as List : const [])
            .whereType<Map>()
            .map(
              (item) =>
                  ReadingRoomMember.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(),
    passwordRequired: _jsonBool(json['passwordRequired']),
    currentBookId: json['currentBookId'] == null
        ? null
        : _jsonInt(json['currentBookId']),
    books: (json['books'] is List ? json['books'] as List : const [])
        .whereType<Map>()
        .map(
          (item) =>
              ReadingRoomBookItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(),
  );
}

class ReadingRoomBookItem {
  const ReadingRoomBookItem({
    required this.book,
    required this.order,
    required this.current,
  });
  final ReadingRoomBook book;
  final int order;
  final bool current;
  factory ReadingRoomBookItem.fromJson(Map<String, dynamic> json) =>
      ReadingRoomBookItem(
        book: ReadingRoomBook.fromJson(
          Map<String, dynamic>.from(json['book'] as Map? ?? const {}),
        ),
        order: _jsonInt(json['order']),
        current: _jsonBool(json['current']),
      );
}

/// Invite-code joins have idempotency metadata that does not belong to a room
/// list/detail response.
class ReadingRoomJoinResult {
  const ReadingRoomJoinResult({
    required this.room,
    required this.alreadyJoined,
  });

  final ReadingRoom room;
  final bool alreadyJoined;

  factory ReadingRoomJoinResult.fromJson(Map<String, dynamic> json) =>
      ReadingRoomJoinResult(
        room: ReadingRoom.fromJson(
          json['room'] is Map
              ? Map<String, dynamic>.from(json['room'] as Map)
              : const <String, dynamic>{},
        ),
        alreadyJoined: _jsonBool(json['alreadyJoined']),
      );
}
