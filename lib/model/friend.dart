/// /api/friends
class Friend {
  const Friend({required this.memberId, required this.name, required this.username, this.ai = false});

  final int memberId;
  final String name;
  final String username;
  final bool ai;

  factory Friend.fromJson(Map<String, dynamic> j) =>
      Friend(memberId: j['memberId'] as int, name: j['name'] as String, username: j['username'] as String, ai: j['ai'] as bool? ?? false);
}

class FriendRequest {
  const FriendRequest({required this.id, required this.other, required this.incoming, required this.createdAt});

  final int id;
  final Friend other;
  final bool incoming;
  final DateTime createdAt;

  factory FriendRequest.fromJson(Map<String, dynamic> j) => FriendRequest(
      id: j['id'] as int,
      other: Friend.fromJson(j['other'] as Map<String, dynamic>),
      incoming: j['incoming'] as bool,
      createdAt: DateTime.parse(j['createdAt'] as String));
}

class FriendsOverview {
  const FriendsOverview({required this.myCode, required this.friends, required this.incoming, required this.outgoing});

  final String myCode;
  final List<Friend> friends;
  final List<FriendRequest> incoming;
  final List<FriendRequest> outgoing;

  factory FriendsOverview.fromJson(Map<String, dynamic> j) => FriendsOverview(
      myCode: j['myCode'] as String,
      friends: (j['friends'] as List).map((e) => Friend.fromJson(e as Map<String, dynamic>)).toList(),
      incoming: (j['incoming'] as List).map((e) => FriendRequest.fromJson(e as Map<String, dynamic>)).toList(),
      outgoing: (j['outgoing'] as List).map((e) => FriendRequest.fromJson(e as Map<String, dynamic>)).toList());
}

/// /api/books/{id}/shares 한 줄
class BookFriendShare {
  const BookFriendShare({required this.friend, required this.sharedByMe, required this.sharedToMe, required this.chapter, required this.lineNo});

  final Friend friend;
  final bool sharedByMe;
  final bool sharedToMe;
  final int chapter;
  final int lineNo;

  String get progressLabel => chapter == 1 && lineNo == 0 ? '시작 전' : '$chapter장 $lineNo줄';

  factory BookFriendShare.fromJson(Map<String, dynamic> j) => BookFriendShare(
      friend: Friend.fromJson(j['friend'] as Map<String, dynamic>),
      sharedByMe: j['sharedByMe'] as bool,
      sharedToMe: j['sharedToMe'] as bool,
      chapter: j['chapter'] as int,
      lineNo: j['lineNo'] as int);
}

/// /api/ai/personas
class Persona {
  const Persona({required this.memberId, required this.key, required this.name, required this.avatar, required this.intro, required this.chosen});

  final int memberId;
  final String key;
  final String name;
  final String avatar;
  final String intro;
  final bool chosen;

  factory Persona.fromJson(Map<String, dynamic> j) => Persona(
      memberId: j['memberId'] as int,
      key: j['key'] as String,
      name: j['name'] as String,
      avatar: j['avatar'] as String,
      intro: j['intro'] as String,
      chosen: j['chosen'] as bool? ?? false);
}

/// /api/memos/{id}/comments
class Comment {
  const Comment({required this.id, required this.memoId, required this.author, required this.ai, required this.mine, required this.text, this.imageUrl, required this.createdAt});

  final int id;
  final int memoId;
  final String author;
  final bool ai;
  final bool mine;
  final String text;
  final String? imageUrl;
  final DateTime createdAt;

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
      id: j['id'] as int,
      memoId: j['memoId'] as int,
      author: j['author'] as String,
      ai: j['ai'] as bool? ?? false,
      mine: j['mine'] as bool? ?? false,
      text: j['text'] as String? ?? '',
      imageUrl: j['imageUrl'] as String?,
      createdAt: DateTime.parse(j['createdAt'] as String));
}
