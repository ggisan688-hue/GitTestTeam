import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ridi_reader.dart';
import 'ridi_auth.dart';
import 'reading_rooms_screen.dart';
import 'book_search_screen.dart';
import 'ridi_rooms.dart';
import 'ridi_store.dart';
import 'ridi_theme.dart';
import 'ridi_widgets.dart';
import 'book_catalog.dart';
import '../../widgets/screen_tag.dart';
import '../../core/api_client.dart';
import '../../repository/book_repository.dart';
import '../../model/reading_stats.dart';
import '../../viewmodel/book_viewmodel.dart';

/// RIDI_HOME_01 — 홈 (도안: 왼쪽 위 읽고 있는 책 · 가운데 이달의 추천 도서 · 오른쪽 프로필 / 통계 / 자주 읽는 책)
///
/// - 읽고 있는 책: 책장에 있고 아직 다 안 읽은 책. 진행 막대 + 누르면 이어 읽기. 끝에 "책 담으러 가기"
/// - 이달의 추천 도서: 첫 권은 크게(추천 한 줄 · 책장에 담기/바로 읽기), 나머지는 작게
/// - 교환독서 방: 내 방 최대 3개 — 지금 읽는 책 · 메모 수. 누르면 그 방에서 이어 읽기
/// - 오른쪽: 프로필(내 정보) · 이번 주 독서 시간(7일 막대) · 연속 읽은 날 · 다 읽은 책 · 남긴 메모 · 자주 읽는 책 3
/// 좁은 화면(900 미만)에서는 오른쪽 칸이 위로 올라가 한 줄로 쌓인다.
/// 서버: 통계 GET /api/me/stats, 추천 GET /api/books/recommended (명세서에 추가 예정)
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => ScreenTag(
    'RIDI_HOME_01',
    alignment: Alignment.topCenter,
    child: _screen(context),
  );

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    final statsRevision = context.watch<BookViewModel>().statsRevision;
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 24,
        title: const Text(
          RidiBrand.appName,
          style: TextStyle(
            fontFamily: RidiText.f,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          if (!store.loggedIn)
            TextButton.icon(
              onPressed: () => showLoginDialog(context),
              icon: const Icon(Icons.login),
              label: const Text('로그인하세요'),
            ),
          IconButton(
            tooltip: 'Reading rooms',
            icon: const Icon(Icons.groups_outlined, size: 28),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReadingRoomsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 28),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const BookSearchScreen())),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 900;
          // 로그인하면 최근 읽은 도서가 위, 전체 도서가 아래 (수정1-7)
          final serverMain = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (store.loggedIn) ...const [
                _SectionTitle('최근 읽은 도서'),
                RecentReadingSection(),
                SizedBox(height: 36),
              ],
              _SectionTitle('전체 도서'),
              BookCatalogSection(),
            ],
          );
          // 게스트는 오른쪽 칸(프로필·통계) 없이 책 목록만 넓게
          final Widget? side = store.loggedIn
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProfileCard(store: store),
                    const SizedBox(height: 16),
                    _StatsCard(key: ValueKey(statsRevision)),
                  ],
                )
              : null;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
            child: side == null
                ? serverMain
                : wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: serverMain),
                      const SizedBox(width: 40),
                      SizedBox(width: 340, child: side),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [side, const SizedBox(height: 32), serverMain],
                  ),
          );
        },
      ),
    );
  }
}

/// 구역 제목
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(text, style: RidiText.title.copyWith(fontSize: 20)),
  );
}

/// 오른쪽 칸 카드 틀 (옅은 회색 판)
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: RidiColors.panel,
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

/// 책 열기 (방 없이 혼자 읽기)
void _openBook(BuildContext context, RidiBook b) {
  context.read<RidiStore>().openBook(b.id);
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => RidiReaderScreen(bookId: b.id)));
}

/// 책장에 담고 안내
void _addToShelf(BuildContext context, RidiStore store, RidiBook b) {
  store.addToShelf(b.id);
  ridiToast(context, '${b.title} 을 책장에 담았어요');
}

