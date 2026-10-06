import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../model/user_profile.dart';
import '../../repository/ridi_auth_repository.dart';
import '../../repository/user_profile_repository.dart';
import 'ridi_data.dart';

/// 책담의 메모리 저장소 — 모든 화면이 이 한 곳의 데이터를 보고 고친다 (Provider 로 주입, ridi_app.dart).
///
/// 지금은 서버·DB 없이 폰 메모리에만 있고, 앱을 끄면 시드(_seed) 상태로 돌아간다.
/// 서버 연결 시: 화면 코드는 그대로 두고 아래 메서드 "안쪽"만 API 호출로 바꾼다.
/// 메서드마다 적힌 `서버:` 가 docs/API_CONTRACT_RIDI.md 의 해당 API 다.
///
/// 구성
/// - 모델: RidiBook · RidiMember · RidiPersona · RidiRoom · RidiNote(형광펜·메모·책갈피) · RidiComment · RidiNotification
/// - 저장소 RidiStore: 계정 → 책 → 방 → AI 친구 → 독서노트 → 댓글 → 알림 → 설정 순
/// - 파일 끝 도우미: 문장·어절 꺼내기, "n분 전" 표시

// ---------------- 모델 ----------------
/// 책 한 권 + 내 읽기 상태(책장에 있는지 · 마지막 열람 · 페이지 · 가장 멀리 읽은 장).
/// 서버: Book + ShelfItem + progress (명세서 3-2)
class RidiBook {
  RidiBook({
    required this.id,
    required this.title,
    required this.author,
    required this.chapters,
    this.done = false,
    this.owned = false,
    this.lastOpened,
    this.page = 1,
    this.unread = 0,
    this.chapterReached = 0,
    this.readMinutes = 0,
  });

  final String id;
  final String title;
  final String author;
  final int chapters;
  final bool done;

  /// 내 책장에 담겨 있는지 (UC-08 도서 다운로드)
  bool owned;
  String? lastOpened;
  int page;
  int unread;

  /// 가장 멀리 읽은 장 (0부터). 방 메모 스포일러 잠금의 기준
  int chapterReached;

  /// 이 책을 읽은 시간(분, 누적) — 홈 "자주 읽는 책"
  int readMinutes;
}

/// 방 멤버 한 명 — 사람 또는 방 AI 친구(ai). owner = 방장
class RidiMember {
  const RidiMember(this.name, {this.ai = false, this.owner = false});
  final String name;
  final bool ai;
  final bool owner;
}

/// AI 독서 친구 캐릭터. tone = 말투, intro = 한 줄 성격, sample = 카드에 보이는 예시 대사.
/// 서버: GET /api/ai/personas, 새로 만들기 POST /api/ai/personas
class RidiPersona {
  const RidiPersona({
    required this.id,
    required this.name,
    required this.tone,
    required this.intro,
    required this.sample,
  });
  final String id;
  final String name;
  final String tone;
  final String intro;
  final String sample;
}

/// 교환독서 방. code(RM-XXXX)로 입장, 책 여러 권, 방마다 AI 친구 하나(personaId).
/// spoilerLock = 내가 읽은 장보다 뒤의 남 메모 가리기, maxMembers = 사람 정원(AI 제외, 2~50).
/// password = 숫자 4자리 (null 이면 코드만으로 입장), blocked = 방장이 차단한 사람(다시 못 들어옴).
/// 서버: Room JSON (명세서 3-3)
class RidiRoom {
  RidiRoom({
    required this.id,
    required this.name,
    required this.code,
    required this.bookIds,
    required this.members,
    this.personaId,
    this.lastBookId,
    this.spoilerLock = true,
    this.maxMembers = 6,
    this.password,
    List<String>? blocked,
  }) : blocked = blocked ?? [];

  final String id;
  String name;
  final String code;
  List<String> bookIds;
  List<RidiMember> members;
  String? personaId;
  String? lastBookId;
  bool spoilerLock;
  int maxMembers;
  String? password;
  List<String> blocked;

  int get humanCount => members.where((m) => !m.ai).length;
}

/// 방 정원 범위 (RIDI_ROOM_CREATE_01 · RIDI_ROOMS_02 의 + / − 버튼)
const kRoomMinMembers = 2;
const kRoomMaxMembers = 50;

/// 코드로 입장한 결과 — 코드 입장 화면이 문구를 고른다.
/// 서버: POST /api/rooms/join → 200 / 404 ROOM_NOT_FOUND / 409 ROOM_FULL / 403 ROOM_BLOCKED / 403 WRONG_PASSWORD
enum JoinResult { ok, notFound, full, blocked, wrongPassword }

/// 독서노트 기록 종류 — 형광펜(메모는 형광펜에 붙는다) / 책갈피
enum NoteKind { highlight, bookmark }

/// 펜 모양 — 형광펜(배경색) / 밑줄(색 줄). 색은 둘 다 colorIndex 를 쓴다 (RIDI_READER_03)
enum PenStyle { highlight, underline }

/// 형광펜·메모·책갈피 한 건.
/// 위치 = 장(chapter) + 문장(line) + 어절 범위(wordFrom~wordTo). page 는 표시용이라 서버에 저장하지 않는다
/// (글자 크기·2단/1단에 따라 바뀜). roomIds 에 든 방들의 멤버에게 공유된다 (여러 방 가능, 비면 나만 보기).
/// 서버: Memo JSON — noteType · penStyle · color · phrase · wordFrom · wordTo · roomIds (명세서 3-4)
class RidiNote {
  RidiNote({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.chapter,
    required this.page,
    required this.line,
    required this.phrase,
    this.memo = '',
    this.colorIndex = 4,
    required this.createdAt,
    List<String>? roomIds,
    this.penStyle = PenStyle.highlight,
    this.mine = true,
    this.author = '',
    this.ai = false,
    this.wordFrom,
    this.wordTo,
  }) : roomIds = roomIds ?? [];

  final String id;
  final String bookId;
  final NoteKind kind;
  final int chapter;
  final int page;

  /// 장 안에서 몇 번째 문장인지
  final int line;

  /// 형광펜이 걸린 문구 (책갈피는 장 제목)
  final String phrase;
  String memo;
  int colorIndex;
  final DateTime createdAt;

  /// 공유한 방들. 비어 있으면 나만 보기 (책갈피는 항상 빈 목록)
  List<String> roomIds;

  /// 형광펜 / 밑줄
  PenStyle penStyle;

