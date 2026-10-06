import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/room.dart';

/// 독서방 로컬 저장소. 서버 `/api/rooms` 가 생기기 전까지 기기 안에만 저장한다.
/// 메서드 모양은 나중의 RoomRepository(API) 와 같게 맞춰 두어 교체만 하면 되게 한다.
///
/// 한계 (서버 없음): 방 코드로 입장은 **이 기기에서 만든 방**만 찾을 수 있다.
class RoomStore {
  static String _key(int memberId) => 'rooms_v1_$memberId';

  Future<List<Room>> list(int memberId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(memberId));
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Room.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(int memberId, List<Room> rooms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(memberId),
      jsonEncode(rooms.map((r) => r.toJson()).toList()),
    );
  }

  Future<Room> create(
    int memberId, {
    required String name,
    required String memberName,
    required List<int> bookIds,
    RoomMember? persona,
  }) async {
    final rooms = await list(memberId);
    final now = DateTime.now();
    final room = Room(
      id: Room.newId(),
      name: name.trim(),
      code: _uniqueCode(rooms),
      ownerId: memberId,
      members: [
        RoomMember(memberId: memberId, name: memberName, joinedAt: now),
        ?persona,
      ],
      bookIds: bookIds,
      personaMemberId: persona?.memberId,
      createdAt: now,
    );
    await _save(memberId, [room, ...rooms]);
    return room;
  }

  /// 코드로 입장. 서버가 없으므로 이 기기의 방만 찾는다 (다른 계정으로 로그인해 만든 방 포함).
  Future<Room?> join(
    int memberId, {
    required String code,
    required String memberName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = code.trim().toUpperCase();
    // 이 기기의 모든 계정 저장소를 훑는다
    for (final key in prefs.getKeys().where((k) => k.startsWith('rooms_v1_'))) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      final rooms = (jsonDecode(raw) as List)
          .map((e) => Room.fromJson(e as Map<String, dynamic>))
          .toList();
      final found = rooms.where((r) => r.code == normalized).firstOrNull;
      if (found == null) continue;
      if (found.members.any((m) => m.memberId == memberId)) return found;
      final joined = found.copyWith(
        members: [
          ...found.members,
          RoomMember(
            memberId: memberId,
            name: memberName,
            joinedAt: DateTime.now(),
          ),
        ],
      );
      // 원래 주인 저장소와 내 저장소 양쪽에 반영
      await prefs.setString(
        key,
        jsonEncode(
          rooms
              .map((r) => r.id == joined.id ? joined.toJson() : r.toJson())
              .toList(),
        ),
      );
      final mine = await list(memberId);
      await _save(memberId, [joined, ...mine.where((r) => r.id != joined.id)]);
      return joined;
    }
    return null;
  }

  Future<Room> update(int memberId, Room room) async {
    final rooms = await list(memberId);
    await _save(
      memberId,
      rooms.map((r) => r.id == room.id ? room : r).toList(),
    );
    return room;
  }

  Future<void> leave(int memberId, String roomId) async {
    final rooms = await list(memberId);
    await _save(memberId, rooms.where((r) => r.id != roomId).toList());
  }

  String _uniqueCode(List<Room> rooms) {
    var code = Room.newCode();
    while (rooms.any((r) => r.code == code)) {
      code = Room.newCode();
    }
    return code;
  }
}