// ---------------- 읽고 있는 책 ----------------
/// 가로로 넘기는 카드들 + 끝에 "책 담으러 가기"
class _ReadingRow extends StatelessWidget {
  const _ReadingRow({required this.books});

  final List<RidiBook> books;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final b in books) ...[
            _ReadingCard(book: b),
            const SizedBox(width: 14),
          ],
          InkWell(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SearchScreen())),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 150,
              decoration: BoxDecoration(
                border: Border.all(color: RidiColors.grayLight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, color: RidiColors.gray, size: 28),
                  SizedBox(height: 6),
                  Text('책 담으러 가기', style: RidiText.sub),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 읽고 있는 책 카드 — 표지 · 제목 · 진행 막대(장 기준) · 마지막 열람
class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.book});

  final RidiBook book;

  @override
  Widget build(BuildContext context) {
    final progress = ((book.chapterReached + 1) / book.chapters).clamp(
      0.0,
      1.0,
    );
    return InkWell(
      onTap: () => _openBook(context, book),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 330,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: RidiColors.grayLight),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const RidiCover(width: 70, height: 100),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    book.title,
                    style: RidiText.bodyBold.copyWith(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(book.author, style: RidiText.sub),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      color: RidiColors.blue,
                      backgroundColor: RidiColors.grayLight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${book.chapters}장 중 ${book.chapterReached + 1}장 · ${book.lastOpened ?? '아직 안 열어 봄'}',
                    style: RidiText.sub.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- 이달의 추천 도서 ----------------
/// 첫 권은 크게, 나머지는 아래에 한 줄씩
class _PickHero extends StatelessWidget {
  const _PickHero({required this.store});

  final RidiStore store;

  @override
  Widget build(BuildContext context) {
    final picks = [
      for (final (id, why) in store.monthlyPicks)
        if (store.book(id) case final b?) (b, why),
    ];
    if (picks.isEmpty)
      return const Text('이번 달 추천 도서를 준비하고 있어요', style: RidiText.sub);
    final (top, why) = picks.first;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: RidiBrand.cream,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const RidiCover(width: 120, height: 172),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: RidiBrand.navy,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${DateTime.now().month}월의 추천',
                        style: const TextStyle(
                          fontFamily: RidiText.f,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      top.title,
                      style: RidiText.title.copyWith(fontSize: 26),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${top.author} · ${top.chapters}장',
                      style: RidiText.sub.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 14),
                    Text(why, style: RidiText.body.copyWith(fontSize: 16)),
                    const SizedBox(height: 20),
                    top.owned
                        ? RidiButton(
                            '바로 읽기',
                            height: 44,
                            onTap: () => _openBook(context, top),
                          )
                        : RidiButton(
                            '책장에 담기',
                            icon: Icons.add_rounded,
                            height: 44,
                            onTap: () => _addToShelf(context, store, top),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final (b, w) in picks.skip(1))
          InkWell(
            onTap: b.owned ? () => _openBook(context, b) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
              child: Row(
                children: [
                  const RidiCover(width: 40, height: 57),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${b.title}  ·  ${b.author}',
                          style: RidiText.bodyBold,
                        ),
                        Text(
                          w,
                          style: RidiText.sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!b.owned)
                    TextButton(
                      onPressed: () => _addToShelf(context, store, b),
                      child: const Text(
                        '담기',
                        style: TextStyle(
                          fontFamily: RidiText.f,
                          fontWeight: FontWeight.w700,
                          color: RidiColors.blue,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------- 교환독서 방 ----------------
/// 내 방 최대 3개 — 방 이름 · 읽는 책 · 멤버 · 메모 수. 누르면 그 방에서 이어 읽기
class _RoomNews extends StatelessWidget {
  const _RoomNews({required this.store});

  final RidiStore store;

  @override
  Widget build(BuildContext context) {
    if (store.rooms.isEmpty)
      return const Text(
        '아직 들어간 방이 없어요 · 내 서재 › 교환독서에서 방을 만들거나 코드로 들어가요',
        style: RidiText.sub,
      );
    return Column(
      children: [
        for (final r in store.rooms.take(3))
          if (store.roomNextBook(r) case final b?)
            InkWell(
              onTap: () {
                store.openBook(b.id, roomId: r.id);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        RidiReaderScreen(bookId: b.id, roomId: r.id),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 4,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: RidiColors.grayLight),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.groups_2_outlined, color: RidiColors.gray),
                    const SizedBox(width: 14),
                    Expanded(child: Text(r.name, style: RidiText.bodyBold)),
                    Text(
                      '${b.title} · 멤버 ${r.humanCount}명 · 메모 ${store.roomNotes(r.id, b.id).length}개',
                      style: RidiText.sub,
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: RidiColors.gray,
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

// ---------------- 오른쪽 칸 ----------------
/// 프로필 — 아바타 · 닉네임 · 소개 · 내 정보(RIDI_PROFILE_01)
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.store});

  final RidiStore store;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          RidiAvatar(label: store.avatar, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${store.nickname} 님', style: RidiText.title),
                Text(
                  store.bio.isEmpty ? '한 줄 소개를 적어 보세요' : store.bio,
                  style: RidiText.sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '내 정보',
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: RidiColors.gray,
            ),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ],
      ),
    );
  }
}

/// "3시간 20분" · "45분"
String _timeLabel(int m) =>
    m >= 60 ? '${m ~/ 60}시간${m % 60 == 0 ? '' : ' ${m % 60}분'}' : '$m분';

/// 통계 — 이번 주 독서 시간(7일 막대, 오늘 진하게) · 연속 읽은 날 · 다 읽은 책 · 남긴 메모
class _StatsCard extends StatefulWidget {
  const _StatsCard({super.key});
  @override
  State<_StatsCard> createState() => _StatsCardState();
}

class _StatsCardState extends State<_StatsCard> {
  late final BookRepository _repo;
  late Future<ReadingStats> _future;
  @override
  void initState() {
    super.initState();
    _repo = BookRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    _future = _repo.readingStats();
  }

  void _reload() => setState(() => _future = _repo.readingStats());
  @override
  Widget build(BuildContext context) => FutureBuilder<ReadingStats>(
    future: _future,
    builder: (context, s) {
      if (s.connectionState != ConnectionState.done)
        return const _Panel(
          child: SizedBox(
            height: 150,
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      if (s.hasError)
        return _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('이번 주 독서', style: RidiText.sub),
              const SizedBox(height: 12),
              const Text('통계를 불러오지 못했습니다.'),
              TextButton(onPressed: _reload, child: const Text('다시 시도')),
            ],
          ),
        );
      final stats = s.data!;
      final peak = stats.dailyReading.fold(
        1,
        (a, b) => b.paragraphsRead > a ? b.paragraphsRead : a,
      );
      return InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReadingStatsScreen(repository: _repo),
          ),
        ),
        child: _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text('이번 주 독서', style: RidiText.sub),
                  Spacer(),
                  Text('자세히 보기', style: RidiText.sub),
                ],
              ),
              Text(
                '${stats.periodParagraphsRead}문단',
                style: RidiText.title.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 76,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final day in stats.dailyReading)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 18,
                              height: day.paragraphsRead == 0
                                  ? 3
                                  : 52 * day.paragraphsRead / peak,
                              decoration: BoxDecoration(
                                color: RidiColors.blue.withValues(alpha: .7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              day.dayLabel,
                              style: RidiText.sub.copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 28),
              Row(
                children: [
                  _Stat(value: '${stats.currentStreakDays}일', label: '연속 읽기'),
                  _Stat(
                    value: '${stats.completedBooksCount}권',
                    label: '다 읽은 책',
                  ),
                  _Stat(value: '${stats.memoCount}개', label: '남긴 메모'),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class ReadingStatsScreen extends StatefulWidget {
  const ReadingStatsScreen({super.key, required this.repository});
  final BookRepository repository;
  @override
  State<ReadingStatsScreen> createState() => _ReadingStatsScreenState();
}

class _ReadingStatsScreenState extends State<ReadingStatsScreen> {
  String _period = 'week';
  late Future<ReadingStats> _future;
  Future<_MonthlyStats>? _monthlyFuture; // 월별 탭을 처음 열 때 불러옴
  @override
  void initState() {
    super.initState();
    _future = widget.repository.readingStats();
  }

  /// 월별(올해 1~12월) — 서버에 period=year 를 먼저 묻고, 아직 없으면 이번 달 기록만으로 채운다.
  // ※ 서버 연결 메모(백엔드 팀이 이어서): GET /api/reading-stats?period=year
  //   → startDate=1/1, endDate=12/31, dailyReading = 올해 날짜별 읽은 문단 수 (지금 응답 모양 그대로).
  //   생기면 이 화면은 그대로 12달 막대를 다 채운다.
  Future<_MonthlyStats> _loadMonthly() async {
    try {
      final year = await widget.repository.readingStats(period: 'year');
      return _MonthlyStats.from(year, onlyThisMonth: false);
    } catch (_) {
      final month = await widget.repository.readingStats(period: 'month');
      return _MonthlyStats.from(month, onlyThisMonth: true);
    }
  }

  void _load(String p) => setState(() {
    _period = p;
    if (p == 'week') {
      _future = widget.repository.readingStats();
    } else {
      _monthlyFuture = _loadMonthly();
    }
  });

  Widget _summary(ReadingStats x) => Row(
    children: [
      _Stat(value: '${x.currentStreakDays}일', label: '연속 읽기'),
      _Stat(value: '${x.completedBooksCount}권', label: '다 읽은 책'),
      _Stat(value: '${x.memoCount}개', label: '전체 메모'),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('독서 통계')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'week', label: Text('이번 주')),
            ButtonSegment(value: 'year', label: Text('월별')),
          ],
          selected: {_period},
          onSelectionChanged: (v) => _load(v.first),
        ),
        const SizedBox(height: 20),
        if (_period == 'week')
          FutureBuilder<ReadingStats>(
            future: _future,
            builder: (context, s) {
              if (!s.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final x = s.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${x.startDate.month}/${x.startDate.day} ~ ${x.endDate.month}/${x.endDate.day}',
                    style: RidiText.sub,
                  ),
                  const SizedBox(height: 12),
                  _WeekBars(days: x.dailyReading),
                  const Divider(height: 32),
                  _summary(x),
                ],
              );
            },
          )
        else
          FutureBuilder<_MonthlyStats>(
            future: _monthlyFuture ??= _loadMonthly(),
            builder: (context, s) {
              if (!s.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final m = s.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${m.year}년 · 1월 ~ 12월', style: RidiText.sub),
                      const Spacer(),
                      Text(
                        '올해 ${m.total}문단',
                        style: RidiText.sub.copyWith(
                          color: RidiColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _MonthBars(perMonth: m.perMonth, current: m.currentMonth),
                  if (m.onlyThisMonth) ...[
                    const SizedBox(height: 8),
                    Text(
                      '지금은 이번 달 기록만 보여요. 지난 달 기록은 서버 기능이 생기면 함께 표시돼요.',
                      style: RidiText.sub.copyWith(fontSize: 12),
                    ),
                  ],
                  const Divider(height: 32),
                  _summary(m.stats),
                ],
              );
            },
          ),
      ],
    ),
  );
}

/// 월별 막대에 쓰는 값 — 날짜별 기록을 달마다 더한다
class _MonthlyStats {
  _MonthlyStats({
    required this.year,
    required this.perMonth,
    required this.currentMonth,
    required this.onlyThisMonth,
    required this.stats,
  });
  final int year;
  final List<int> perMonth; // 12칸, [0] = 1월
  final int currentMonth;
  final bool onlyThisMonth;
  final ReadingStats stats;
  int get total => perMonth.fold(0, (a, b) => a + b);

  factory _MonthlyStats.from(ReadingStats x, {required bool onlyThisMonth}) {
    final now = DateTime.now();
    final per = List<int>.filled(12, 0);
    for (final d in x.dailyReading) {
      if (d.date.year == now.year) per[d.date.month - 1] += d.paragraphsRead;
    }
    return _MonthlyStats(
      year: now.year,
      perMonth: per,
      currentMonth: now.month,
      onlyThisMonth: onlyThisMonth,
      stats: x,
    );
  }
}

/// 독서 통계 — 이번 주: 요일별 세로 막대 (막대 위 = 읽은 문단 수, 아래 = 요일)
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days});

  final List<DailyReading> days;

  @override
  Widget build(BuildContext context) {
    final maxV = days.fold<int>(
      0,
      (m, d) => d.paragraphsRead > m ? d.paragraphsRead : m,
    );
    const barMax = 220.0;
    return SizedBox(
      height: barMax + 64,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${d.paragraphsRead}문단',
                    maxLines: 1,
                    style: RidiText.sub.copyWith(
                      fontSize: 12,
                      color: d.paragraphsRead > 0
                          ? RidiColors.ink
                          : RidiColors.gray,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 36,
                    height: maxV == 0 || d.paragraphsRead == 0
                        ? 4
                        : (barMax * d.paragraphsRead / maxV).clamp(4.0, barMax),
                    decoration: BoxDecoration(
                      color: d.paragraphsRead > 0
                          ? RidiColors.blue
                          : RidiColors.grayLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(d.dayLabel, style: RidiText.sub),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 독서 통계 — 월별: 1월~12월 세로 막대 (막대 위 = 그 달 읽은 문단 수, 이번 달 글자는 굵게)
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.perMonth, required this.current});

  final List<int> perMonth;
  final int current;

  @override
  Widget build(BuildContext context) {
    final maxV = perMonth.fold<int>(0, (m, v) => v > m ? v : m);
    const barMax = 220.0;
    return SizedBox(
      height: barMax + 64,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 12; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    perMonth[i] > 0 ? '${perMonth[i]}' : '',
                    maxLines: 1,
                    style: RidiText.sub.copyWith(
                      fontSize: 12,
                      color: RidiColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 28,
                    height: maxV == 0 || perMonth[i] == 0
                        ? 4
                        : (barMax * perMonth[i] / maxV).clamp(4.0, barMax),
                    decoration: BoxDecoration(
                      color: perMonth[i] > 0
                          ? RidiColors.blue
                          : RidiColors.grayLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${i + 1}월',
                    style: RidiText.sub.copyWith(
                      color: i + 1 == current ? RidiColors.ink : null,
                      fontWeight: i + 1 == current ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(value, style: RidiText.bodyBold.copyWith(fontSize: 17)),
        Text(label, style: RidiText.sub.copyWith(fontSize: 12)),
      ],
    ),
  );
}

/// 자주 읽는 책 — 읽은 시간 많은 순 3권
class _TopBooks extends StatelessWidget {
  const _TopBooks({required this.store});

  final RidiStore store;

  @override
  Widget build(BuildContext context) {
    final top = store.topBooks;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('자주 읽는 책', style: RidiText.heading),
          const SizedBox(height: 10),
          if (top.isEmpty) const Text('책을 읽으면 여기에 모여요', style: RidiText.sub),
          for (var i = 0; i < top.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      style: RidiText.bodyBold.copyWith(
                        color: i == 0 ? RidiColors.blue : RidiColors.gray,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      top[i].title,
                      style: RidiText.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(_timeLabel(top[i].readMinutes), style: RidiText.sub),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// RIDI_SEARCH_01 — UC-07 도서 검색, UC-08 도서 다운로드(책장에 담기)
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  /// 검색 실행 — 2자 이상이면 최근 검색어에 남긴다. 결과는 책 목록을 제목·저자로 거른다
  /// (서버 연결 후 책이 많아지면 GET /api/books?q=)
  void _search(String s) {
    setState(() => _query = s.trim());
    if (s.trim().length >= 2) context.read<RidiStore>().addSearch(s);
  }

  @override
  Widget build(BuildContext context) =>
      ScreenTag('RIDI_SEARCH_01', child: _screen(context));

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    final hits = _query.isEmpty
        ? <RidiBook>[]
        : store.books
              .where(
                (b) => b.title.contains(_query) || b.author.contains(_query),
              )
              .toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----- 검색창 -----
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: RidiColors.panel,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          const Icon(
                            Icons.search_rounded,
                            color: RidiColors.gray,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _q,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              style: RidiText.body.copyWith(
                                fontSize: 16,
                                color: RidiColors.ink,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: '책 제목, 저자 검색',
                                hintStyle: RidiText.sub,
                              ),
                              // Keep the editing value untouched while an IME is
                              // composing Hangul. Whitespace is normalized only
                              // when a search is submitted (_search).
                              onChanged: (s) => setState(() => _query = s),
                              onSubmitted: _search,
                            ),
                          ),
                          if (_q.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(
                                Icons.cancel,
                                size: 18,
                                color: RidiColors.gray,
                              ),
                              onPressed: () {
                                _q.clear();
                                setState(() => _query = '');
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      '취소',
                      style: TextStyle(
                        fontFamily: RidiText.f,
                        fontSize: 15,
                        color: RidiColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ----- 최근 검색 -----
            if (_query.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                child: Row(
                  children: [
                    const Text('최근 검색', style: RidiText.heading),
                    const Spacer(),
                    TextButton(
                      onPressed: store.recentSearches.isEmpty
                          ? null
                          : store.clearSearches,
                      child: const Text(
                        '전체 삭제',
                        style: TextStyle(
                          fontFamily: RidiText.f,
                          fontSize: 13,
                          color: RidiColors.gray,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: store.recentSearches.isEmpty
                    ? const Text('최근 검색어가 없어요', style: RidiText.sub)
                    : Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final s in store.recentSearches)
                            RidiChip(
                              s,
                              on: false,
                              onTap: () {
                                _q.text = s;
                                _search(s);
                              },
                            ),
                        ],
                      ),
              ),
            ],
            // ----- 결과 -----
            if (_query.isNotEmpty)
              Expanded(
                child: hits.isEmpty
                    ? const RidiEmpty(
                        icon: Icons.search_off_rounded,
                        text: '검색 결과가 없어요',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '검색 결과 ${hits.length}',
                              style: RidiText.heading,
                            ),
                          ),
                          for (final b in hits) _ResultRow(book: b),
                        ],
                      ),
              )
            else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// 검색 결과 한 줄 — 내 책장에 있으면 "이어보기"(뷰어), 없으면 "책장에 담기"(UC-08)
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.book});

  final RidiBook book;

  @override
  Widget build(BuildContext context) {
    final store = context.read<RidiStore>();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: RidiColors.grayLight)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RidiCover(width: 70, height: 100),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text(
                  book.title,
                  style: RidiText.bodyBold.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text('${book.author} · ${book.chapters}장', style: RidiText.sub),
                const SizedBox(height: 8),
                Text(
                  book.owned ? '내 책장에 있음' : '무료',
                  style: RidiText.sub.copyWith(
                    color: book.owned ? RidiColors.gray : RidiColors.blue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: RidiOutlineButton(
              book.owned ? '이어보기' : '책장에 담기',
              onTap: () {
                if (book.owned) {
                  store.openBook(book.id);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RidiReaderScreen(bookId: book.id),
                    ),
                  );
                } else {
                  store.addToShelf(book.id);
                  ridiToast(context, '${book.title} — 내 책장에 담았어요');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