  /// 내가 쓴 것인지. 남의 것이면 [author] 가 이름
  final bool mine;
  final String author;

  /// 방 AI 독서 친구가 남긴 메모
  final bool ai;

  /// 형광펜이 걸린 어절 범위 (문장을 공백으로 나눈 번호, 0부터). null 이면 마지막 어절
  final int? wordFrom;
  final int? wordTo;

  int wordStart(int wordCount) =>
      (wordFrom ?? wordCount - 1).clamp(0, wordCount - 1);
  int wordEnd(int wordCount) => (wordTo ?? wordFrom ?? wordCount - 1).clamp(
    wordStart(wordCount),
    wordCount - 1,
  );

  String get dateLabel =>
      '${createdAt.year}.${createdAt.month.toString().padLeft(2, '0')}.${createdAt.day.toString().padLeft(2, '0')}.';
}

/// 방 메모에 달린 댓글
class RidiComment {
  RidiComment({
    required this.id,
    required this.noteId,
    required this.text,
    required this.createdAt,
    this.mine = false,
    this.author = '',
    this.ai = false,
  });
  final String id;
  final String noteId;
  final String text;
  final DateTime createdAt;
  final bool mine;
  final String author;
  final bool ai;
}

/// 알림 한 건. kind(room·comment·ai)로 아이콘과 누르면 갈 곳이 정해진다 (ridi_notifications.dart _open).
/// time 은 지금 시드용 글자 — 서버 연결 후에는 createdAt 으로 "n시간 전" 을 계산한다. 서버: Notification JSON (명세서 3-8)
class RidiNotification {
  RidiNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    required this.kind,
    this.roomId,
    this.bookId,
    this.noteId,
    this.read = false,
    this.archived = false,
  });
  final String id;
  final String title;
  final String body;
  final String time;

  /// room · comment · ai
  final String kind;

  /// 누르면 갈 곳
  final String? roomId;
  final String? bookId;
  final String? noteId;
  bool read;

  /// 보관함으로 옮긴 알림 (RIDI_NOTI_01 보관함 탭)
  bool archived;
}

/// 읽기 테마
enum PaperTheme { light, sepia, dark }

// ---------------- 저장소 ----------------
/// 앱 전체 상태. 값이 바뀌면 notifyListeners() → 이 값을 watch 하는 화면이 다시 그려진다.
class RidiStore extends ChangeNotifier {
  RidiStore() {
    _seed();
    restoreSession();
  }

  final RidiAuthRepository _authRepository = RidiAuthRepository();

  // ----- 계정 -----
  bool loggedIn = false;
  bool authReady = false;
  String? accessToken;
  String name = '박성필';
  String username = '';
  String nickname = '박성필';
  String bio = '밤에 조금씩 읽어요';
  String? profileImageUrl;
  String avatar = '박';

  // ----- 데이터 -----
  final List<RidiBook> books = [];
  final List<RidiRoom> rooms = [];

  /// 내가 들어가지 않은 방 — 서버에만 있는 방을 흉내 낸다 (코드 입장 시연용, 서버 연결 후 지운다)
  final List<RidiRoom> _otherRooms = [];
  final List<RidiPersona> personas = [];
  final List<RidiNote> notes = [];
  final List<RidiNotification> notifications = [];
  final List<RidiComment> comments = [];
  final List<String> recentSearches = ['봄봄', '김유정', '어린왕자'];

  /// 홈 통계 — 최근 7일 독서 시간(분, 마지막이 오늘). 서버: GET /api/me/stats
  final List<int> weekMinutes = [25, 40, 0, 35, 50, 20, 30];

  /// 이달의 추천 도서 (책 id, 추천 한 줄) — 첫 번째가 크게. 서버: GET /api/books/recommended
  final List<(String, String)> monthlyPicks = [
    ('b4', '짧은 단편이라 한 주 동안 방에서 같이 읽기 좋아요. 달밤 메밀밭 장면은 형광펜 각.'),
    ('b3', '어른이 되어 다시 읽으면 전혀 다른 문장이 보여요.'),
  ];

  // ----- 설정 -----
  double fontScale = 1.0; // 0.85 ~ 1.3
  int lineHeightStep = 1; // 0 좁게 · 1 보통 · 2 넓게
  PaperTheme paper = PaperTheme.light;
  bool twoColumn = true; // 뷰어 설정: 2단 / 1단
  bool keepScreenOn = false;

  /// 뷰어 "내 메모만 보기" — 켜면 방 멤버·AI 말풍선을 숨긴다 (폰에만 저장)
  bool onlyMyNotes = false;

  /// 펜 메뉴가 기억하는 마지막 펜 모양 (형광펜 / 밑줄)
  PenStyle lastPenStyle = PenStyle.highlight;

  /// 알림 설정 5종 (RIDI_NOTI_SET_01). 서버: GET/PUT /api/me/notification-settings
  final Map<String, bool> notiSettings = {
    '방 메모 알림': true,
    '댓글 알림': true,
    'AI 독서 친구 알림': true,
    '새 멤버 입장': false,
    '방해 금지 (22:00~08:00)': false,
  };

  /// 시연용 더미 계정 5개 — 아이디 = 이름, 비밀번호는 모두 1234. 서버 연결 후 지운다.
  static const dummyAccounts = ['김기산', '서성민', '손지유', '윤강은', '박성필'];
  static const dummyPassword = '1234';
  static const _dummyBios = {
    '김기산': '주말마다 한 권씩',
    '서성민': '출퇴근길에 읽어요',
    '손지유': '고전을 좋아해요',
    '윤강은': '밑줄 긋는 걸 좋아해요',
    '박성필': '밤에 조금씩 읽어요',
  };

