import '../core/api_client.dart';
import '../model/friend.dart';
import '../model/server_friend.dart';

/// 친구 코드 / 요청 / 책별 공유 / AI 캐릭터
class FriendRepository {
  FriendRepository(this._api);

  final ApiClient _api;

  Future<List<ServerFriend>> serverFriends() async => (await _api.get<List<ServerFriend>>('/api/friends',parse:(j)=>(j as List).map((e)=>ServerFriend.fromJson(e as Map<String,dynamic>)).toList())).data??const [];
  Future<List<ServerFriend>> incomingServerRequests() async => (await _api.get<List<ServerFriend>>('/api/friends/requests/incoming',parse:(j)=>(j as List).map((e)=>ServerFriend.fromJson(e as Map<String,dynamic>)).toList())).data??const [];
  Future<List<ServerFriend>> searchServerFriends(String query) async => (await _api.get<List<ServerFriend>>('/api/friends/search',query:{'query':query},parse:(j)=>(j as List).map((e)=>ServerFriend.fromJson(e as Map<String,dynamic>)).toList())).data??const [];
  Future<void> sendServerRequest(String username)=>_api.post('/api/friends/requests/$username');
  Future<void> respondServerRequest(int id,bool accept)=>_api.patch('/api/friends/requests/$id?accept=$accept');
  Future<void> removeServerFriend(int id)=>_api.delete('/api/friends/$id');

  Future<FriendsOverview> overview() async =>
      (await _api.get<FriendsOverview>('/api/friends', parse: (j) => FriendsOverview.fromJson(j as Map<String, dynamic>))).data!;

  Future<void> request(String code) => _api.post('/api/friends/requests', body: {'code': code.trim().toUpperCase()});

  Future<void> accept(int requestId) => _api.post('/api/friends/requests/$requestId/accept');

  Future<void> remove(int memberId) => _api.delete('/api/friends/$memberId');

  Future<List<BookFriendShare>> shares(int bookId) async {
    final res = await _api.get<List<BookFriendShare>>('/api/books/$bookId/shares',
        parse: (j) => (j as List).map((e) => BookFriendShare.fromJson(e as Map<String, dynamic>)).toList());
    return res.data ?? const [];
  }

  Future<List<BookFriendShare>> updateShares(int bookId, List<int> friendIds) async {
    final res = await _api.put<List<BookFriendShare>>('/api/books/$bookId/shares',
        body: {'friendIds': friendIds},
        parse: (j) => (j as List).map((e) => BookFriendShare.fromJson(e as Map<String, dynamic>)).toList());
    return res.data ?? const [];
  }

  Future<List<Persona>> personas() async {
    final res = await _api.get<List<Persona>>('/api/ai/personas',
        parse: (j) => (j as List).map((e) => Persona.fromJson(e as Map<String, dynamic>)).toList());
    return res.data ?? const [];
  }

  Future<Persona> choosePersona(int memberId) async =>
      (await _api.put<Persona>('/api/ai/persona', body: {'memberId': memberId}, parse: (j) => Persona.fromJson(j as Map<String, dynamic>))).data!;
}
