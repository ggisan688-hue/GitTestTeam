import 'package:flutter_app/model/reading_room.dart';
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
        'joined': true,
        'owner': false,
      },
    });

    expect(result.alreadyJoined, isTrue);
    expect(result.room.id, 7);
    expect(result.room.name, '고전 함께 읽기');
  });
}
