import 'package:flutter_app/view/ridi/ridi_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('room book removal updates the room and its current-book target', () {
    final store = RidiStore();
    final room = store.room('r2')!;
    room.members = [RidiMember(store.name, owner: true)];

    expect(store.removeRoomBook(room.id, 'b1'), isTrue);
    expect(room.bookIds, isNot(contains('b1')));
    expect(room.lastBookId, room.bookIds.first);
    expect(store.removeRoomBook(room.id, 'missing'), isFalse);
  });

  test('room owner can remove a shared note and its comments', () {
    final store = RidiStore();
    final room = store.room('r2')!;
    room.members = [RidiMember(store.name, owner: true)];
    final note = RidiNote(
      id: 'shared-note',
      bookId: 'b1',
      kind: NoteKind.highlight,
      chapter: 0,
      page: 1,
      line: 0,
      phrase: 'shared',
      createdAt: DateTime(2026, 10, 12),
      roomIds: [room.id],
      mine: false,
      author: 'member',
    );
    store.notes.add(note);
    store.comments.add(
      RidiComment(
        id: 'shared-comment',
        noteId: note.id,
        text: 'comment',
        createdAt: DateTime(2026, 10, 12),
      ),
    );

    expect(store.canDeleteNote(note), isTrue);
    store.deleteNotes([note.id]);

    expect(store.note(note.id), isNull);
    expect(store.commentsOf(note.id), isEmpty);
  });
}
