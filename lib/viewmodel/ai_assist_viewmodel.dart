import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../model/ai_answer.dart';
import '../repository/ai_repository.dart';

/// 자유 질문 한 턴 (질문 + 답변 or 에러)
class ChatTurn {
  ChatTurn(this.question);

  final String question;
  AiAnswer? answer;
  String? error;
}

/// AI 보조 화면 상태. 탭별 답변은 (문장, 탭) 단위로 캐시해서 탭을 오가도 다시 부르지 않음
class AiAssistViewModel extends ChangeNotifier {
  AiAssistViewModel(this._repository);

  final AiRepository _repository;

  int bookId = 1;
  int chapter = 1;
  int? lineNo;
  AiMode mode = AiMode.explain;

  final Map<String, AiAnswer> _cache = {};
  final Set<String> _loading = {};
  String? errorMessage;

  final List<ChatTurn> turns = [];
  bool isChatting = false;

  String _key(AiMode m) => '$bookId/$chapter/${m == AiMode.explain ? lineNo : '-'}/${m.value}';

  AiAnswer? get answer => _cache[_key(mode)];
  bool get isLoading => _loading.contains(_key(mode));

  /// 화면 진입 시 호출. 위치를 정하고 첫 탭을 바로 요청
  Future<void> open({required int bookId, required int chapter, int? lineNo, AiMode initial = AiMode.explain}) {
    this.bookId = bookId;
    this.chapter = chapter;
    this.lineNo = lineNo;
    turns.clear();
    return selectMode(initial);
  }

  Future<void> selectMode(AiMode m) async {
    mode = m;
    errorMessage = null;
    notifyListeners();

    final key = _key(m);
    if (_cache.containsKey(key) || _loading.contains(key)) return;
    if (m == AiMode.explain && lineNo == null) {
      errorMessage = '문장을 먼저 선택해주세요';
      notifyListeners();
      return;
    }

    _loading.add(key);
    notifyListeners();
    try {
      _cache[key] = await _repository.assist(mode: m, bookId: bookId, chapter: chapter, lineNo: lineNo);
    } on ApiException catch (e) {
      errorMessage = e.message;
    } finally {
      _loading.remove(key);
      notifyListeners();
    }
  }

  /// 현재 탭 답변을 지우고 다시 요청
  Future<void> refresh() {
    _cache.remove(_key(mode));
    return selectMode(mode);
  }

  Future<void> chat(String question) async {
    final q = question.trim();
    if (q.isEmpty || isChatting) return;
    final turn = ChatTurn(q);
    turns.add(turn);
    isChatting = true;
    notifyListeners();
    try {
      turn.answer = await _repository.chat(bookId: bookId, chapter: chapter, lineNo: lineNo, question: q);
    } on ApiException catch (e) {
      turn.error = e.message;
    } finally {
      isChatting = false;
      notifyListeners();
    }
  }
}
