import 'package:flutter_app/model/reading_room.dart';
import 'package:flutter_app/repository/reading_room_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invite join envelope keeps the room and idempotency flag separate', () {
    final result = ReadingRoomJoinResult.fromJson({
      'alreadyJoined': true,
      'room': {
        'id': 7,
        'name': '고전 함께 읽기',
        'members': 2,
        'maxMembers': 6,
        'isPublic': false,
        'ownerNickname': '방장',
        'createdAt': '2026-10-06T01:02:03Z',
        'joined': true,
        'owner': false,
      },
    });

    expect(result.alreadyJoined, isTrue);
    expect(result.room.id, 7);
    expect(result.room.name, '고전 함께 읽기');
    expect(result.room.createdAt, DateTime.utc(2026, 10, 6, 1, 2, 3));
  });

  test('invite codes use one canonical form at the API boundary', () {
    expect(
      ReadingRoomRepository.normalizeInviteCode(' abcd  - ef12 '),
      'ABCD-EF12',
    );
    expect(ReadingRoomRepository.normalizeInviteCode('abcdEF12'), 'ABCD-EF12');
    expect(
      ReadingRoomRepository.normalizeInviteCode(' abcd\u00A0-\u3000ef12\n'),
      'ABCD-EF12',
    );
    expect(ReadingRoomRepository.normalizeInviteCode('too-short'), 'TOOS-HORT');
  });

  test('room DTO tolerates null and malformed optional fields', () {
    final room = ReadingRoom.fromJson({
      'id': null,
      'name': null,
      'members': null,
      'maxMembers': null,
      'ownerNickname': null,
      'participants': [
        null,
        'not-a-member',
        {
          'userId': null,
          'nickname': null,
          'role': null,
          'roomProfileImageUrl': 42,
        },
      ],
      'book': {'id': null, 'title': null, 'author': null, 'coverImageUrl': 42},
    });

    expect(room.id, 0);
    expect(room.name, '이름 없는 독서방');
    expect(room.members, 0);
    expect(room.maxMembers, 0);
    expect(room.ownerNickname, '알 수 없음');
    expect(room.participants, hasLength(1));
    expect(room.participants.single.nickname, '알 수 없음');
    expect(room.participants.single.role, 'MEMBER');
    expect(room.book?.coverImageUrl, '42');
  });
}
