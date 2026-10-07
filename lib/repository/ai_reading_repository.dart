import '../core/api_client.dart';

class AiReadingFriend {
  const AiReadingFriend({
    required this.id,
    required this.name,
    required this.isDefault,
    this.persona,
  });

  final int id;
  final String name;
  final bool isDefault;
  final String? persona;

  factory AiReadingFriend.fromJson(Map<String, dynamic> json) {
    return AiReadingFriend(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
      isDefault: json['isDefault'] == true,
      persona: json['persona'] as String?,
    );
  }
}

class AiReadingNote {
  const AiReadingNote({
    required this.id,
    required this.friendId,
    required this.bookId,
    required this.paragraphOrder,
    required this.startOffset,
    required this.endOffset,
    required this.selectedText,
    required this.content,
  });

  final int id;
  final int friendId;
  final int bookId;
  final int paragraphOrder;
  final int startOffset;
  final int endOffset;
  final String selectedText;
  final String content;

  factory AiReadingNote.fromJson(Map<String, dynamic> json) {
    return AiReadingNote(
      id: (json['id'] as num).toInt(),
      friendId: (json['friendId'] as num).toInt(),
      bookId: (json['bookId'] as num).toInt(),
      paragraphOrder: (json['paragraphOrder'] as num).toInt(),
      startOffset: (json['startOffset'] as num).toInt(),
      endOffset: (json['endOffset'] as num).toInt(),
      selectedText: json['selectedText']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
    );
  }
}

class AiReadingRepository {
  AiReadingRepository(this._api);

  final ApiClient _api;

  /// 서버에 등록된 기본 AI 독서친구 목록
  Future<List<AiReadingFriend>> getDefaultFriends() async {
    final res = await _api.get<List<AiReadingFriend>>(
      '/api/ai-reading-friends/defaults',
      parse: (json) {
        final list = json as List<dynamic>;

        return list
            .map(
              (item) => AiReadingFriend.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
            .toList();
      },
    );

    return res.data ?? const <AiReadingFriend>[];
  }

  Future<List<AiReadingFriend>> getMyFriends() async {
    final res = await _api.get<List<AiReadingFriend>>(
      '/api/ai-reading-friends',
      parse: (json) => (json as List)
          .map((item) => AiReadingFriend.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
    return res.data ?? const [];
  }

  Future<AiReadingFriend> createFriend({required String name, required String persona}) async {
    final res = await _api.post<AiReadingFriend>(
      '/api/ai-reading-friends',
      body: {'name': name.trim(), 'persona': persona.trim()},
      parse: (json) => AiReadingFriend.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }

  Future<void> deleteFriend(int friendId) =>
      _api.delete('/api/ai-reading-friends/$friendId');

  /// 해당 책을 AI 친구가 읽고 메모를 생성한다.
  ///
  /// 백엔드에서 이미 생성된 메모가 있으면
  /// 기존 메모를 그대로 반환한다.
  Future<List<AiReadingNote>> generateNotes({
    required int bookId,
    required int friendId,
  }) async {
    final res = await _api.post<List<AiReadingNote>>(
      '/api/books/$bookId/ai-reading-friends/$friendId/generate',
      body: const {},
      parse: _parseNotes,
    );

    return res.data ?? const <AiReadingNote>[];
  }

  /// 이미 생성되어 있는 AI 독서 메모 조회
  Future<List<AiReadingNote>> getNotes({
    required int bookId,
    required int friendId,
  }) async {
    final res = await _api.get<List<AiReadingNote>>(
      '/api/books/$bookId/ai-reading-friends/$friendId/notes',
      parse: _parseNotes,
    );

    return res.data ?? const <AiReadingNote>[];
  }

  List<AiReadingNote> _parseNotes(Object? json) {
    final list = json as List<dynamic>;

    return list
        .map(
          (item) => AiReadingNote.fromJson(
        Map<String, dynamic>.from(item as Map),
      ),
    )
        .toList();
  }
}
