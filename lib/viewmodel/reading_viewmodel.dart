import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../model/book.dart';
import '../model/ink.dart';
import '../model/memo.dart';
import '../model/progress.dart';
import '../repository/book_repository.dart';

/// 읽기 화면 상태. 장별 본문·내 메모·친구 메모를 캐시하고 앞뒤 장을 미리 받는다.
/// 친구 메모 = 이 책에서 나에게 공개한 친구 + 내 AI 독서 친구. 스포일러는 서버가 가림.
class ReadingViewModel extends ChangeNotifier {
  ReadingViewModel(this._books);

  final BookRepository _books;

  Book? book;
  int chapterNo = 1;

  final Map<int, Chapter> _chapters = {};
  final Map<int, List<Memo>> _memos = {};
  final Map<int, List<Memo>> _shared = {};
  final Set<int> _loading = {};
  final Map<int, String> _errors = {};

  Progress progress = const Progress(chapter: 1, lineNo: 0);
  int? selectedLine;
  bool complete = false; // 완독 여부 (리포트 버튼)

  // ---------- 현재 장 ----------
  int get bookId => book?.id ?? 1;
  int get chapterCount => book?.chapterCount ?? 1;
  String get bookTitle => book?.title ?? '';
  bool get hasPrev => chapterNo > 1;
  bool get hasNext => chapterNo < chapterCount;

  Chapter? get chapter => _chapters[chapterNo];
  List<Memo> get memos =>
      (_memos[chapterNo] ?? const []).where((m) => !m.isInk).toList();
  List<Memo> get sharedMemos =>
      (_shared[chapterNo] ?? const []).where((m) => !m.isInk).toList();
  List<Memo> get myInk => (_memos[chapterNo] ?? const [])
      .where((m) => m.isInk && m.ink != null)
      .toList();
  bool get isLoading => _loading.contains(chapterNo);
  String? get errorMessage => _errors[chapterNo];
  int get maskedSharedCount => (_shared[chapterNo] ?? const [])
      .where((m) => !m.mine && m.spoiler)
      .length;

  int get readLine {
    if (chapterNo == progress.chapter) return progress.lineNo;
    if (chapterNo < progress.chapter) return chapter?.lines.length ?? 0;
    return 0;
  }

  Line? get selected => selectedLine == null
      ? null
      : chapter?.lines.where((l) => l.lineNo == selectedLine).firstOrNull;
  List<Memo> memosOf(int lineNo) =>
      memos.where((m) => m.lineNo == lineNo).toList();
  List<Memo> sharedOf(int lineNo) =>
      sharedMemos.where((m) => m.lineNo == lineNo && !m.mine).toList();
  bool hasMemo(int lineNo) => memos.any((m) => m.lineNo == lineNo);
  bool isSpoiler(int lineNo) => progress.isAhead(chapterNo, lineNo);

  // ---------- 펜 도구 ----------
  bool penMode = false;
  bool eraser = false;
  int penColor = 0xFFB4652A;
  double penWidth = 2.5;
  bool showMyInk = true;
  bool showSharedInk = true;

  /// 아직 저장 안 된 이번 펜 세션의 획 (장 번호별)
  final Map<int, List<InkStroke>> _session = {};
  Timer? _sessionTimer;

  void setPenMode(bool v) {
    penMode = v;
    if (!v) {
      eraser = false;
      flushInkSession(); // 펜을 놓으면 세션 저장
    }
    notifyListeners();
  }

  void setEraser(bool v) {
    eraser = v;
    notifyListeners();
  }

  void setPenColor(int c) {
    penColor = c;
    eraser = false;
    notifyListeners();
  }

  void setPenWidth(double w) {
    penWidth = w;
    notifyListeners();
  }

  void toggleMyInk() {
    showMyInk = !showMyInk;
    notifyListeners();
  }

  void toggleSharedInk() {
    showSharedInk = !showSharedInk;
    notifyListeners();
  }

