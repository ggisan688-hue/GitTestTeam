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
        id: (json['id'] as num).toInt(),
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        coverImageUrl: json['coverImageUrl'] as String?,
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
        userId: (json['userId'] as num).toInt(),
        nickname: json['nickname'] as String,
        role: json['role'] as String,
        roomProfileImageUrl: json['roomProfileImageUrl'] as String?,
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
    this.joined = false,
    this.isOwner = false,
    this.joinCode,
    this.spoilerLockEnabled = false,
    this.selectedAiFriendType,
    this.book,
    this.myRole,
    this.alreadyJoined = false,
    this.participants = const [],
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
  final bool joined;
  final bool isOwner;
  final String? joinCode;
  final bool spoilerLockEnabled;
  final String? selectedAiFriendType;
  final ReadingRoomBook? book;
  final String? myRole;
  final bool alreadyJoined;
  final List<ReadingRoomMember> participants;

  factory ReadingRoom.fromJson(Map<String, dynamic> json) => ReadingRoom(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String,
    description: json['description'] as String?,
    bookId: (json['bookId'] as num?)?.toInt(),
    members: (json['members'] as num).toInt(),
    maxMembers: (json['maxMembers'] as num).toInt(),
    isPublic: json['isPublic'] == true,
    ownerNickname: json['ownerNickname'] as String,
    ownerId: (json['ownerId'] as num?)?.toInt(),
    joined: json['joined'] == true,
    isOwner: json['owner'] == true,
    joinCode: json['joinCode'] as String?,
    spoilerLockEnabled: json['spoilerLockEnabled'] == true,
    selectedAiFriendType: json['selectedAiFriendType'] as String?,
    book: json['book'] is Map<String, dynamic>
        ? ReadingRoomBook.fromJson(json['book'] as Map<String, dynamic>)
        : null,
    myRole: json['myRole'] as String?,
    alreadyJoined: json['alreadyJoined'] == true,
    participants: (json['participants'] as List<dynamic>? ?? const [])
        .map((item) => ReadingRoomMember.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}
