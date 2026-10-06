class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.nickname,
    this.bio,
    this.avatar,
    this.profileImageUrl,
    this.createdAt,
  });
  final int id;
  final String username;
  final String nickname;
  final String? bio;
  final String? avatar;
  final String? profileImageUrl;
  final DateTime? createdAt;
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: (json['id'] as num).toInt(),
    username: json['username'] as String,
    nickname: json['nickname'] as String,
    bio: json['bio'] as String?,
    avatar: json['avatar'] as String?,
    profileImageUrl: json['profileImageUrl'] as String?,
    createdAt: json['createdAt'] is String
        ? DateTime.tryParse(json['createdAt'] as String)
        : null,
  );
}
