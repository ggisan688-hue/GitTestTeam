import '../core/api_client.dart';
import '../model/ai_answer.dart';

/// AI 보조 탭. 값은 Spring 의 AiAssistRequest.mode 와 동일
enum AiMode {
  explain('explain', '문장 설명'),
  summary('summary', '구간 요약'),
  relation('relation', '인물관계도'),
  taste('taste', '취향 분석');

  const AiMode(this.value, this.label);
  final String value;
  final String label;
}

/// Spring /api/ai/* 호출 (Spring 이 FastAPI 로 넘김)
class AiRepository {
  AiRepository(this._api);

  final ApiClient _api;

  /// 자유 질문
  Future<AiAnswer> ask(String question) async {
    final res = await _api.post<AiAnswer>(
      '/api/ai/ask',
      body: {'question': question},
      parse: (json) => AiAnswer.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }

  /// 독서 보조: mode 에 맞는 프롬프트는 Spring 이 조립
  Future<AiAnswer> assist({
    required AiMode mode,
    required int bookId,
    required int chapter,
    int? lineNo,
  }) => _assist({
    'mode': mode.value,
    'bookId': bookId,
    'chapter': chapter,
    'lineNo': lineNo,
  });

  /// 선택 문장을 두고 자유롭게 물어보기
  Future<AiAnswer> chat({
    required int bookId,
    required int chapter,
    int? lineNo,
    required String question,
  }) => _assist({
    'mode': 'chat',
    'bookId': bookId,
    'chapter': chapter,
    'lineNo': lineNo,
    'question': question,
  });

  Future<AiAnswer> _assist(Map<String, dynamic> body) async {
    final res = await _api.post<AiAnswer>(
      '/api/ai/assist',
      body: body,
      parse: (json) => AiAnswer.fromJson(json as Map<String, dynamic>),
    );
    return res.data!;
  }
}