  /// 시연용 데이터 — 로그인한 사람(name) 기준으로 만든다. 서버 연결 후 지운다.
  /// 책 4권, AI 캐릭터 3, 방 3개:
  /// - r1 목요일 밤 독서회 RM-7K2M: 박성필(방장)·서성민·손지유 + AI 미나 / 윤강은은 차단됨
  /// - r2 Thursday Club RM-DPZT: 김기산(방장)·윤강은·박성필 + AI 하루
  /// - r3 주말 고전 읽기 RM-8QHN (비밀번호 1234): 손지유(방장)·김기산
  /// 내가 멤버인 방은 내 목록(rooms), 아닌 방은 코드로만 찾는다(_otherRooms).
  /// 방 메모·댓글은 쓴 사람 이름으로 넣고, 로그인한 사람이 쓴 것이 "내 것"(mine)이 된다.
  /// rn4·rn5 는 2장 메모라 스포일러 잠금 시연용.
  void _seed() {
    final me = name;
    books.addAll([
      RidiBook(
        id: 'b1',
        title: '봄봄',
        author: '김유정',
        chapters: 12,
        done: true,
        owned: true,
        lastOpened: '방금 전 열람',
        page: 7,
        unread: 27,
        readMinutes: 190,
      ),
      RidiBook(
        id: 'b2',
        title: '운수 좋은 날',
        author: '현진건',
        chapters: 9,
        owned: true,
        lastOpened: '1일 전 열람',
        page: 1,
        unread: 99,
        readMinutes: 85,
      ),
      RidiBook(
        id: 'b3',
        title: '어린왕자',
        author: '생텍쥐페리',
        chapters: 1,
        readMinutes: 20,
      ),
      RidiBook(id: 'b4', title: '메밀꽃 필 무렵', author: '이효석', chapters: 5),
    ]);
    personas.addAll(const [
      RidiPersona(
        id: 'p1',
        name: '하루',
        tone: '감성적',
        intro: '문장의 온도를 느끼는 감성파',
        sample: '"이 문장, 마음에 남지 않아요?"',
      ),
      RidiPersona(
        id: 'p2',
        name: '도현',
        tone: '분석적',
        intro: '복선을 추리하는 탐정형',
        sample: '"이 장면, 나중에 중요해질 것 같아요."',
      ),
      RidiPersona(
        id: 'p3',
        name: '미나',
        tone: '유머러스',
        intro: '먼저 말 거는 수다형',
        sample: '"여기서 웃었어요. 당신은요?"',
      ),
    ]);
    final all = [
      RidiRoom(
        id: 'r1',
        name: '목요일 밤 독서회',
        code: 'RM-7K2M',
        bookIds: ['b2'],
        members: const [
          RidiMember('박성필', owner: true),
          RidiMember('서성민'),
          RidiMember('손지유'),
          RidiMember('미나', ai: true),
        ],
        personaId: 'p3',
        lastBookId: 'b2',
        blocked: ['윤강은'],
      ),
      RidiRoom(
        id: 'r2',
        name: 'Thursday Club',
        code: 'RM-DPZT',
        bookIds: ['b3', 'b1', 'b2'],
        members: const [
          RidiMember('김기산', owner: true),
          RidiMember('윤강은'),
          RidiMember('박성필'),
          RidiMember('하루', ai: true),
        ],
        personaId: 'p1',
        lastBookId: 'b1',
      ),
      RidiRoom(
        id: 'r3',
        name: '주말 고전 읽기',
        code: 'RM-8QHN',
        bookIds: ['b4', 'b2'],
        members: const [RidiMember('손지유', owner: true), RidiMember('김기산')],
        lastBookId: 'b4',
        maxMembers: 8,
        password: '1234',
      ),
    ];
    for (final r in all) {
      (isMember(r) ? rooms : _otherRooms).add(r);
    }
    bool inRoom(String id) => rooms.any((r) => r.id == id);

    notes.addAll([
      RidiNote(
        id: 'n1',
        bookId: 'b1',
        kind: NoteKind.bookmark,
        chapter: 0,
        page: 7,
        line: 0,
        phrase: 'Chapter 1',
        createdAt: DateTime(2026, 9, 21),
      ),
      RidiNote(
        id: 'n2',
        bookId: 'b1',
        kind: NoteKind.highlight,
        chapter: 0,
        page: 7,
        line: 0,
        phrase: '저.......”',
        memo: 'ㅋㅋ',
        colorIndex: 4,
        createdAt: DateTime(2026, 9, 21),
      ),
    ]);
    // 방 메모 — 쓴 사람(author)이 로그인한 사람이면 내 메모
    RidiNote shared(
      String id,
      String room,
      String bookId,
      int ch,
      int line,
      String memo, {
      required String author,
      bool ai = false,
      int color = 4,
      int daysAgo = 1,
    }) => RidiNote(
      id: id,
      bookId: bookId,
      kind: NoteKind.highlight,
      chapter: ch,
      page: kFirstPageOf(ch),
      line: line,
      phrase: _lastWord(ch, line),
      memo: memo,
      colorIndex: color,
      createdAt: DateTime.now().subtract(Duration(days: daysAgo, hours: line)),
      roomIds: [room],
      mine: !ai && author == me,
      author: author,
      ai: ai,
    );
    notes.addAll([
      shared(
        'rn0',
        'r1',
        'b2',
        0,
        3,
        '반전 ㅋㅋ 사람 키 얘기가 아니었네',
        author: '박성필',
        color: 0,
        daysAgo: 2,
      ),
      shared(
        'rn1',
        'r1',
        'b2',
        0,
        2,
        '장인 첫 등장부터 강렬하다',
        author: '서성민',
        color: 4,
        daysAgo: 2,
      ),
      shared(
        'rn2',
        'r1',
        'b2',
        0,
        8,
        '계약서 없이 일하면 이렇게 됩니다… 현실 공감',
        author: '손지유',
        color: 3,
      ),
      shared(
        'rn3',
        'r1',
        'b2',
        0,
        11,
        '여기서 웃었어요. 키가 모로만 벌어진다니! 당신은요?',
        author: '미나',
        ai: true,
        color: 2,
      ),
      shared('rn4', 'r1', 'b2', 1, 8, '꾀병 연기 대상 드립니다', author: '서성민', color: 4),
      shared(
        'rn5',
        'r2',
        'b1',
        1,
        3,
        '이 장면, 나중에 중요해질 것 같아요.',
        author: '하루',
        ai: true,
        color: 3,
        daysAgo: 0,
      ),
      shared(
        'rn6',
        'r2',
        'b1',
        0,
        4,
        '삼 년 일곱 달… 그 시간의 무게가 문장에 담겨 있어요.',
        author: '하루',
        ai: true,
        color: 1,
      ),
      shared(
        'rn7',
        'r2',
        'b1',
        0,
        2,
        '장인 캐릭터가 너무 현실적이라 웃프다',
        author: '김기산',
        color: 0,
      ),
      shared(
        'rn8',
        'r2',
        'b1',
        0,
        6,
        '여기 문장 리듬 좋아요',
        author: '윤강은',
        color: 1,
        daysAgo: 0,
      ),
      shared(
        'rn9',
        'r3',
        'b4',
        0,
        1,
        '첫 문장부터 달빛이 보이는 느낌',
        author: '손지유',
        color: 3,
      ),
    ]);
    RidiComment comment(
      String id,
      String noteId,
      String text,
      String author,
      Duration ago,
    ) => RidiComment(
      id: id,
      noteId: noteId,
      text: text,
      author: author,
      mine: author == me,
      createdAt: DateTime.now().subtract(ago),
    );
    comments.addAll([
      comment(
        'c1',
        'rn0',
        '나도 여기서 빵 터짐',
        '서성민',
        const Duration(days: 1, hours: 3),
      ),
      comment(
        'c2',
        'rn0',
        '작가가 일부러 헷갈리게 쓴 듯',
        '손지유',
        const Duration(hours: 20),
      ),
      comment('c3', 'rn1', '욕필이 ㅋㅋ 별명까지 있음', '손지유', const Duration(days: 1)),
      comment('c4', 'rn3', '저도요! 표현이 너무 웃겨요', '박성필', const Duration(hours: 5)),
      comment('c5', 'rn7', '동감 ㅋㅋ', '윤강은', const Duration(hours: 8)),
    ]);
    // 알림 — 받는 사람 기준
    notifications.addAll([
      if (inRoom('r2'))
        RidiNotification(
          id: 'm1',
          title: 'AI 독서 친구 하루가 메모를 남겼어요',
          body: '봄봄 2장 · 아직 안 읽은 장이라 내용은 가려 뒀어요',
          time: '10시간 전',
          kind: 'ai',
          roomId: 'r2',
          bookId: 'b1',
          noteId: 'rn5',
        ),
      if (inRoom('r1') && me != '손지유')
        RidiNotification(
          id: 'm2',
          title: '목요일 밤 독서회에 손지유 님이 들어왔어요',
          body: '방 코드 RM-7K2M 로 입장',
          time: '1일 전',
          kind: 'room',
          roomId: 'r1',
          bookId: 'b2',
        ),
      if (me == '박성필')
        RidiNotification(
          id: 'm3',
          title: '내 메모에 댓글이 달렸어요',
          body: '운수 좋은 날 1장 · 문장 4 · 서성민 "나도 여기서 빵 터짐"',
          time: '1일 전',
          kind: 'comment',
          roomId: 'r1',
          bookId: 'b2',
          noteId: 'rn0',
        ),
      if (me == '서성민')
        RidiNotification(
          id: 'm4',
          title: '내 메모에 댓글이 달렸어요',
          body: '운수 좋은 날 1장 · 문장 3 · 손지유 "욕필이 ㅋㅋ 별명까지 있음"',
          time: '1일 전',
          kind: 'comment',
          roomId: 'r1',
          bookId: 'b2',
          noteId: 'rn1',
        ),
      if (me == '김기산')
        RidiNotification(
          id: 'm5',
          title: '내 메모에 댓글이 달렸어요',
          body: '봄봄 1장 · 문장 3 · 윤강은 "동감 ㅋㅋ"',
          time: '8시간 전',
          kind: 'comment',
          roomId: 'r2',
          bookId: 'b1',
          noteId: 'rn7',
        ),
      if (me == '손지유')
        RidiNotification(
          id: 'm6',
          title: '주말 고전 읽기에 김기산 님이 들어왔어요',
          body: '방 코드 RM-8QHN 로 입장',
          time: '2일 전',
          kind: 'room',
          roomId: 'r3',
          bookId: 'b4',
        ),
    ]);
  }

