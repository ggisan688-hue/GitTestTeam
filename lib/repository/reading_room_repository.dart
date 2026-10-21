import 'dart:typed_data';

import '../core/api_client.dart';
import '../model/reading_room.dart';
import '../model/shared_room_note.dart';

class RoomParticipantProgress {
  const RoomParticipantProgress({
    required this.userId,
    required this.nickname,
    this.profileImageUrl,
    required this.progressPercent,
    required this.lastReadPosition,
    this.updatedAt,
    required this.currentUser,
  });
  final int userId;
  final String nickname;
  final String? profileImageUrl;
  final int progressPercent;
  final int lastReadPosition;
  final DateTime? updatedAt;
  final bool currentUser;
  factory RoomParticipantProgress.fromJson(Map<String, dynamic> json) =>
      RoomParticipantProgress(
        userId: (json['userId'] as num).toInt(),
        nickname: json['nickname']?.toString() ?? '참여자',
        profileImageUrl: json['profileImageUrl']?.toString(),
        progressPercent: (json['progressPercent'] as num?)?.toInt() ?? 0,
        lastReadPosition: (json['lastReadPosition'] as num?)?.toInt() ?? 0,
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.tryParse(json['updatedAt'].toString()),
        currentUser: json['currentUser'] == true,
      );
}

class RoomReadingProgress {
  const RoomReadingProgress({
    required this.progressPercent,
    required this.lastReadPosition,
  });
  final int progressPercent;
  final int lastReadPosition;
  factory RoomReadingProgress.fromJson(Map<String, dynamic> json) =>
      RoomReadingProgress(
        progressPercent: (json['progressPercent'] as num?)?.toInt() ?? 0,
        lastReadPosition: (json['lastReadPosition'] as num?)?.toInt() ?? 0,
      );
}

class InviteCodeValidation {
  const InviteCodeValidation({
    required this.roomId,
    required this.roomName,
    required this.passwordRequired,
    required this.capacity,
    required this.currentMemberCount,
    required this.alreadyJoined,
  });
  final int roomId, capacity, currentMemberCount;
  final String roomName;
  final bool passwordRequired, alreadyJoined;
  factory InviteCodeValidation.fromJson(Map<String, dynamic> json) =>
      InviteCodeValidation(
        roomId: (json['roomId'] as num).toInt(),
        roomName: json['roomName'] as String? ?? '',
        passwordRequired: json['passwordRequired'] == true,
        capacity: (json['capacity'] as num?)?.toInt() ?? 0,
        currentMemberCount: (json['currentMemberCount'] as num?)?.toInt() ?? 0,
        alreadyJoined: json['alreadyJoined'] == true,
      );
}

/// 지금 책 화면을 열어 둔 친구 한 명 (서버 메모리 기준, 35초 안에 신호가 있던 사람).
class RoomPresence {
  const RoomPresence({
    required this.userId,
    required this.bookId,
    required this.position,
    this.writing = false,
  });
  final int userId;
  final int bookId;

  /// 지금 메모를 쓰는 중인지
  final bool writing;

