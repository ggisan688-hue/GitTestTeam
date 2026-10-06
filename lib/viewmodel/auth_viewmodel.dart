import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../model/auth.dart';
import '../model/member.dart';
import '../model/signup_request.dart';
import '../repository/member_repository.dart';

/// 로그인 세션. 토큰은 SharedPreferences 에 저장해 앱을 다시 켜도 유지
class AuthViewModel extends ChangeNotifier {
  AuthViewModel(this._repository, this._api) {
    // ApiClient 가 매 요청마다 여기서 토큰을 가져감
    _api.tokenProvider = () => session?.token;
  }

  static const _key = 'auth_session';

  final MemberRepository _repository;
  final ApiClient _api;

  AuthSession? session;
  bool restoring = true; // 앱 시작 시 저장된 세션 확인 중
  bool isLoading = false;
  String? errorMessage;

  bool get isLoggedIn => session != null;
  Member? get member => session?.member;

  /// 앱 시작: 저장된 세션 복원 → 서버에 토큰이 아직 유효한지 확인
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        session = AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        try {
          // 만료됐으면 401 → 세션 폐기. 유효하면 최신 회원 정보(친구 코드 등)로 갱신
          final me = await _repository.me();
          session = AuthSession(token: session!.token, member: me);
          await _persist();
        } on ApiException catch (e) {
          if (e.isUnauthorized) await logout();
        }
      }
    } catch (_) {
      session = null;
    } finally {
      restoring = false;
      notifyListeners();
    }
  }

  Future<bool> login(String login, String password) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      session = await _repository.login(login.trim(), password);
      await _persist();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// 가입 후 바로 로그인
  Future<bool> signup(SignupRequest request) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _repository.signup(request);
      session = await _repository.login(request.username, request.password);
      await _persist();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(session!.toJson()));
  }
}
