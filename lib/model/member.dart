/// 회원가입 성공 시 서버가 돌려주는 회원 정보 (SignupResponse 와 동일)
class Member {
  const Member({
    required this.id,
    required this.email,
    required this.username,
    required this.name,
    this.friendCode,
    this.aiPersonaId,
  });

  final int id;
  final String email;
  final String username;
  final String name;
  final String? friendCode;
  final int? aiPersonaId;

  factory Member.fromJson(Map<String, dynamic> json) => Member(
    id: json['id'] as int,
    email: json['email'] as String,
    username: json['username'] as String,
    name: json['name'] as String,
    friendCode: json['friendCode'] as String?,
    aiPersonaId: json['aiPersonaId'] as int?,
  );
}