  // ---------- 장 단위 조회 (페이저) ----------
  Chapter? chapterAt(int n) => _chapters[n];
  bool isChapterLoading(int n) => _loading.contains(n);
  String? errorAt(int n) => _errors[n];
  String memoLinesKey(int n) =>
      _key((_memos[n] ?? const []).where((m) => !m.isInk).map((m) => m.lineNo));
  String sharedLinesKey(int n) =>
      ((_shared[n] ?? const [])
              .where((m) => !m.mine && !m.isInk)
              .map((m) => m.lineNo)
              .toList()
            ..sort())
          .join(',');
  String _key(Iterable<int> lines) =>
      (lines.toSet().toList()..sort()).join(',');

  /// 장 n 의 손글씨 메모 (저장된 것)
  List<Memo> inkOf(int n) => [
    if (showMyInk)
      ...(_memos[n] ?? const []).where((m) => m.isInk && m.ink != null),
    if (showSharedInk)
      ...(_shared[n] ?? const []).where(
        (m) => m.isInk && !m.mine && m.ink != null,
      ),
  ];

  /// 장 n 의 아직 저장 안 된 세션 획
  List<InkStroke> sessionOf(int n) => _session[n] ?? const [];
  String inkKey(int n) =>
      '${showMyInk ? 1 : 0}${showSharedInk ? 1 : 0}:${inkOf(n).map((m) => m.id).join(',')}:${sessionOf(n).length}';

  // ---------- 책 열기 / 장 이동 ----------
  Future<void> open(Book b) async {
    await flushInkSession();
    book = b;
    _chapters.clear();
    _memos.clear();
    _shared.clear();
    _loading.clear();
    _errors.clear();
    _session.clear();
    selectedLine = null;
    complete = false;
    progress = const Progress(chapter: 1, lineNo: 0);
    chapterNo = 1;
    notifyListeners();
    await Future.wait([_loadProgress(b.id), _loadComplete(b.id)]);
    chapterNo = progress.chapter.clamp(1, chapterCount);
    notifyListeners();
    await _ensureAround(chapterNo);
  }

  Future<void> goTo(int n) async {
    if (n < 1 || n > chapterCount || n == chapterNo) return;
    await flushInkSession();
    chapterNo = n;
    selectedLine = null;
    notifyListeners();
    await _ensureAround(n);
    await refreshShared(n);
  }

  Future<void> prevChapter() => goTo(chapterNo - 1);
  Future<void> nextChapter() => goTo(chapterNo + 1);

  Future<void> reload() {
    _chapters.remove(chapterNo);
    _memos.remove(chapterNo);
    _shared.remove(chapterNo);
    _errors.remove(chapterNo);
    return ensureChapter(chapterNo);
  }

  Future<void> _ensureAround(int n) async {
    await ensureChapter(n);
    if (n + 1 <= chapterCount) ensureChapter(n + 1);
    if (n - 1 >= 1) ensureChapter(n - 1);
  }

  Future<void> ensureChapter(int n) async {
    if (_chapters.containsKey(n) || _loading.contains(n)) return;
    _loading.add(n);
    _errors.remove(n);
    notifyListeners();
    try {
      final id = bookId;
      final c = await _books.chapter(id, n);
      final m = await _books.memos(id, chapter: n);
      final s = await _books.friendMemos(id, n);
      if (book?.id != id) return;
      _chapters[n] = c;
      _memos[n] = m;
      _shared[n] = s;
    } on ApiException catch (e) {
      _errors[n] = e.message;
    } finally {
      _loading.remove(n);
      notifyListeners();
    }
  }

  Future<void> refreshShared(int n) async {
    try {
      _shared[n] = await _books.friendMemos(bookId, n);
      notifyListeners();
    } on ApiException catch (e) {
      _errors[n] = e.message;
      notifyListeners();
    }
  }

  /// AI 캐릭터가 메모를 남길 시간을 준 뒤 다시 받기 (장 진입 후 몇 초 뒤)
  Future<void> pollSharedLater(int n, {int seconds = 8}) async {
    await Future.delayed(Duration(seconds: seconds));
    if (chapterNo == n && book != null) await refreshShared(n);
  }

  // ---------- 읽는 지점 / 완독 ----------
  Future<void> _loadProgress(int id) async {
    try {
      progress = await _books.progress(id);
    } on ApiException catch (_) {}
  }

  Future<void> _loadComplete(int id) async {
    try {
      complete = await _books.isComplete(id);
    } on ApiException catch (_) {}
  }

