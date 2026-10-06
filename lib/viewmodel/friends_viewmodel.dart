import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../model/friend.dart';
import '../repository/friend_repository.dart';

/// 친구 목록/요청 + AI 캐릭터 선택 + 책별 공유 설정
class FriendsViewModel extends ChangeNotifier {
  FriendsViewModel(this._repo);

  final FriendRepository _repo;

  FriendsOverview? overview;
  List<Persona> personas = [];
  List<BookFriendShare> shares = [];
  bool isLoading = false;
  String? errorMessage;

  Persona? get chosenPersona => personas.where((p) => p.chosen).firstOrNull;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      overview = await _repo.overview();
      personas = await _repo.personas();
    } on ApiException catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> request(String code) => _guard(() => _repo.request(code));
  Future<String?> accept(int id) => _guard(() => _repo.accept(id));
  Future<String?> remove(int memberId) => _guard(() => _repo.remove(memberId));

  Future<String?> choosePersona(int memberId) => _guard(() async {
        await _repo.choosePersona(memberId);
        personas = await _repo.personas();
      }, reload: false);

  // ---------- 책별 공유 ----------
  Future<void> loadShares(int bookId) async {
    try {
      shares = await _repo.shares(bookId);
    } on ApiException catch (e) {
      errorMessage = e.message;
    }
    notifyListeners();
  }

  Future<String?> toggleShare(int bookId, int friendId, bool on) => _guard(() async {
        final ids = shares.where((s) => s.sharedByMe).map((s) => s.friend.memberId).toSet();
        if (on) {
          ids.add(friendId);
        } else {
          ids.remove(friendId);
        }
        shares = await _repo.updateShares(bookId, ids.toList());
      }, reload: false);

  /// 성공이면 null, 실패면 에러 메시지
  Future<String?> _guard(Future<void> Function() action, {bool reload = true}) async {
    try {
      await action();
      if (reload) await load();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }
}
