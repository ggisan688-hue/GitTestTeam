import '../core/api_client.dart';


class AiReadingFriend {
  const AiReadingFriend({
    required this.id,
    required this.name,
    required this.isDefault,
    this.persona,
    this.inputAge,
    this.inputGender,
    this.inputRelationship,
    this.inputPersonality,
    this.inputSpeechStyle,
    this.inputTraits,
  });

  final int id;
  final String name;
  final bool isDefault;
  final String? persona;

  // 사용자가 직접 입력한 정보
  final String? inputAge;
  final String? inputGender;
  final String? inputRelationship;
  final String? inputPersonality;
  final String? inputSpeechStyle;
  final String? inputTraits;

  factory AiReadingFriend.fromJson(Map<String, dynamic> json) {
    return AiReadingFriend(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
      isDefault: json['isDefault'] == true,
      persona: json['persona'] as String?,

      // DB에 저장된 사용자 입력값
      inputAge: json['inputAge']?.toString(),
      inputGender: json['inputGender']?.toString(),
      inputRelationship: json['inputRelationship']?.toString(),
      inputPersonality: json['inputPersonality']?.toString(),
      inputSpeechStyle: json['inputSpeechStyle']?.toString(),
      inputTraits: json['inputTraits']?.toString(),
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
    this.highlightColor,
  });

  final int id;
  final int friendId;
  final int bookId;
  final int paragraphOrder;
  final int startOffset;
  final int endOffset;
  final String selectedText;
  final String content;
  final String? highlightColor;

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
      highlightColor: json['highlightColor']?.toString(),
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
          .map(
            (item) => AiReadingFriend.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
    return res.data ?? const [];
  }


  Future<AiReadingFriend> createFriend({
    required String name,
    String? age,
    String? gender,
    String? relationship,
    String? personality,
    String? speechStyle,
    String? traits,
  }) async {
    final res = await _api.post<AiReadingFriend>(
      '/api/ai-reading-friends',
      body: {
        'name': name.trim(),
        'age': age?.trim(),
        'gender': gender?.trim(),
        'relationship': relationship?.trim(),
        'personality': personality?.trim(),
        'speechStyle': speechStyle?.trim(),
        'traits': traits?.trim(),
      },
      parse: (json) =>
          AiReadingFriend.fromJson(Map<String, dynamic>.from(json as Map)),
      timeout: const Duration(seconds: 120),
    );

    return res.data!;
  }



  // 사용자가 생성한 AI 독서친구 수정
  Future<AiReadingFriend> updateFriend({
    required int friendId,
    required String name,
    String? age,
    String? gender,
    String? relationship,
    String? personality,
    String? speechStyle,
    String? traits,
  }) async {
    final res = await _api.put<AiReadingFriend>(
      '/api/ai-reading-friends/$friendId',
      body: {
        'name': name.trim(),
        'age': age?.trim(),
        'gender': gender?.trim(),
        'relationship': relationship?.trim(),
        'personality': personality?.trim(),
        'speechStyle': speechStyle?.trim(),
        'traits': traits?.trim(),
      },
      parse: (json) => AiReadingFriend.fromJson(
        Map<String, dynamic>.from(json as Map),
      ),
    );

    return res.data!;
  }


  Future<void> deleteFriend(int friendId) =>
      _api.delete('/api/ai-reading-friends/$friendId');


  // AI 친구별 형광펜 색상 조회
  Future<String> getFriendHighlightColor(int friendId) async {
    final res = await _api.get<String>(
      '/api/ai-reading-friends/$friendId/highlight-color',
      parse: (json) =>
      (json as Map)['highlightColor']?.toString() ?? 'YELLOW',
    );

    return res.data ?? 'YELLOW';
  }

  // AI 친구별 형광펜 색상 저장
  Future<String> saveFriendHighlightColor({
    required int friendId,
    required String color,
  }) async {
    final res = await _api.put<String>(
      '/api/ai-reading-friends/$friendId/highlight-color',
      body: {'highlightColor': color},
      parse: (json) =>
      (json as Map)['highlightColor']?.toString() ?? 'YELLOW',
    );

    return res.data ?? 'YELLOW';
  }


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
      timeout: const Duration(seconds: 120),
    );

    return res.data ?? const <AiReadingNote>[];
  }

  Future<Map<String, dynamic>> getReadingProgress({
    required int bookId,
    required int friendId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/books/$bookId/ai-reading-friends/$friendId/progress',
      parse: (data) => Map<String, dynamic>.from(data as Map),
    );

    return res.data ?? <String, dynamic>{};
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

  /// 현재 계정이 이 책에서 선택한 AI 친구 목록 조회
  Future<List<int>> getSelectedFriendIds({required int bookId}) async {
    final res = await _api.get<List<int>>(
      '/api/books/$bookId/ai-reading-friend-selections',
      parse: (json) =>
          (json as List<dynamic>).map((id) => (id as num).toInt()).toList(),
    );

    return res.data ?? const <int>[];
  }

  /// 현재 계정이 이 책에서 선택한 AI 친구 목록 전체 저장
  Future<List<int>> saveSelectedFriendIds({
    required int bookId,
    required Set<int> friendIds,
  }) async {
    final res = await _api.put<List<int>>(
      '/api/books/$bookId/ai-reading-friend-selections',
      body: {'friendIds': friendIds.toList()},
      parse: (json) =>
          (json as List<dynamic>).map((id) => (id as num).toInt()).toList(),
    );

    return res.data ?? const <int>[];
  }

  List<AiReadingNote> _parseNotes(Object? json) {
    final list = json as List<dynamic>;

    return list
        .map(
          (item) =>
              AiReadingNote.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }
}
