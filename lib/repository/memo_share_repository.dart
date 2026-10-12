import '../core/api_client.dart';

/// 메모 원본의 위치
/// PERSONAL: 혼자읽기 메모
/// ROOM: 교환독서방 메모
enum MemoShareSource {
  personal,
  room,
}

/// 공유된 메모 정보
class MemoShareRecord {
  const MemoShareRecord({
    required this.shareId,
    required this.sourceType,
    required this.memoId,
    required this.bookId,
    required this.authorId,
    required this.content,
    required this.spoilerLocked,
    required this.mine,
  });

  final int shareId;
  final String sourceType;
  final int memoId;
  final int bookId;
  final int authorId;
  final String? content;
  final bool spoilerLocked;
  final bool mine;

  factory MemoShareRecord.fromJson(
      Map<String, dynamic> json,
      ) {
    return MemoShareRecord(
      shareId: (json['shareId'] as num).toInt(),
      sourceType: json['sourceType'] as String,
      memoId: (json['memoId'] as num).toInt(),
      bookId: (json['bookId'] as num).toInt(),
      authorId: (json['authorId'] as num).toInt(),
      content: json['content'] as String?,
      spoilerLocked: json['spoilerLocked'] == true,
      mine: json['mine'] == true,
    );
  }
}

/// 메모 공유 API
class MemoShareRepository {
  const MemoShareRepository(this._api);

  final ApiClient _api;

  /// 선택한 메모를 대상 독서방에 공유
  Future<MemoShareRecord> share({
    required int targetRoomId,
    required MemoShareSource source,
    required int memoId,
  }) async {
    final response = await _api.post<MemoShareRecord>(
      '/api/reading-rooms/$targetRoomId/memo-shares',
      body: {
        'sourceType':
        source == MemoShareSource.personal
            ? 'PERSONAL'
            : 'ROOM',
        'memoId': memoId,
      },
      parse: (json) => MemoShareRecord.fromJson(
        json as Map<String, dynamic>,
      ),
    );

    return response.data!;
  }

  /// 해당 독서방에 공유된 메모 목록
  Future<List<MemoShareRecord>> list({
    required int roomId,
    int? bookId,
  }) async {
    final response =
    await _api.get<List<MemoShareRecord>>(
      '/api/reading-rooms/$roomId/memo-shares',
      query: {
        if (bookId != null) 'bookId': '$bookId',
      },
      parse: (json) => (json as List<dynamic>)
          .map(
            (e) => MemoShareRecord.fromJson(
          e as Map<String, dynamic>,
        ),
      )
          .toList(),
    );

    return response.data ?? const [];
  }

  /// 특정 독서방에서만 공유 취소
  /// 원본 메모는 삭제하지 않음
  Future<void> revoke({
    required int roomId,
    required int shareId,
  }) async {
    await _api.delete<void>(
      '/api/reading-rooms/$roomId/memo-shares/$shareId',
    );
  }

  /// 기존 독서방 메모 + 공유받은 메모 통합 조회
  Future<List<Map<String, dynamic>>> feed({
    required int roomId,
    required int bookId,
  }) async {
    final response =
    await _api.get<List<Map<String, dynamic>>>(
      '/api/reading-rooms/$roomId/memo-shares/feed',
      query: {
        'bookId': '$bookId',
      },
      parse: (json) => (json as List<dynamic>)
          .map(
            (e) => e as Map<String, dynamic>,
      )
          .toList(),
    );

    return response.data ?? const [];
  }
}