  // ----- 조회 -----
  /// 내 책장 (RIDI_LIB_01). 서버: GET /api/me/shelf
  List<RidiBook> get shelf => books.where((b) => b.owned).toList();
  RidiBook? book(String? id) =>
      id == null ? null : books.where((b) => b.id == id).firstOrNull;
  RidiPersona? persona(String? id) =>
      id == null ? null : personas.where((p) => p.id == id).firstOrNull;
  RidiRoom? room(String id) => rooms.where((r) => r.id == id).firstOrNull;
  List<RidiBook> roomBooks(RidiRoom r) =>
      r.bookIds.map(book).whereType<RidiBook>().toList();

  /// 방 카드를 누르면 열 책 — 그 방에서 마지막에 읽던 책, 없으면 첫 책
  RidiBook? roomNextBook(RidiRoom r) =>
      book(r.lastBookId) ?? roomBooks(r).firstOrNull;
  RidiNote? note(String? id) =>
      id == null ? null : notes.where((n) => n.id == id).firstOrNull;

  /// 내가 이 방의 방장인가 (멤버 관리·비밀번호·정원 바꾸기는 방장만)
  bool isOwner(RidiRoom r) =>
      r.members.any((m) => m.owner && (m.name == name || m.name == nickname));
  bool isMember(RidiRoom r) =>
      r.members.any((m) => !m.ai && (m.name == name || m.name == nickname));

  /// 이 책을 함께 읽는 내 방들 — 메모 공개 범위 칩 (RIDI_MEMO_01)
  List<RidiRoom> roomsReading(String bookId) =>
      rooms.where((r) => r.bookIds.contains(bookId)).toList();

  /// 공유한 방 이름 요약 — "목요일 밤 독서회" / "목요일 밤 독서회 외 1곳" / null(나만 보기)
  String? sharedLabel(RidiNote n) {
    final names = n.roomIds
        .map((id) => room(id)?.name)
        .whereType<String>()
        .toList();
    if (names.isEmpty) return n.roomIds.isEmpty ? null : '나간 방';
    return names.length == 1
        ? names.first
        : '${names.first} 외 ${names.length - 1}곳';
  }

  /// 내 독서노트 (내가 쓴 것만, 공유 여부 무관). 서버: GET /api/books/{bookId}/memos?mine=true
  List<RidiNote> notesOf(String bookId, {NoteKind? kind}) => notes
      .where(
        (n) => n.mine && n.bookId == bookId && (kind == null || n.kind == kind),
      )
      .toList();

  /// 이 페이지에 내 책갈피가 있나 (뷰어 오른쪽 위 리본)
  bool hasBookmark(String bookId, int page) => notes.any(
    (n) =>
        n.mine &&
        n.bookId == bookId &&
        n.kind == NoteKind.bookmark &&
        n.page == page,
  );

  /// 방에 공유된 메모 (나 + 멤버 + AI). 장·문장 순. 서버: GET /api/rooms/{roomId}/books/{bookId}/memos
  List<RidiNote> roomNotes(String roomId, String bookId) =>
      notes
          .where(
            (n) =>
                n.roomIds.contains(roomId) &&
                n.bookId == bookId &&
                n.kind == NoteKind.highlight,
          )
          .toList()
        ..sort(
          (a, b) => a.chapter != b.chapter
              ? a.chapter.compareTo(b.chapter)
              : a.line.compareTo(b.line),
        );

