import 'member.dart';

/// POST /api/members/login 응답
class AuthSession {
  const AuthSession({required this.token, required this.member});

  final String token;
  final Member member;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    token: json['token'] as String,
    member: Member.fromJson(json['member'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {
    'token': token,
    'member': {
      'id': member.id,
      'email': member.email,
      'username': member.username,
      'name': member.name,
      'friendCode': member.friendCode,
      'aiPersonaId': member.aiPersonaId,
    },
  };
}
