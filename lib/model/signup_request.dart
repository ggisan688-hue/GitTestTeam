/// POST /api/members/signup 요청 바디 (Spring 의 SignupRequest 와 동일)
class SignupRequest {
  const SignupRequest({
    required this.email,
    required this.username,
    required this.password,
    required this.name,
  });

  final String email;
  final String username;
  final String password;
  final String name;

  Map<String, dynamic> toJson() => {
        'email': email,
        'username': username,
        'password': password,
        'name': name,
      };
}
