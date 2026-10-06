import 'dart:typed_data';

import '../core/api_client.dart';
import '../model/reading_room.dart';
import '../model/shared_room_note.dart';

class ReadingRoomRepository {
  ReadingRoomRepository(this._api);

  final ApiClient _api;

  String absoluteUrl(String path) => _api.absolute(path);

  Future<List<ReadingRoom>> list() async {
    final response = await _api.get<List<ReadingRoom>>(
      '/api/reading-rooms',
      parse: (json) => (json as List<dynamic>)
          .map((item) => ReadingRoom.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
    return response.data ?? const [];
  }

  /// Authenticated user's rooms only.  Unlike [list], this never includes a
  /// public room the user has not joined.
  Future<List<ReadingRoom>> myRooms() async {
    final response = await _api.get<List<ReadingRoom>>(
      '/api/reading-rooms/my',
      parse: (json) => (json as List<dynamic>)
          .map((item) => ReadingRoom.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
    return response.data ?? const [];
  }

  Future<ReadingRoom> detail(int roomId) async {
    final response = await _api.get<ReadingRoom>(
      '/api/reading-rooms/$roomId',
      parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
    );
    return response.data!;
  }

  Future<ReadingRoom> create(Map<String, dynamic> body) async {
    final response = await _api.post<ReadingRoom>(
      '/api/reading-rooms',
      body: body,
      parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
    );
    return response.data!;
  }

  Future<ReadingRoomJoinResult> join(String code) async {
    final response = await _api.post<ReadingRoomJoinResult>(
      '/api/reading-rooms/join-by-code',
      body: {'inviteCode': normalizeInviteCode(code)},
      parse: (json) => ReadingRoomJoinResult.fromJson(json as Map<String, dynamic>),
    );
    return response.data!;
  }

  /// Codes are displayed as XXXX-XXXX, but accepting copied values without a
  /// hyphen or with whitespace avoids making presentation part of the API
  /// contract. The server applies the identical canonical form.
  static String normalizeInviteCode(String value) {
    final compact = value.trim().replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();
    return compact.length == 8 ? '${compact.substring(0, 4)}-${compact.substring(4)}' : compact;
  }

  /// Rooms the authenticated user has already joined and that use [bookId]
  /// as their representative book. This is deliberately not the public room
  /// directory: annotations may only be shared to active memberships.
  Future<List<ReadingRoom>> shareTargets(int bookId) async =>
      (await _api.get<List<ReadingRoom>>(
        '/api/reading-rooms/share-targets/books/$bookId',
        parse: (json) => (json as List<dynamic>)
            .map((item) => ReadingRoom.fromJson(item as Map<String, dynamic>))
            .toList(),
      )).data ??
      const [];

  Future<List<SharedRoomNote>> sharedNotes(int roomId) async =>
      (await _api.get<List<SharedRoomNote>>(
        '/api/reading-rooms/$roomId/shared-notes',
        parse: (json) => (json as List)
            .map((e) => SharedRoomNote.fromJson(e as Map<String, dynamic>))
            .toList(),
      )).data ??
      const [];

  /// Event payloads contain metadata only. A caller must refetch shared notes
  /// after receiving one so the server can apply its per-user spoiler filter.
  Future<List<int>> syncEventIds(int roomId, int after) async =>
      (await _api.get<List<int>>(
        '/api/reading-rooms/$roomId/shared-notes/sync',
        query: {'after': '$after'},
        parse: (json) => (json as List<dynamic>)
            .map((item) => (item as Map<String, dynamic>)['id'] as num)
            .map((id) => id.toInt())
            .toList(),
      )).data ??
      const [];
  Future<SharedRoomNote> createSharedNote(
    int roomId,
    Map<String, dynamic> body,
  ) async => (await _api.post<SharedRoomNote>(
    '/api/reading-rooms/$roomId/shared-notes',
    body: body,
    parse: (json) => SharedRoomNote.fromJson(json as Map<String, dynamic>),
  )).data!;
  Future<void> deleteSharedNote(int roomId, int noteId) =>
      _api.delete('/api/reading-rooms/$roomId/shared-notes/$noteId');
  Future<List<SharedRoomNoteComment>> sharedNoteComments(
    int roomId,
    int noteId,
  ) async =>
      (await _api.get<List<SharedRoomNoteComment>>(
        '/api/reading-rooms/$roomId/shared-notes/$noteId/comments',
        parse: (json) => (json as List)
            .map(
              (e) => SharedRoomNoteComment.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      )).data ??
      const [];
  Future<SharedRoomNoteComment> addSharedNoteComment(
    int roomId,
    int noteId,
    String content,
  ) async => (await _api.post<SharedRoomNoteComment>(
    '/api/reading-rooms/$roomId/shared-notes/$noteId/comments',
    body: {'content': content.trim()},
    parse: (json) =>
        SharedRoomNoteComment.fromJson(json as Map<String, dynamic>),
  )).data!;
  Future<void> deleteSharedNoteComment(int roomId, int noteId, int commentId) =>
      _api.delete(
        '/api/reading-rooms/$roomId/shared-notes/$noteId/comments/$commentId',
      );

  Future<ReadingRoom> joinPublic(int roomId) async {
    final response = await _api.post<ReadingRoom>(
      '/api/reading-rooms/$roomId/members',
      parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
    );
    return response.data!;
  }

  Future<void> leave(int roomId) =>
      _api.delete('/api/reading-rooms/$roomId/members/me');

  Future<ReadingRoom> update(int roomId, Map<String, dynamic> body) async {
    final response = await _api.patch<ReadingRoom>(
      '/api/reading-rooms/$roomId',
      body: body,
      parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
    );
    return response.data!;
  }

  Future<ReadingRoom> reissueCode(int roomId) async {
    final response = await _api.post<ReadingRoom>(
      '/api/reading-rooms/$roomId/join-code',
      parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
    );
    return response.data!;
  }

  Future<ReadingRoom> regenerateInviteCode(int roomId) async {
    final response = await _api.post<ReadingRoom>(
      '/api/reading-rooms/$roomId/invite-code/regenerate',
      parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
    );
    return response.data!;
  }

  Future<void> kick(int roomId, int memberId) =>
      _api.delete('/api/reading-rooms/$roomId/members/$memberId');

  Future<void> delete(int roomId) => _api.delete('/api/reading-rooms/$roomId');

  Future<ReadingRoomMember> uploadMyRoomProfileImage(
    int roomId, {
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async =>
      (await _api.uploadFile<ReadingRoomMember>(
        '/api/reading-rooms/$roomId/members/me/profile-image',
        method: 'PUT',
        fieldName: 'profileImage',
        bytes: bytes,
        filename: filename,
        contentType: contentType,
        parse: (json) =>
            ReadingRoomMember.fromJson(json as Map<String, dynamic>),
      )).data!;

  Future<void> deleteMyRoomProfileImage(int roomId) => _api.delete(
    '/api/reading-rooms/$roomId/members/me/profile-image',
  );
}
