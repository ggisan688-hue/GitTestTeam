import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../data/room_store.dart';
import '../model/book.dart';
import '../model/friend.dart';
import '../model/room.dart';
import '../repository/book_repository.dart';
import '../repository/friend_repository.dart';

/// 독서방 목록·현재 방. 방 자체는 로컬(RoomStore), 책 목록·AI 캐릭터는 기존 API.
class RoomViewModel extends ChangeNotifier {
  RoomViewModel(this._store, this._books, this._friends);

  final RoomStore _store;
  final BookRepository _books;
  final FriendRepository _friends;

  int? _memberId;
  String _memberName = '';

  List<Room> rooms = [];
  List<Book> catalog = []; // 서버의 전체 책 (방에 추가할 후보)
  List<Persona> personas = [];
  Room? current;
  bool isLoading = false;
  String? errorMessage;

  Book? bookOf(int id) => catalog.where((b) => b.id == id).firstOrNull;
  Persona? personaOf(int? memberId) => memberId == null
      ? null
      : personas.where((p) => p.memberId == memberId).firstOrNull;
  List<Book> booksOf(Room r) =>
      r.bookIds.map(bookOf).whereType<Book>().toList();
  Persona? personaIn(Room r) => personaOf(r.personaMemberId);

  /// 이어 읽을 책: 마지막에 연 책, 없으면 첫 책
  Book? continueBookOf(Room r) =>
      bookOf(r.lastBookId ?? -1) ?? booksOf(r).firstOrNull;

  /// 로그인 사용자 기준으로 목록을 읽는다
  Future<void> load({required int memberId, required String memberName}) async {
    _memberId = memberId;
    _memberName = memberName;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      rooms = await _store.list(memberId);
      catalog = await _books.books();
      personas = await _friends.personas();
      if (current != null)
        current = rooms.where((r) => r.id == current!.id).firstOrNull;
    } on ApiException catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void select(Room r) {
    current = r;
    notifyListeners();
  }

  Future<Room?> create({
    required String name,
    required List<int> bookIds,
    Persona? persona,
  }) async {
    final id = _memberId;
    if (id == null || name.trim().isEmpty) return null;
    final room = await _store.create(
      id,
      name: name,
      memberName: _memberName,
      bookIds: bookIds,
      persona: persona == null
          ? null
          : RoomMember(
              memberId: persona.memberId,
              name: '${persona.avatar} ${persona.name}',
              ai: true,
            ),
    );
    rooms = [room, ...rooms];
    current = room;
    notifyListeners();
    // 방의 AI 친구 = 내 AI 캐릭터 (서버는 아직 사용자별이라 여기서 맞춰 둔다)
    if (persona != null) await _syncPersona(persona.memberId);
    return room;
  }

  /// 성공이면 방, 실패면 null + errorMessage
  Future<Room?> join(String code) async {
    final id = _memberId;
    if (id == null) return null;
    final room = await _store.join(id, code: code, memberName: _memberName);
    if (room == null) {
      errorMessage = '코드 $code 인 방을 찾을 수 없어요';
      notifyListeners();
      return null;
    }
    rooms = [room, ...rooms.where((r) => r.id != room.id)];
    current = room;
    errorMessage = null;
    notifyListeners();
    if (room.personaMemberId != null) await _syncPersona(room.personaMemberId!);
    return room;
  }

  Future<void> addBooks(Room room, List<int> bookIds) async {
    final merged = [
      ...room.bookIds,
      ...bookIds.where((b) => !room.bookIds.contains(b)),
    ];
    await _update(room.copyWith(bookIds: merged));
  }

  Future<void> removeBook(Room room, int bookId) => _update(
    room.copyWith(bookIds: room.bookIds.where((b) => b != bookId).toList()),
  );

  Future<void> rename(Room room, String name) =>
      _update(room.copyWith(name: name.trim()));

  Future<void> setPersona(Room room, Persona? persona) async {
    final members = room.members.where((m) => !m.ai).toList();
    if (persona != null)
      members.add(
        RoomMember(
          memberId: persona.memberId,
          name: '${persona.avatar} ${persona.name}',
          ai: true,
        ),
      );
    await _update(
      room.copyWith(
        members: members,
        personaMemberId: persona?.memberId,
        clearPersona: persona == null,
      ),
    );
    if (persona != null) await _syncPersona(persona.memberId);
  }

  /// 읽기 화면으로 들어갈 때: 마지막 책 기억
  Future<void> markOpened(Room room, int bookId) async {
    if (room.lastBookId == bookId) return;
    await _update(room.copyWith(lastBookId: bookId));
  }

  Future<void> leave(Room room) async {
    final id = _memberId;
    if (id == null) return;
    await _store.leave(id, room.id);
    rooms = rooms.where((r) => r.id != room.id).toList();
    if (current?.id == room.id) current = null;
    notifyListeners();
  }

  Future<void> _update(Room room) async {
    final id = _memberId;
    if (id == null) return;
    final saved = await _store.update(id, room);
    rooms = rooms.map((r) => r.id == saved.id ? saved : r).toList();
    if (current?.id == saved.id) current = saved;
    notifyListeners();
  }

  Future<void> _syncPersona(int personaMemberId) async {
    try {
      await _friends.choosePersona(personaMemberId);
      personas = await _friends.personas();
      notifyListeners();
    } on ApiException catch (_) {
      // 방 자체는 만들어졌으니 조용히 넘어간다
    }
  }
}
