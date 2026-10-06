class ServerFriend {
  const ServerFriend({
    required this.id,
    required this.username,
    required this.nickname,
    required this.status,
  });
  final int id;
  final String username, nickname, status;
  factory ServerFriend.fromJson(Map<String, dynamic> j) => ServerFriend(
    id: (j['id'] as num).toInt(),
    username: j['username'] as String,
    nickname: j['nickname'] as String,
    status: j['status'] as String,
  );
}
