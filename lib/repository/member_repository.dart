import '../core/api_client.dart';
import '../model/auth.dart';
import '../model/member.dart';
import '../model/signup_request.dart';

/// 회원가입 / 로그인 / 중복확인
class MemberRepository {
  MemberRepository(this._api);

  final ApiClient _api;

  Future<Member> signup(SignupRequest request) async {
    final res = await _api.post<Member>(
      '/api/members/signup',
      body: request.toJson(),
      parse: (json) => Member.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }

  /// login: 이메일 또는 아이디
  Future<AuthSession> login(String login, String password) async {
    final res = await _api.post<AuthSession>(
      '/api/members/login',
      body: {'login': login, 'password': password},
      parse: (json) => AuthSession.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }

  Future<Member> me() async {
    final res = await _api.get<Member>(
      '/api/members/me',
      parse: (json) => Member.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }

  Future<bool> isEmailAvailable(String email) async {
    final res = await _api.get<bool>(
      '/api/members/check-email',
      query: {'email': email},
      parse: (json) => (json as Map<String, dynamic>)['available'] == true,
    );
    return res.data ?? false;
  }

  Future<bool> isUsernameAvailable(String username) async {
    final res = await _api.get<bool>(
      '/api/members/check-username',
      query: {'username': username},
      parse: (json) => (json as Map<String, dynamic>)['available'] == true,
    );
    return res.data ?? false;
  }
}