  /// 친구가 보고 있는 문단 번호(paragraph order)
  final int position;
  factory RoomPresence.fromJson(Map<String, dynamic> json) => RoomPresence(
    userId: (json['userId'] as num).toInt(),
    bookId: (json['bookId'] as num).toInt(),
    position: (json['position'] as num?)?.toInt() ?? 0,
    writing: json['writing'] == true,
  );
}

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

  /// Authenticated user's rooms only. Unlike [list], this never includes a
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

  Future<ReadingRoomJoinResult> join(
      String code, {
        String? password,
        String? roomNickname,
      }) async {
    final inviteCode = normalizeInviteCode(code);

    try {
      final response = await _api.post<ReadingRoomJoinResult>(
        '/api/reading-rooms/join-by-code',
        body: {
          'inviteCode': inviteCode,
          if (password?.isNotEmpty == true) 'password': password,
          if (roomNickname?.trim().isNotEmpty == true)
            'roomNickname': roomNickname!.trim(),
        },
        parse: (json) =>
            ReadingRoomJoinResult.fromJson(json as Map<String, dynamic>),
      );
      return response.data!;
    } catch (_) {
      rethrow;
    }
  }

  /// Membership and its profile are committed together by the server.
  Future<ReadingRoomJoinResult> joinWithProfile({
    required String code,
    required String roomNickname,
    String? password,
    Uint8List? bytes,
    String? filename,
    String? contentType,
  }) async => (await _api.uploadFile<ReadingRoomJoinResult>(
    '/api/reading-rooms/join-with-profile',
    method: 'POST',
    fields: {
      'inviteCode': normalizeInviteCode(code),
      'roomNickname': roomNickname.trim(),
      if (password?.isNotEmpty == true) 'password': password!,
    },
    fieldName: 'profileImage',
    bytes: bytes,
    filename: filename ?? 'profile.jpg',
    contentType: contentType ?? 'image/jpeg',
    parse: (json) => ReadingRoomJoinResult.fromJson(json as Map<String, dynamic>),
  )).data!;

  Future<InviteCodeValidation> validateInviteCode(String code) async =>
      (await _api.post<InviteCodeValidation>(
        '/api/reading-rooms/invite-codes/validate',
        body: {'inviteCode': normalizeInviteCode(code)},
        parse: (json) =>
            InviteCodeValidation.fromJson(json as Map<String, dynamic>),
      )).data!;

  /// Codes are displayed as XXXX-XXXX, but accepting copied values without a
  /// hyphen or with whitespace avoids making presentation part of the API
  /// contract. The server applies the identical canonical form.
  static String normalizeInviteCode(String value) {
    final compact = value
        .trim()
        .replaceAll(RegExp(r'[\s\u00A0\u2000-\u200B\u202F\u205F\u3000-]+'), '')
        .toUpperCase();

    return compact.length == 8
        ? '${compact.substring(0, 4)}-${compact.substring(4)}'
        : compact;
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

  Future<void> updateMyMemoColor(int roomId, String color) async {
    await _api.patch<Map<String, dynamic>>(
      '/api/reading-rooms/$roomId/shared-notes/my-color',
      body: {'highlightColor': color},
      parse: (json) => json as Map<String, dynamic>,
    );
  }

  Future<List<SharedRoomNote>> sharedNotes(int roomId, {int? bookId, bool reader = false}) async =>
      (await _api.get<List<SharedRoomNote>>(
        '/api/reading-rooms/$roomId/shared-notes',
        query: {if (bookId != null) 'bookId': '$bookId', if (reader) 'reader': 'true'},
        parse: (json) => (json as List)
            .map((e) => SharedRoomNote.fromJson(e as Map<String, dynamic>))
            .toList(),
      )).data ??
          const [];

  Future<SharedRoomNote> revealSharedNote(int roomId, int noteId) async =>
      (await _api.post<SharedRoomNote>(
        '/api/reading-rooms/$roomId/shared-notes/$noteId/reveal',
        parse: (json) => SharedRoomNote.fromJson({...(json as Map<String, dynamic>), 'explicitlyRevealed': true}),
      )).data!;

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

  Future<SharedRoomNote> updateSharedNote(
      int roomId,
      int noteId,
      Map<String, dynamic> body,
      ) async => (await _api.patch<SharedRoomNote>(
    '/api/reading-rooms/$roomId/shared-notes/$noteId',
    body: body,
    parse: (json) => SharedRoomNote.fromJson(json as Map<String, dynamic>),
  )).data!;

  Future<List<SharedRoomNoteComment>> sharedNoteComments(
      int roomId,
      int noteId, {bool revealed = false}
      ) async =>
      (await _api.get<List<SharedRoomNoteComment>>(
        '/api/reading-rooms/$roomId/shared-notes/$noteId/comments',
        query: {if (revealed) 'revealed': 'true'},
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
      String content, {bool revealed = false}
      ) async => (await _api.post<SharedRoomNoteComment>(
    '/api/reading-rooms/$roomId/shared-notes/$noteId/comments?revealed=$revealed',
    body: {'content': content.trim()},
    parse: (json) =>
        SharedRoomNoteComment.fromJson(json as Map<String, dynamic>),
  )).data!;

  Future<SharedRoomNoteComment> updateSharedNoteComment(
      int roomId,
      int noteId,
      int commentId,
      String content, {bool revealed = false}
      ) async => (await _api.patch<SharedRoomNoteComment>(
    '/api/reading-rooms/$roomId/shared-notes/$noteId/comments/$commentId?revealed=$revealed',
    body: {'content': content.trim()},
    parse: (json) =>
        SharedRoomNoteComment.fromJson(json as Map<String, dynamic>),
  )).data!;

  Future<void> deleteSharedNoteComment(int roomId, int noteId, int commentId, {bool revealed = false}) =>
      _api.delete(
        '/api/reading-rooms/$roomId/shared-notes/$noteId/comments/$commentId',
        query: {if (revealed) 'revealed': 'true'},
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

  /// This intentionally has its own endpoint so the active reader can change
  /// only the room spoiler policy without resubmitting stale room metadata.
  Future<ReadingRoom> updateSpoilerLock(int roomId, bool enabled) async =>
      (await _api.patch<ReadingRoom>(
        '/api/reading-rooms/$roomId/spoiler-lock',
        body: {'enabled': enabled},
        parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
      )).data!;

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

  Future<List<RoomParticipantProgress>> participantProgress(
      int roomId,
      int bookId,
      ) async =>
      (await _api.get<List<RoomParticipantProgress>>(
        '/api/reading-rooms/$roomId/books/$bookId/progress/participants',
        parse: (json) => (json as List)
            .map(
              (value) => RoomParticipantProgress.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
            .toList(),
      )).data ??
          const [];

  Future<RoomReadingProgress> myProgress(int roomId, int bookId) async =>
      (await _api.get<RoomReadingProgress>(
        '/api/reading-rooms/$roomId/books/$bookId/progress/me',
        parse: (json) =>
            RoomReadingProgress.fromJson(json as Map<String, dynamic>),
      )).data!;

  /// 책 화면이 열려 있는 동안 주기적으로 호출: "나 지금 여기 읽는 중"
  Future<void> sendPresence(int roomId, int bookId, int position,
      {bool writing = false}) async {
    await _api.post<Object>(
      '/api/reading-rooms/$roomId/presence',
      body: {
        'bookId': bookId,
        'position': position < 0 ? 0 : position,
        'writing': writing,
      },
    );
  }

  /// 책 화면을 닫을 때 호출 (못 불러도 35초 뒤 저절로 사라진다)
  Future<void> clearPresence(int roomId) =>
      _api.delete('/api/reading-rooms/$roomId/presence');

  /// 지금 읽는 중인 사람들. [bookId] 를 주면 그 책을 읽는 사람만.
  Future<List<RoomPresence>> presence(int roomId, {int? bookId}) async =>
      (await _api.get<List<RoomPresence>>(
        '/api/reading-rooms/$roomId/presence',
        query: {if (bookId != null) 'bookId': '$bookId'},
        parse: (json) => (json as List<dynamic>)
            .map((item) => RoomPresence.fromJson(item as Map<String, dynamic>))
            .toList(),
      )).data ??
          const [];

  Future<void> saveProgress(
      int roomId,
      int bookId, {
        required int progressPercent,
        required int lastReadPosition,
      }) async {
    await _api.post<Object>(
      '/api/reading-rooms/$roomId/books/$bookId/progress',
      body: {
        'progressPercent': progressPercent.clamp(0, 100),
        'lastReadPosition': lastReadPosition < 0 ? 0 : lastReadPosition,
      },
    );
  }

  Future<void> kick(int roomId, int memberId) =>
      _api.delete('/api/reading-rooms/$roomId/members/$memberId');

  Future<void> delete(int roomId) => _api.delete('/api/reading-rooms/$roomId');

  Future<ReadingRoom> uploadMyRoomProfileImage(
      int roomId, {
        required Uint8List bytes,
        required String filename,
        required String contentType,
      }) async => (await _api.uploadFile<ReadingRoom>(
    '/api/reading-rooms/$roomId/members/me/profile-image',
    method: 'PUT',
    fieldName: 'profileImage',
    bytes: bytes,
    filename: filename,
    contentType: contentType,
    parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
  )).data!;

  Future<ReadingRoom> deleteMyRoomProfileImage(int roomId) async =>
      (await _api.delete<ReadingRoom>(
        '/api/reading-rooms/$roomId/members/me/profile-image',
        parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
      )).data!;

  Future<ReadingRoom> uploadCoverImage(
      int roomId, {
        required Uint8List bytes,
        required String filename,
        required String contentType,
      }) async => (await _api.uploadFile<ReadingRoom>(
    '/api/reading-rooms/$roomId/cover-image',
    method: 'PUT',
    fieldName: 'coverImage',
    bytes: bytes,
    filename: filename,
    contentType: contentType,
    parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
  )).data!;

  Future<void> deleteCoverImage(int roomId) =>
      _api.delete('/api/reading-rooms/$roomId/cover-image');

  Future<ReadingRoom> updateMyRoomNickname(
      int roomId,
      String roomNickname,
      ) async => (await _api.patch<ReadingRoom>(
    '/api/reading-rooms/$roomId/members/me',
    body: {'roomNickname': roomNickname.trim()},
    parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
  )).data!;

  Future<ReadingRoom> addBook(int roomId, int bookId) async =>
      (await _api.post<ReadingRoom>(
        '/api/reading-rooms/$roomId/books?bookId=$bookId',
        parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
      )).data!;
  Future<ReadingRoom> removeBook(int roomId, int bookId) async =>
      (await _api.delete<ReadingRoom>(
        '/api/reading-rooms/$roomId/books/$bookId',
        parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
      )).data!;
  Future<ReadingRoom> moveBook(int roomId, int bookId, int order) async =>
      (await _api.patch<ReadingRoom>(
        '/api/reading-rooms/$roomId/books/$bookId/order',
        body: {'order': order},
        parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
      )).data!;
  Future<ReadingRoom> setCurrentBook(int roomId, int bookId) async =>
      (await _api.put<ReadingRoom>(
        '/api/reading-rooms/$roomId/current-book/$bookId',
        parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
      )).data!;
  Future<ReadingRoom> setPassword(int roomId, String? password) async =>
      (await _api.put<ReadingRoom>(
        '/api/reading-rooms/$roomId/password',
        body: {'password': password},
        parse: (json) => ReadingRoom.fromJson(json as Map<String, dynamic>),
      )).data!;
}