  Future<void> selectLine(int lineNo) async {
    if (selectedLine == lineNo) {
      selectedLine = null;
      notifyListeners();
      return;
    }
    selectedLine = lineNo;
    progress = Progress(chapter: chapterNo, lineNo: lineNo);
    notifyListeners();
    try {
      progress = await _books.updateProgress(
        bookId,
        chapter: chapterNo,
        lineNo: lineNo,
      );
      await refreshShared(chapterNo);
      if (!complete && chapterNo == chapterCount) await _loadComplete(bookId);
      notifyListeners();
    } on ApiException catch (e) {
      _errors[chapterNo] = e.message;
      notifyListeners();
    }
  }

  // ---------- 내 메모 ----------
  Future<bool> addMemo(int lineNo, String text) async {
    if (text.trim().isEmpty) return false;
    try {
      final memo = await _books.addMemo(
        bookId,
        chapter: chapterNo,
        lineNo: lineNo,
        text: text,
      );
      _memos[chapterNo] = [...(_memos[chapterNo] ?? const []), memo]
        ..sort(
          (a, b) => a.lineNo != b.lineNo
              ? a.lineNo - b.lineNo
              : a.createdAt.compareTo(b.createdAt),
        );
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errors[chapterNo] = e.message;
      notifyListeners();
      return false;
    }
  }

  /// 댓글 수 갱신 (댓글 시트에서 돌아올 때)
  void updateCommentCount(int memoId, int count) {
    for (final map in [_memos, _shared]) {
      for (final entry in map.entries.toList()) {
        final i = entry.value.indexWhere((m) => m.id == memoId);
        if (i >= 0) {
          final list = [...entry.value];
          list[i] = list[i].copyWith(commentCount: count);
          map[entry.key] = list;
        }
      }
    }
    notifyListeners();
  }

  // ---------- 손글씨 (세션 단위 저장) ----------
  /// 획 하나 추가. 2.5초 동안 새 획이 없으면 세션을 메모 하나로 저장
  void addStroke(InkStroke stroke, {required int chapter}) {
    (_session[chapter] ??= []).add(stroke);
    _sessionTimer?.cancel();
    _sessionTimer = Timer(
      const Duration(milliseconds: 2500),
      () => flushInkSession(chapter: chapter),
    );
    notifyListeners();
  }

  Future<void> flushInkSession({int? chapter}) async {
    _sessionTimer?.cancel();
    final targets = chapter == null ? _session.keys.toList() : [chapter];
    for (final ch in targets) {
      final strokes = _session.remove(ch);
      if (strokes == null || strokes.isEmpty) continue;
      try {
        final memo = await _books.addInk(
          bookId,
          chapter: ch,
          ink: InkMemo(strokes),
        );
        _memos[ch] = [...(_memos[ch] ?? const []), memo];
      } on ApiException catch (e) {
        _errors[ch] = e.message;
        (_session[ch] ??= []).insertAll(0, strokes); // 실패 시 세션에 되돌림
        _sessionTimer?.cancel();
        _sessionTimer = Timer(
          const Duration(seconds: 5),
          () => flushInkSession(chapter: ch),
        ); // 5초 뒤 재시도
      }
    }
    notifyListeners();
  }

  /// 저장된 손글씨 메모 삭제 (지우개)
  Future<void> removeInk(int memoId) async {
    final list = _memos[chapterNo];
    if (list == null) return;
    _memos[chapterNo] = list.where((m) => m.id != memoId).toList();
    notifyListeners();
    try {
      await _books.deleteMemo(bookId, memoId);
    } on ApiException catch (e) {
      _errors[chapterNo] = e.message;
      notifyListeners();
    }
  }

  /// 실행취소: 세션에 획이 있으면 마지막 획, 없으면 마지막 저장 손글씨 메모
  Future<void> undoInk() async {
    final s = _session[chapterNo];
    if (s != null && s.isNotEmpty) {
      s.removeLast();
      notifyListeners();
      return;
    }
    final mine = myInk;
    if (mine.isEmpty) return;
    await removeInk(mine.last.id);
  }

  bool get canUndoInk =>
      (_session[chapterNo]?.isNotEmpty ?? false) || myInk.isNotEmpty;

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }
}
