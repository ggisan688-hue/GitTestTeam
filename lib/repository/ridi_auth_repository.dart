import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';

class RidiAuthException implements Exception {
  const RidiAuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

class RidiAuthUser {
  const RidiAuthUser({required this.id, required this.username, required this.nickname});

  final int id;
  final String username;
  final String nickname;

  factory RidiAuthUser.fromJson(Map<String, dynamic> json) => RidiAuthUser(
        id: (json['id'] as num).toInt(),
        username: json['username'] as String,
        nickname: json['nickname'] as String,
      );
}

class RidiAuthSession {
  const RidiAuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final RidiAuthUser user;

  factory RidiAuthSession.fromJson(Map<String, dynamic> json) => RidiAuthSession(
        accessToken: json['accessToken'] as String,
        user: RidiAuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}

/// Authentication API client. The token is persisted, but a password is never
/// stored on the device.
class RidiAuthRepository {
  RidiAuthRepository({http.Client? client}) : _client = client ?? http.Client();

  static const _tokenKey = 'ridi_auth_access_token';
  final http.Client _client;

  Future<void> signup({required String username, required String password, required String nickname}) async {
    final json = await _request(
      'POST',
      '/api/auth/signup',
      body: {'username': username, 'password': password, 'nickname': nickname},
    );
    if (json['success'] != true) {
      throw RidiAuthException(json['message'] as String? ?? '회원가입에 실패했습니다.');
    }
  }

  Future<RidiAuthSession> login({required String username, required String password}) async {
    final json = await _request(
      'POST',
      '/api/auth/login',
      body: {'username': username, 'password': password},
    );
    final session = RidiAuthSession.fromJson(json);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.accessToken);
    return session;
  }

  Future<RidiAuthUser?> restoreUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return null;
    try {
      final json = await _request('GET', '/api/users/me', token: token);
      return RidiAuthUser.fromJson(json);
    } on RidiAuthException {
      await prefs.remove(_tokenKey);
      return null;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<String?> accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final request = http.Request(method, Uri.parse('${AppConfig.baseUrl}$path'))
      ..headers['Accept'] = 'application/json'
      ..headers['Content-Type'] = 'application/json; charset=utf-8';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await http.Response.fromStream(await _client.send(request));
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw RidiAuthException(json['message'] as String? ?? '서버 요청에 실패했습니다.', statusCode: response.statusCode);
      }
      return json;
    } on http.ClientException {
      throw const RidiAuthException('서버에 연결할 수 없습니다. 백엔드 실행 상태를 확인해주세요.');
    } on FormatException {
      throw const RidiAuthException('서버 응답을 처리할 수 없습니다.');
    }
  }
}