  /// 스포일러 (장 단위, D4): 보고 있는 방이 잠금을 켰고, 남의 메모가 내가 읽은 장보다 뒤에 있으면 내용을 숨긴다.
  /// 메모가 여러 방에 공유될 수 있으므로 "지금 보고 있는 방"의 잠금 설정을 따른다.
  /// 서버 연결 후에는 서버가 memo.spoiler 로 계산해 주고(내용도 빈칸), 앱은 그 값만 쓴다.
  bool isSpoiler(RidiNote n, String roomId) {
    if (n.mine) return false;
    final r = room(roomId);
    if (r == null || !r.spoilerLock) return false;
    return n.chapter > (book(n.bookId)?.chapterReached ?? 0);
  }

  /// 표시 이름 — 내 것은 지금 닉네임을 쓴다(닉네임을 바꾸면 따라감)
  String authorOf(RidiNote n) => n.mine ? nickname : n.author;
  String commentAuthor(RidiComment c) => c.mine ? nickname : c.author;

  /// 메모의 댓글 (오래된 순). 서버: GET /api/memos/{memoId}/comments
  List<RidiComment> commentsOf(String noteId) =>
      comments.where((c) => c.noteId == noteId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// 안 읽은 알림 수 — 하단 탭 알림 아이콘의 빨간 점. 서버: GET /api/notifications 의 read
  int unreadCount() =>
      notifications.where((n) => !n.read && !n.archived).length;

  // ----- 계정 -----
  /// 로그인 — 더미 계정(아이디 = 이름, 비밀번호 1234)이면 그 사람으로, 아니면 기본 계정(박성필)으로 통과.
  /// 더미 계정 이름에 비밀번호가 틀리면 false (로그인 화면이 오류 문구를 보여 줌).
  /// 서버: POST /api/members/login → 받은 토큰을 저장하고 이후 요청에 Authorization: Bearer
  /* Legacy in-memory authentication removed. The app now authenticates only
   * after a successful response from the Spring Boot API.
  bool login(String id, String password) {
    final who = id.trim();
    final dummy = dummyAccounts.contains(who);
    if (dummy && password != dummyPassword) return false;
    _become(dummy ? who : '박성필');
    return true;
  }

  /// 회원가입 후 바로 로그인 — 새 사람이라 들어간 방·쓴 메모가 없다. 서버: POST /api/members/signup
  void signup(String who) => _become(who.trim().isEmpty ? '박성필' : who.trim());

  /// 이 사람으로 로그인: 이름·닉네임·아바타·소개를 바꾸고 시연 데이터를 이 사람 기준으로 다시 만든다
  */
  Future<String?> login(String id, String password) async {
    final username = id.trim();
    if (username.isEmpty || password.isEmpty) return '아이디와 비밀번호를 입력해주세요.';
    try {
      final session = await _authRepository.login(
        username: username,
        password: password,
      );
      accessToken = session.accessToken;
      _become(session.user.nickname);
      this.username = session.user.username;
      await refreshProfile();
      return null;
    } on RidiAuthException catch (e) {
      return e.message;
    }
  }

  Future<String?> signup({
    required String username,
    required String password,
    required String nickname,
  }) async {
    try {
      await _authRepository.signup(
        username: username.trim(),
        password: password,
        nickname: nickname.trim(),
      );
      return null;
    } on RidiAuthException catch (e) {
      return e.message;
    }
  }

  Future<void> restoreSession() async {
    try {
      final user = await _authRepository.restoreUser();
      if (user != null) {
        accessToken = await _authRepository.accessToken();
        _become(user.nickname);
        username = user.username;
        await refreshProfile();
      }
    } finally {
      authReady = true;
      notifyListeners();
    }
  }

  void _become(String who) {
    name = who;
    nickname = who;
    avatar = who.substring(0, 1);
    bio = _dummyBios[who] ?? '';
    for (final list in <List<Object>>[
      books,
      rooms,
      _otherRooms,
      personas,
      notes,
      notifications,
      comments,
    ]) {
      list.clear();
    }
    _seed();
    loggedIn = true;
    notifyListeners();
  }

  /// 로그아웃 → RidiGate 가 로그인 화면으로 바꾼다. 서버: 토큰만 버림
  Future<void> logout() async {
    loggedIn = false;
    accessToken = null;
    username = '';
    name = '';
    nickname = '';
    bio = '';
    profileImageUrl = null;
    avatar = '';
    notifyListeners();
    await _authRepository.logout();
  }

  Future<void> refreshProfile() async {
    if (!loggedIn || accessToken == null) return;
    final profile = await UserProfileRepository(
      ApiClient(tokenProvider: () => accessToken),
    ).get();
    _applyProfile(profile);
  }

  /// 성공한 서버 응답만 단일 사용자 상태에 반영한다.
  Future<void> saveProfile({
    required String nick,
    required String intro,
    Uint8List? imageBytes,
    String? imageFilename,
    String? imageContentType,
    bool removeProfileImage = false,
  }) async {
    final repository = UserProfileRepository(
      ApiClient(tokenProvider: () => accessToken),
    );
    final profile = removeProfileImage
        ? await repository.removeImage(nickname: nick, bio: intro)
        : await repository.updateWithImage(
            nickname: nick,
            bio: intro,
            imageBytes: imageBytes,
            filename: imageFilename,
            contentType: imageContentType,
          );
    _applyProfile(profile);
  }

  void _applyProfile(UserProfile profile) {
    username = profile.username;
    name = profile.nickname;
    nickname = profile.nickname;
    bio = profile.bio ?? '';
    profileImageUrl = profile.profileImageUrl;
    avatar = profile.avatar?.isNotEmpty == true
        ? profile.avatar!
        : profile.nickname.substring(0, 1);
    notifyListeners();
  }

  // ----- 책 -----
  /// 책장에 담기 (UC-08 도서 다운로드). 서버: PUT /api/me/shelf/{bookId}
  void addToShelf(String bookId) {
    final b = book(bookId);
    if (b == null || b.owned) return;
    b.owned = true;
    b.lastOpened = '방금 담음';
    notifyListeners();
  }

  /// 책장에서 빼기 — 메모·형광펜은 남는다. 서버: DELETE /api/me/shelf {bookIds}
  void removeFromShelf(Iterable<String> ids) {
    for (final id in ids) {
      book(id)?.owned = false;
    }
    notifyListeners();
  }

  /// 책을 열 때: "방금 전 열람" 표시, 방에서 열었으면 그 방의 마지막 책으로 기억.
  /// 서버: 방이면 PATCH /api/rooms/{id} {lastBookId} (열람 시각은 서버가 progress 로 기록)
  void openBook(String bookId, {String? roomId}) {
    final b = book(bookId);
    if (b == null) return;
    b.lastOpened = '방금 전 열람';
    if (roomId != null) room(roomId)?.lastBookId = bookId;
    notifyListeners();
  }

  /// 페이지를 넘길 때마다 호출. 가장 멀리 읽은 장(chapterReached)은 줄지 않는다 — 스포일러 기준.
  /// 서버: PUT /api/books/{id}/progress {chapter, lineNo} (page 는 보내지 않음)
  void setPage(String bookId, int page, {int? chapter}) {
    final b = book(bookId);
    if (b == null) return;
    final reached = chapter != null && chapter > b.chapterReached;
    if (b.page == page && !reached) return;
    b.page = page;
    if (reached) b.chapterReached = chapter;
    notifyListeners();
  }

  /// 최근 검색어에 넣기 (최대 8개, 같은 말은 맨 앞으로). 폰에만 저장
  void addSearch(String q) {
    final s = q.trim();
    if (s.isEmpty) return;
    recentSearches.remove(s);
    recentSearches.insert(0, s);
    if (recentSearches.length > 8) recentSearches.removeLast();
    notifyListeners();
  }

  /// 최근 검색어 전체 삭제
  void clearSearches() {
    recentSearches.clear();
    notifyListeners();
  }

  // ----- 방 -----
  /// 방 코드 글자 — 헷갈리는 0·O·1·I 는 뺐다
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final _rand = Random();

  /// RM-XXXX 코드 만들기 (이미 있으면 다시). 서버 연결 후에는 서버가 만든다
  String newCode() {
    String gen() =>
        'RM-${List.generate(4, (_) => _alphabet[_rand.nextInt(_alphabet.length)]).join()}';
    var c = gen();
    while ([...rooms, ..._otherRooms].any((r) => r.code == c)) {
      c = gen();
    }
    return c;
  }

  /// 방 만들기 (UC-03): 나는 방장, AI 친구를 골랐으면 멤버로 넣고, 고른 책은 내 책장에도 담는다.
  /// 새 방은 목록 맨 앞. 서버: POST /api/rooms
  RidiRoom createRoom({
    required String name,
    required List<String> bookIds,
    String? personaId,
    bool spoilerLock = true,
    int maxMembers = 6,
    String? password,
  }) {
    final p = persona(personaId);
    final r = RidiRoom(
      id: 'r${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      code: newCode(),
      bookIds: bookIds,
      members: [
        RidiMember(nickname, owner: true),
        if (p != null) RidiMember(p.name, ai: true),
      ],
      personaId: personaId,
      lastBookId: bookIds.firstOrNull,
      spoilerLock: spoilerLock,
      maxMembers: maxMembers.clamp(kRoomMinMembers, kRoomMaxMembers),
      password: password,
    );
    rooms.insert(0, r);
    for (final id in bookIds) {
      addToShelf(id);
    }
    notifyListeners();
    return r;
  }

  // ----- 홈 -----
  /// 읽고 있는 책 — 책장에 있고 아직 다 읽지 않은 책
  List<RidiBook> get readingNow =>
      books.where((b) => b.owned && !b.done).toList();

  /// 자주 읽는 책 — 읽은 시간 많은 순 3권
  List<RidiBook> get topBooks =>
      (books.where((b) => b.readMinutes > 0).toList()
            ..sort((a, b) => b.readMinutes.compareTo(a.readMinutes)))
          .take(3)
          .toList();

  /// 연속으로 읽은 날 (오늘부터 거꾸로)
  int get streakDays {
    var n = 0;
    for (final m in weekMinutes.reversed) {
      if (m == 0) break;
      n++;
    }
    return n;
  }

  /// 코드로 방 찾기 (입장 전 미리보기용 — 내 방 + 아직 안 들어간 방). 서버: GET /api/rooms/preview?code=
  RidiRoom? findByCode(String code) {
    final c = code.trim().toUpperCase();
    return [...rooms, ..._otherRooms].where((r) => r.code == c).firstOrNull;
  }

  /// 코드로 입장 (UC-04). 이미 멤버면 그대로 ok. 아니면 차단 → 정원 → 비밀번호(숫자 4자리) 순으로 검사.
  /// 들어간 방은 목록 맨 앞으로. 서버: POST /api/rooms/join {code, password?}
  JoinResult joinRoom(String code, {String? password}) {
    final r = findByCode(code);
    if (r == null) return JoinResult.notFound;
    if (!isMember(r)) {
      if (r.blocked.contains(nickname)) return JoinResult.blocked;
      if (r.humanCount >= r.maxMembers) return JoinResult.full;
      if (r.password != null && r.password != password)
        return JoinResult.wrongPassword;
      r.members = [...r.members, RidiMember(nickname)];
    }
    _otherRooms.remove(r);
    rooms.remove(r);
    rooms.insert(0, r);
    notifyListeners();
    return JoinResult.ok;
  }

  /// 나를 뺀 사람 멤버, 들어온 순서대로 (AI 친구 제외). 방장이 나가면 첫 번째 사람이 방장
  List<RidiMember> otherHumans(RidiRoom r) => r.members
      .where((m) => !m.ai && m.name != name && m.name != nickname)
      .toList();

  /// 방장 넘기기 (방장 → 다른 사람 멤버). 서버: PATCH /api/rooms/{id} {ownerId}
  void transferOwner(String id, String to) {
    final r = room(id);
    if (r == null) return;
    r.members = [
      for (final m in r.members)
        RidiMember(m.name, ai: m.ai, owner: !m.ai && m.name == to),
    ];
    notifyListeners();
  }

  /// 방 나가기 (D5 결정: 방장이 나가면 들어온 순서대로 가장 먼저 들어온 사람이 방장이 된다).
  /// 사람 멤버가 나 혼자면 방이 사라진다. 나간 방은 남은 사람들의 방으로 남아 코드로 다시 찾을 수 있다.
  /// 서버: DELETE /api/rooms/{id}/members/me — 서버가 다음 방장을 정한다(가장 먼저 들어온 멤버), 혼자면 방 삭제
  void leaveRoom(String id) {
    final r = room(id);
    if (r == null) return;
    final others = otherHumans(r);
    if (isOwner(r) && others.isNotEmpty) transferOwner(id, others.first.name);
    rooms.remove(r);
    if (others.isNotEmpty) {
      r.members = r.members
          .where((m) => m.ai || (m.name != name && m.name != nickname))
          .toList();
      _otherRooms.add(r);
    }
    notifyListeners();
  }

  /// 방 이름 바꾸기 (방장). 서버: PATCH /api/rooms/{id} {name}
  void renameRoom(String id, String name) {
    final r = room(id);
    if (r == null || name.trim().isEmpty) return;
    r.name = name.trim();
    notifyListeners();
  }

  /// 방 AI 친구 바꾸기 / 없애기(null) — 멤버 목록의 AI 도 같이 바꾼다. 서버: PATCH /api/rooms/{id} {personaId}
  void setRoomPersona(String id, String? personaId) {
    final r = room(id);
    if (r == null) return;
    r.personaId = personaId;
    final p = persona(personaId);
    r.members = [
      ...r.members.where((m) => !m.ai),
      if (p != null) RidiMember(p.name, ai: true),
    ];
    notifyListeners();
  }

  /// 스포일러 잠금 켜기/끄기 (방장). 서버: PATCH /api/rooms/{id} {spoilerLock}
  void setRoomSpoilerLock(String id, bool v) {
    final r = room(id);
    if (r == null) return;
    r.spoilerLock = v;
    notifyListeners();
  }

  /// 최대 인원 바꾸기 (방장, RIDI_ROOMS_02). 지금 멤버 수보다 적게는 못 줄인다. 서버: PATCH /api/rooms/{id} {maxMembers}
  void setRoomMaxMembers(String id, int n) {
    final r = room(id);
    if (r == null) return;
    r.maxMembers = n.clamp(max(kRoomMinMembers, r.humanCount), kRoomMaxMembers);
    notifyListeners();
  }

  /// 방 비밀번호 걸기 / 풀기(null) — 숫자 4자리 (방장, 코드 재발급 대신). 서버: PATCH /api/rooms/{id} {password}
  void setRoomPassword(String id, String? password) {
    final r = room(id);
    if (r == null) return;
    r.password = password;
    notifyListeners();
  }

  /// 멤버 내보내기 (방장, RIDI_ROOM_MEMBERS_01) — 코드가 있으면 다시 들어올 수 있다.
  /// 서버: DELETE /api/rooms/{id}/members/{memberId}
  void kickMember(String id, String name) {
    final r = room(id);
    if (r == null) return;
    r.members = r.members
        .where((m) => m.ai || m.owner || m.name != name)
        .toList();
    notifyListeners();
  }

  /// 멤버 차단 (방장) — 내보내고 다시 못 들어오게. 서버: POST /api/rooms/{id}/blocks {memberId}
  void blockMember(String id, String name) {
    final r = room(id);
    if (r == null) return;
    kickMember(id, name);
    if (!r.blocked.contains(name)) r.blocked = [...r.blocked, name];
    notifyListeners();
  }

  /// 차단 해제 (방장). 서버: DELETE /api/rooms/{id}/blocks/{memberId}
  void unblockMember(String id, String name) {
    final r = room(id);
    if (r == null) return;
    r.blocked = r.blocked.where((b) => b != name).toList();
    notifyListeners();
  }

  /// 방에 책 추가 (이미 있는 책은 건너뜀) + 내 책장에도 담기. 서버: PUT /api/rooms/{id}/books
  void addRoomBooks(String id, List<String> bookIds) {
    final r = room(id);
    if (r == null) return;
    r.bookIds = [...r.bookIds, ...bookIds.where((b) => !r.bookIds.contains(b))];
    for (final b in bookIds) {
      addToShelf(b);
    }
    notifyListeners();
  }

  // ----- AI 친구 -----
  /// 새 AI 친구 만들기 (UC-09). 성격을 비우면 "○○ 말투의 AI 독서 친구". 서버: POST /api/ai/personas
  RidiPersona createPersona({
    required String name,
    required String tone,
    required String intro,
  }) {
    final p = RidiPersona(
      id: 'p${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      tone: tone,
      intro: intro.trim().isEmpty ? '$tone 말투의 AI 독서 친구' : intro.trim(),
      sample: '"함께 읽어요."',
    );
    personas.add(p);
    notifyListeners();
    return p;
  }

  // ----- 독서노트 -----
  /// 형광펜·밑줄·책갈피 저장. roomIds 의 방들에 공유(방에서 쓰면 기본은 그 방, 책갈피는 항상 나만).
  /// wordFrom~wordTo = 칠한 어절 범위. 서버: POST /api/books/{bookId}/memos
  RidiNote addNote({
    required String bookId,
    required NoteKind kind,
    required int chapter,
    required int page,
    required int line,
    required String phrase,
    String memo = '',
    int colorIndex = 4,
    List<String> roomIds = const [],
    PenStyle penStyle = PenStyle.highlight,
    int? wordFrom,
    int? wordTo,
  }) {
    final n = RidiNote(
      id: 'n${DateTime.now().microsecondsSinceEpoch}',
      bookId: bookId,
      kind: kind,
      chapter: chapter,
      page: page,
      line: line,
      phrase: phrase,
      memo: memo,
      colorIndex: colorIndex,
      createdAt: DateTime.now(),
      roomIds: kind == NoteKind.bookmark ? [] : [...roomIds],
      penStyle: penStyle,
      wordFrom: wordFrom,
      wordTo: wordTo,
    );
    if (kind == NoteKind.highlight) lastPenStyle = penStyle;
    notes.add(n);
    notifyListeners();
    return n;
  }

  /// 책갈피 켜기/끄기 — 켜졌으면 true. 서버: POST /api/books/{bookId}/memos {noteType: bookmark} / 삭제
  bool toggleBookmark({
    required String bookId,
    required int chapter,
    required int page,
    required String chapterTitle,
  }) {
    final found = notes
        .where(
          (n) =>
              n.mine &&
              n.bookId == bookId &&
              n.kind == NoteKind.bookmark &&
              n.page == page,
        )
        .firstOrNull;
    if (found != null) {
      notes.remove(found);
      notifyListeners();
      return false;
    }
    addNote(
      bookId: bookId,
      kind: NoteKind.bookmark,
      chapter: chapter,
      page: page,
      line: 0,
      phrase: chapterTitle,
    );
    return true;
  }

  /// 형광펜 색 바꾸기 (0~4, RidiColors.penColors 순서). 서버: PATCH /api/memos/{id} {color}
  void setNoteColor(String noteId, int colorIndex) {
    final n = notes.where((e) => e.id == noteId).firstOrNull;
    if (n == null) return;
    n.colorIndex = colorIndex;
    notifyListeners();
  }

  /// 펜 모양 바꾸기 (형광펜 ↔ 밑줄). 서버: PATCH /api/memos/{id} {penStyle}
  void setNotePenStyle(String noteId, PenStyle style) {
    final n = note(noteId);
    if (n == null) return;
    n.penStyle = style;
    lastPenStyle = style;
    notifyListeners();
  }

  /// 메모 글 저장 (최대 1500자). 서버: PATCH /api/memos/{id} {text}
  void updateMemo(String noteId, String memo) {
    final n = notes.where((e) => e.id == noteId).firstOrNull;
    if (n == null) return;
    n.memo = memo;
    notifyListeners();
  }

  /// 공개 범위 바꾸기 — 공유할 방들 (빈 목록 = 나만 보기). 서버: PATCH /api/memos/{id} {roomIds}
  void setNoteRooms(String noteId, List<String> roomIds) {
    final n = note(noteId);
    if (n == null || !n.mine || n.kind == NoteKind.bookmark) return;
    n.roomIds = [...roomIds];
    notifyListeners();
  }

  /// 여러 개 삭제 (내 것만) — 달린 댓글도 함께 지운다. 서버: DELETE /api/memos {ids}
  void deleteNotes(Iterable<String> ids) {
    final set = ids.toSet();
    notes.removeWhere((n) => set.contains(n.id) && n.mine);
    comments.removeWhere((c) => set.contains(c.noteId));
    notifyListeners();
  }

  // ----- 댓글 -----
  /// 댓글 달기 (빈 글은 무시, 올린 댓글을 돌려줌). 서버: POST /api/memos/{memoId}/comments
  RidiComment? addComment(String noteId, String text) {
    final t = text.trim();
    if (t.isEmpty || note(noteId) == null) return null;
    final c = RidiComment(
      id: 'c${DateTime.now().microsecondsSinceEpoch}',
      noteId: noteId,
      text: t,
      createdAt: DateTime.now(),
      mine: true,
    );
    comments.add(c);
    notifyListeners();
    return c;
  }

  /// 내 댓글 지우기. 서버: DELETE /api/memos/{memoId}/comments/{commentId}
  void deleteComment(String id) {
    comments.removeWhere((c) => c.id == id && c.mine);
    notifyListeners();
  }

  // ----- 알림 -----
  /// 알림 하나 읽음 처리. 서버: POST /api/notifications/{id}/read
  void markRead(String id) {
    final n = notifications.where((e) => e.id == id).firstOrNull;
    if (n == null || n.read) return;
    n.read = true;
    notifyListeners();
  }

  /// 보관함으로 옮기기 (읽음도 같이). 서버: POST /api/notifications/{id}/archive
  void archiveNotification(String id) {
    final n = notifications.where((e) => e.id == id).firstOrNull;
    if (n == null) return;
    n.archived = true;
    n.read = true;
    notifyListeners();
  }

  /// 보관함에서 되돌리기. 서버: DELETE /api/notifications/{id}/archive
  void unarchiveNotification(String id) {
    final n = notifications.where((e) => e.id == id).firstOrNull;
    if (n == null) return;
    n.archived = false;
    notifyListeners();
  }

  /// 알림 지우기 — 지운 알림과 자리를 돌려준다(스낵바 되돌리기용). 서버: DELETE /api/notifications/{id}
  (RidiNotification, int)? deleteNotification(String id) {
    final i = notifications.indexWhere((e) => e.id == id);
    if (i < 0) return null;
    final n = notifications.removeAt(i);
    notifyListeners();
    return (n, i);
  }

  /// 지운 알림 되돌리기 (스낵바)
  void restoreNotification(RidiNotification n, int index) {
    notifications.insert(index.clamp(0, notifications.length), n);
    notifyListeners();
  }

  /// 모두 읽음. 서버: POST /api/notifications/read-all
  void markAllRead() {
    for (final n in notifications) {
      n.read = true;
    }
    notifyListeners();
  }

  // ----- 설정 -----
  /// 보기·뷰어 설정 (아래 5개) — 모두 폰에만 저장, 서버 불필요. 바꾸면 뷰어가 바로 다시 그려진다
  void setFontScale(double v) {
    fontScale = v;
    notifyListeners();
  }

  void setLineHeight(int step) {
    lineHeightStep = step;
    notifyListeners();
  }

  void setPaper(PaperTheme t) {
    paper = t;
    notifyListeners();
  }

  void setTwoColumn(bool v) {
    twoColumn = v;
    notifyListeners();
  }

  void setKeepScreenOn(bool v) {
    keepScreenOn = v;
    notifyListeners();
  }

  /// 뷰어 "내 메모만 보기" 켜기/끄기 (폰에만 저장)
  void setOnlyMyNotes(bool v) {
    onlyMyNotes = v;
    notifyListeners();
  }

  /// 알림 설정 토글 하나. 서버: PUT /api/me/notification-settings
  void setNoti(String key, bool v) {
    notiSettings[key] = v;
    notifyListeners();
  }

  /// 본문 행간 (보기 설정 3단계)
  double get lineHeight => [1.6, 1.85, 2.15][lineHeightStep];
}

/// 시드용: 장의 첫 페이지 번호 (2단 기본 배치 기준 대략값 — 서버엔 저장하지 않는 값)
int kFirstPageOf(int chapter) => chapter == 0 ? 7 : 10;

/// 형광펜이 걸리는 마지막 어절 (본문 표시 규칙과 같게)
String _lastWord(int chapter, int line) =>
    ridiChapters[chapter].lines[line].trim().split(' ').last;

/// 문장 전체
String ridiSentence(int chapter, int line) {
  if (chapter < 0 || chapter >= ridiChapters.length) return '';
  final lines = ridiChapters[chapter].lines;
  return line >= 0 && line < lines.length ? lines[line] : '';
}

/// '방금 · n분 전 · n시간 전 · n일 전'
String ridiAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return '방금';
  if (d.inHours < 1) return '${d.inMinutes}분 전';
  if (d.inDays < 1) return '${d.inHours}시간 전';
  return '${d.inDays}일 전';
}
