import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'ridi_data.dart';
import 'ridi_dialogs.dart';
import 'ridi_reader_settings.dart';
import 'ridi_room_memos.dart';
import 'ridi_rooms.dart';
import 'ridi_store.dart';
import 'ridi_theme.dart';
import 'ridi_widgets.dart';
import '../../widgets/screen_tag.dart';

/// RIDI_READER_01 (본문) · RIDI_READER_02 (도구) — UC-05 책 읽기
/// 본문 가운데를 누르면 위·아래 도구가 나온다. 문장을 길게 누르면 형광펜·메모.
/// 방에서 열면(roomId) 같은 방 멤버의 메모가 문장 끝 말풍선으로 보이고, 내 형광펜·메모는 그 방에 공유된다.
///
/// 구성
/// - _RidiReaderScreenState: 페이지 나누기(_pages) · 페이지 이동(_goto / _gotoLine) · 위·아래 도구 열고 닫기
/// - _PageBody / _Column: 한 페이지(2단·1단)와 한 단
/// - _Line: 문장 한 줄 — 어절 선택 · 형광펜 · 메모 핀 · 방 메모 말풍선, 펜 메뉴(RIDI_READER_03)
/// - _TopBar / _BottomBar: 도구(RIDI_READER_02), _RoomBadge 말풍선, _Ribbon 책갈피 리본
/// 본문은 지금 ridi_data.dart 의 더미(봄봄 2장). 서버 연결 시 GET /api/books/{id}/chapters/{n}
const kFirstPage = 7; // 화면설계서의 "7 / 550" 과 맞춘 시작 페이지

class RidiReaderScreen extends StatefulWidget {
  const RidiReaderScreen({super.key, required this.bookId, this.roomId});

  final String bookId;
  final String? roomId;

  @override
  State<RidiReaderScreen> createState() => _RidiReaderScreenState();
}

class _RidiReaderScreenState extends State<RidiReaderScreen> {
  bool _chrome = false;
  late final PageController _controller;
  int _index = 0;
  int? _undoIndex; // 슬라이더로 건너뛰기 전 위치
  double? _dragging;
  String? _lastLayout;

  /// 마지막으로 읽던 페이지에서 연다 (책의 page 는 kFirstPage 부터 센다)
  @override
  void initState() {
    super.initState();
    final store = context.read<RidiStore>();
    _index = ((store.book(widget.bookId)?.page ?? kFirstPage) - kFirstPage).clamp(0, 999);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 본문을 페이지로 나눈다. 한 단에 담을 문장 수를 2단/1단 · 글자 크기 · 행간에 맞춰 조정하고,
  /// 장 첫 페이지는 장 제목 자리만큼 적게 담는다. 설정이 바뀌면 페이지 수가 달라진다(_screen 에서 위치 보정).
  List<_PageSpec> _pages(RidiStore store) {
    final twoColumn = store.twoColumn;
    var perColumn = twoColumn ? 7 : 12;
    if (store.fontScale > 1.1) perColumn -= 1;
    if (store.fontScale > 1.2) perColumn -= 1;
    if (store.lineHeightStep == 2) perColumn -= 1;
    if (store.lineHeightStep == 0) perColumn += 1;
    if (perColumn < 3) perColumn = 3;
    final pages = <_PageSpec>[];
    for (var c = 0; c < ridiChapters.length; c++) {
      final lines = ridiChapters[c].lines;
      var i = 0;
      while (i < lines.length) {
        final first = i == 0;
        final leftN = first ? perColumn - 3 : perColumn; // 첫 페이지는 장 제목 자리만큼 적게
        final rightN = twoColumn ? perColumn : 0;
        pages.add(_PageSpec(
          chapter: c,
          leftFrom: i,
          leftTo: (i + leftN).clamp(0, lines.length),
          rightFrom: (i + leftN).clamp(0, lines.length),
          rightTo: (i + leftN + rightN).clamp(0, lines.length),
          showTitle: first,
        ));
        i += leftN + rightN;
      }
    }
    return pages;
  }

  /// n번째 페이지로 이동 — remember 면 "되돌리기" 위치를 기억하고, 읽은 위치·읽은 장을 저장한다
  void _goto(int index, {bool remember = true}) {
    final store = context.read<RidiStore>();
    final pages = _pages(store);
    final i = index.clamp(0, pages.length - 1);
    if (remember) _undoIndex = _index;
    _controller.jumpToPage(i);
    setState(() => _index = i);
    store.setPage(widget.bookId, i + kFirstPage, chapter: pages[i].chapter);
  }

  /// 장·문장이 들어 있는 페이지로
  void _gotoLine(int chapter, int line) {
    final pages = _pages(context.read<RidiStore>());
    final i = pages.indexWhere((p) => p.chapter == chapter && ((line >= p.leftFrom && line < p.leftTo) || (line >= p.rightFrom && line < p.rightTo)));
    if (i >= 0) _goto(i);
  }

  @override
  Widget build(BuildContext context) => ScreenTag(_chrome ? 'RIDI_READER_02' : 'RIDI_READER_01', alignment: Alignment.bottomCenter, child: _screen(context));

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    final book = store.book(widget.bookId);
    final pages = _pages(store);
    final safeIndex = _index.clamp(0, pages.length - 1);
    // 단 수·글자 크기·행간이 바뀌면 페이지 수가 달라지므로, 그린 뒤 지금 위치로 다시 맞춘다
    final layout = '${store.twoColumn}/${store.fontScale}/${store.lineHeightStep}';
    if (_lastLayout != layout) {
      _lastLayout = layout;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.jumpToPage(safeIndex);
        setState(() => _index = safeIndex);
      });
    }
    final spec = pages[safeIndex];
    final page = safeIndex + kFirstPage;
    final bg = switch (store.paper) {
      PaperTheme.light => RidiColors.paperLight,
      PaperTheme.sepia => RidiColors.paperSepia,
      PaperTheme.dark => RidiColors.paperDark,
    };
    final fg = store.paper == PaperTheme.dark ? RidiColors.textOnDark : RidiColors.ink;
    final marked = store.hasBookmark(widget.bookId, page);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // ----- 본문 -----
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => setState(() => _chrome = !_chrome),
            child: PageView.builder(
              controller: _controller,
              itemCount: pages.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                store.setPage(widget.bookId, i + kFirstPage, chapter: pages[i].chapter);
              },
              itemBuilder: (_, i) => _PageBody(
                spec: pages[i],
                bookId: widget.bookId,
                roomId: widget.roomId,
                onBlankTap: () => setState(() => _chrome = !_chrome),
                page: i + kFirstPage,
                twoColumn: store.twoColumn,
                fg: fg,
              ),
            ),
          ),
          // ----- 아래 캡션 -----
          Positioned(
            left: 64,
            right: 64,
            bottom: 36,
            child: IgnorePointer(
              child: Row(children: [
                Text('Chapter ${spec.chapter + 1}', style: RidiText.sub.copyWith(fontSize: 14)),
                const Spacer(),
                Text('$page / $ridiTotalPages', style: RidiText.sub.copyWith(fontSize: 14)),
              ]),
            ),
          ),
          // ----- 책갈피 리본 -----
          if (marked)
            // 상태 표시줄(시계·배터리) 아래, 모서리 둥근 화면에서도 잘리지 않게 안쪽으로
            Positioned(top: MediaQuery.paddingOf(context).top, right: 40, child: const IgnorePointer(child: _Ribbon())),
          // ----- 도구 -----
          if (_chrome) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopBar(
                title: [
                  '${book?.title ?? ''} 1권',
                  if (widget.roomId != null) ?store.room(widget.roomId!)?.name,
                ].join('  ·  '),
                marked: marked,
                onBack: () => Navigator.of(context).pop(),
                onBookmark: () {
                  final on = store.toggleBookmark(
                    bookId: widget.bookId,
                    chapter: spec.chapter,
                    page: page,
                    chapterTitle: 'Chapter ${spec.chapter + 1}',
                  );
                  ridiToast(context, on ? '책갈피를 꽂았어요' : '책갈피를 뺐어요');
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomBar(
                page: page,
                ratio: _dragging ?? (pages.length <= 1 ? 0 : safeIndex / (pages.length - 1)),
                canUndo: _undoIndex != null,
                roomId: widget.roomId,
                onSlide: (v) => setState(() => _dragging = v),
                onSlideEnd: (v) {
                  final target = ((pages.length - 1) * v).round();
                  setState(() => _dragging = null);
                  _goto(target);
                },
                onUndo: () {
                  final back = _undoIndex;
                  if (back == null) return;
                  _undoIndex = null;
                  _goto(back, remember: false);
                },
                onChapters: () async {
                  final c = await showChapterList(context, current: spec.chapter);
                  if (c == null) return;
                  final target = pages.indexWhere((p) => p.chapter == c);
                  if (target >= 0) _goto(target);
                },
                onNote: () => showRidiNoteDialog(context, bookId: widget.bookId, onGoto: (p) => _goto((p - kFirstPage).clamp(0, pages.length - 1))),
                onRoomMemo: widget.roomId == null
                    ? null
                    : () => showRoomMemoDialog(context, roomId: widget.roomId!, bookId: widget.bookId, onGoto: _gotoLine),
                onView: () => showViewSettings(context),
                onViewer: () => showViewerSettings(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 한 페이지에 담을 범위 — 장 번호, 왼쪽 단·오른쪽 단의 문장 범위(from~to, to 는 제외), 장 제목 표시 여부
class _PageSpec {
  const _PageSpec({required this.chapter, required this.leftFrom, required this.leftTo, required this.rightFrom, required this.rightTo, required this.showTitle});

  final int chapter;
  final int leftFrom;
  final int leftTo;
  final int rightFrom;
  final int rightTo;
  final bool showTitle;
}

/// 한 페이지 — 2단이면 좌우 두 단, 1단이면 가운데 한 단(최대 폭 720)
class _PageBody extends StatelessWidget {
  const _PageBody({required this.spec, required this.bookId, this.roomId, this.onBlankTap, required this.page, required this.twoColumn, required this.fg});

  final _PageSpec spec;
  final String bookId;
  final String? roomId;
  final VoidCallback? onBlankTap;
  final int page;
  final bool twoColumn;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final left = _Column(spec: spec, bookId: bookId, roomId: roomId, onBlankTap: onBlankTap, page: page, from: spec.leftFrom, to: spec.leftTo, title: spec.showTitle ? 'Chapter ${spec.chapter + 1}' : null, fg: fg);
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 72, 64, 80),
      child: twoColumn
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: left),
              const SizedBox(width: 56),
              Expanded(child: _Column(spec: spec, bookId: bookId, roomId: roomId, onBlankTap: onBlankTap, page: page, from: spec.rightFrom, to: spec.rightTo, fg: fg)),
            ])
          : Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: left)),
    );
  }
}

/// 한 단 — (장 첫 페이지면) 장 제목 + 문장들
class _Column extends StatelessWidget {
  const _Column({required this.spec, required this.bookId, this.roomId, this.onBlankTap, required this.page, required this.from, required this.to, required this.fg, this.title});

  final _PageSpec spec;
  final String bookId;
  final String? roomId;
  final VoidCallback? onBlankTap;
  final int page;
  final int from;
  final int to;
  final Color fg;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<RidiStore>();
    final lines = ridiChapters[spec.chapter].lines;
    final style = TextStyle(fontFamily: RidiText.f, fontSize: 17 * store.fontScale, height: store.lineHeight, color: fg, fontWeight: FontWeight.w400);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(title!, style: TextStyle(fontFamily: 'NotoSerifKR', fontSize: 30 * store.fontScale, fontWeight: FontWeight.w700, color: fg)),
          SizedBox(height: 120 * store.fontScale),
        ],
        for (var i = from; i < to && i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _Line(bookId: bookId, roomId: roomId, onBlankTap: onBlankTap, chapter: spec.chapter, page: page, index: i, text: lines[i], style: style),
          ),
      ],
    );
  }
}

/// 문장 한 줄 — 길게 누른 어절부터 선택, 누른 채 끌면 선택이 늘어남 → 형광펜·메모.
/// 형광펜을 누르면 메모 편집, 방에서 읽을 때는 끝의 말풍선을 누르면 그 문장의 방 메모.
/// 한 문장에 형광펜 여러 개 가능 (어절 범위가 겹치지 않게).
class _Line extends StatefulWidget {
  const _Line({required this.bookId, this.roomId, required this.chapter, required this.page, required this.index, required this.text, required this.style, this.onBlankTap});

  final String bookId;
  final String? roomId;
  final int chapter;
  final int page;
  final int index;
  final String text;
  final TextStyle style;

  /// 형광펜이 아닌 곳을 누르면 (뷰어 도구 열고 닫기)
  final VoidCallback? onBlankTap;

  @override
  State<_Line> createState() => _LineState();
}

class _LineState extends State<_Line> {
  final _key = GlobalKey();
  int? _selFrom; // 길게 누르는 동안의 선택 (어절 번호)
  int? _selTo;

  // 마지막 build 의 어절별 글자 위치 (WidgetSpan 은 1글자로 셈)
  final _starts = <int>[];
  final _ends = <int>[];

  late List<String> _words = widget.text.trim().split(' ');

  @override
  void didUpdateWidget(covariant _Line old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _words = widget.text.trim().split(' ');
  }

  /// 화면 좌표 → 어절 번호
  int? _wordAt(Offset global) {
    final box = _key.currentContext?.findRenderObject();
    if (box is! RenderParagraph || _starts.isEmpty) return null;
    final o = box.getPositionForOffset(box.globalToLocal(global)).offset;
    for (var i = 0; i < _words.length; i++) {
      if (o >= _starts[i] && o < _ends[i]) return i;
    }
    if (o < _starts.first) return 0;
    for (var i = _words.length - 1; i >= 0; i--) {
      if (o >= _ends[i]) return i;
    }
    return null;
  }

  /// 선택 범위 (앞·뒤 순서로 정리)
  (int, int) get _sel {
    final a = _selFrom!, b = _selTo ?? _selFrom!;
    return a <= b ? (a, b) : (b, a);
  }

  /// 이 어절을 덮고 있는 내 형광펜 (없으면 null)
  RidiNote? _noteAt(List<RidiNote> mine, int word) => mine.where((n) => word >= n.wordStart(_words.length) && word <= n.wordEnd(_words.length)).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<RidiStore>();
    final style = widget.style;
    // 이 문장의 내 형광펜들 · 같은 방 남의 메모(말풍선용)
    final mine = store.notes
        .where((n) => n.mine && n.bookId == widget.bookId && n.kind == NoteKind.highlight && n.chapter == widget.chapter && n.line == widget.index)
        .toList()
      ..sort((a, b) => a.wordStart(_words.length).compareTo(b.wordStart(_words.length)));
    final others = widget.roomId == null || store.onlyMyNotes
        ? const <RidiNote>[]
        : store.roomNotes(widget.roomId!, widget.bookId).where((n) => !n.mine && n.chapter == widget.chapter && n.line == widget.index).toList();

    // ----- 어절 단위로 span 을 만들면서 글자 위치를 기록 -----
    final spans = <InlineSpan>[TextSpan(text: '  ', style: style)];
    var offset = 2;
    _starts.clear();
    _ends.clear();
    final selecting = _selFrom != null;
    final (sa, sb) = selecting ? _sel : (-1, -1);
    // 어절 하나(또는 그 뒤 공백)의 모양: 선택 중이면 파란 배경, 형광펜이면 색 배경, 밑줄이면 진한 색 밑줄
    TextStyle paint(RidiNote? note, bool selected) {
      if (selected) return style.copyWith(backgroundColor: RidiColors.blue.withValues(alpha: 0.28));
      if (note == null) return style;
      if (note.penStyle == PenStyle.underline) {
        return style.copyWith(decoration: TextDecoration.underline, decorationColor: RidiColors.penLines[note.colorIndex], decorationThickness: 2.2);
      }
      return style.copyWith(backgroundColor: RidiColors.penColors[note.colorIndex]);
    }

    for (var i = 0; i < _words.length; i++) {
      final note = _noteAt(mine, i);
      final inSel = i >= sa && i <= sb;
      _starts.add(offset);
      spans.add(TextSpan(text: _words[i], style: paint(note, inSel)));
      offset += _words[i].length;
      final last = i == _words.length - 1;
      // 같은 형광펜·밑줄 안의 어절 사이 공백도 칠한다
      final nextSame = !last && note != null && _noteAt(mine, i + 1) == note;
      final nextSel = !last && inSel && i + 1 <= sb;
      if (!last) {
        spans.add(TextSpan(text: ' ', style: paint(nextSame && !inSel ? note : null, nextSel)));
        offset += 1;
      }
      _ends.add(offset);
      // 형광펜 끝 어절 뒤에 메모 핀
      if (note != null && note.memo.isNotEmpty && i == note.wordEnd(_words.length)) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Icon(Icons.push_pin_rounded, size: 14 * store.fontScale, color: style.color)),
        ));
        offset += 1;
      }
    }
    if (others.isNotEmpty) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _RoomBadge(
          notes: others,
          locked: others.every((n) => store.isSpoiler(n, widget.roomId!)),
          scale: store.fontScale,
          onTap: () => showRoomMemoDialog(context, roomId: widget.roomId!, bookId: widget.bookId, chapter: widget.chapter, line: widget.index),
        ),
      ));
    }

    // 탭: 형광펜 위면 메모 창, 아니면 도구 열고 닫기
    // 길게 누르기: 누른 어절부터 선택 → 끌면 늘어남 → 놓으면 펜 메뉴(이미 칠한 곳이면 그 형광펜 편집)
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final w = _wordAt(d.globalPosition);
        final note = w == null ? null : _noteAt(mine, w);
        if (note == null) {
          widget.onBlankTap?.call();
          return;
        }
        showRidiMemoDialog(context, bookId: widget.bookId, chapter: widget.chapter, page: widget.page, line: widget.index, phrase: note.phrase, note: note, roomId: widget.roomId);
      },
      onLongPressStart: (d) {
        final w = _wordAt(d.globalPosition);
        if (w == null) return;
        HapticFeedback.selectionClick();
        setState(() => _selFrom = _selTo = w);
      },
      onLongPressMoveUpdate: (d) {
        if (_selFrom == null) return;
        final w = _wordAt(d.globalPosition);
        if (w != null && w != _selTo) setState(() => _selTo = w);
      },
      onLongPressEnd: (_) async {
        if (_selFrom == null) return;
        final (a, b) = _sel;
        // 누른 곳에 이미 형광펜이 있으면 그 형광펜을 편집
        final existing = mine.where((n) => n.wordStart(_words.length) <= b && n.wordEnd(_words.length) >= a).firstOrNull;
        await _openPenMenu(context, store, a, b, note: existing);
        if (mounted) setState(() => _selFrom = _selTo = null);
      },
      child: Text.rich(TextSpan(children: spans), key: _key, textAlign: TextAlign.justify),
    );
  }

  /// RIDI_READER_03 — 리디의 문장 선택 도구: [형광펜 | 밑줄] + 색 5개 + 메모 + (있으면) 지우기.
  /// 새 선택이면 색을 누를 때 고른 모양(형광펜/밑줄)으로 만들고, 이미 칠한 곳이면 모양·색 바꾸기 · 지우기.
  /// 모양은 마지막에 쓴 것을 기억한다(store.lastPenStyle).
  /// "메모 남기기"는 (없으면 분홍으로 만든 뒤) 메모 창으로. 방에서 읽는 중이면 그 방에 공유된다(메모 창에서 방을 더 고를 수 있음).
  Future<void> _openPenMenu(BuildContext context, RidiStore store, int from, int to, {RidiNote? note}) {
    final phrase = note?.phrase ?? _words.sublist(from, to + 1).join(' ');
    final roomId = widget.roomId;
    var penStyle = note?.penStyle ?? store.lastPenStyle;
    RidiNote add(int color) => store.addNote(
          bookId: widget.bookId,
          kind: NoteKind.highlight,
          chapter: widget.chapter,
          page: widget.page,
          line: widget.index,
          phrase: phrase,
          colorIndex: color,
          roomIds: [?roomId],
          penStyle: penStyle,
          wordFrom: from,
          wordTo: to,
        );
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      barrierColor: Colors.black26,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (ctx) => ScreenTag('RIDI_READER_03', alignment: Alignment.bottomRight, child: StatefulBuilder(builder: (ctx, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('“$phrase”', style: RidiText.body.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              [
                if (note == null) '누른 채 끌면 선택을 늘릴 수 있어요',
                if (note == null && roomId != null) '${store.room(roomId)?.name ?? '방'} 에 공유돼요',
                if (note != null) switch (store.sharedLabel(note)) { null => '나만 보기', final s => '$s 에 공유됨' },
              ].join('  ·  '),
              style: RidiText.sub,
            ),
            const SizedBox(height: 16),
            // 펜 모양 — 이미 칠한 곳이면 누르는 즉시 바뀐다
            Row(children: [
              for (final (s, label) in const [(PenStyle.highlight, '형광펜'), (PenStyle.underline, '밑줄')]) ...[
                RidiChip(label, on: penStyle == s, onTap: () {
                  setSheet(() => penStyle = s);
                  if (note != null) store.setNotePenStyle(note.id, s);
                }),
                const SizedBox(width: 8),
              ],
            ]),
            const SizedBox(height: 14),
            Row(children: [
              for (var c = 0; c < RidiColors.penColors.length; c++)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: InkWell(
                    onTap: () {
                      if (note == null) {
                        add(c);
                      } else {
                        store.setNoteColor(note.id, c);
                      }
                      Navigator.pop(ctx);
                    },
                    borderRadius: BorderRadius.circular(18),
                    // 형광펜 = 색 동그라미, 밑줄 = 가운데 "가" 아래 색 줄
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: penStyle == PenStyle.highlight ? RidiColors.penColors[c] : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: note?.colorIndex == c ? RidiColors.ink : (penStyle == PenStyle.highlight ? Colors.transparent : RidiColors.grayLight),
                          width: note?.colorIndex == c ? 2 : 1,
                        ),
                      ),
                      child: penStyle == PenStyle.highlight
                          ? null
                          : Text(
                              '가',
                              style: TextStyle(
                                fontFamily: RidiText.f,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: RidiColors.text,
                                decoration: TextDecoration.underline,
                                decorationColor: RidiColors.penLines[c],
                                decorationThickness: 3,
                              ),
                            ),
                    ),
                  ),
                ),
              const Spacer(),
              if (note != null)
                TextButton.icon(
                  onPressed: () {
                    store.deleteNotes([note.id]);
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: RidiColors.red),
                  label: const Text('지우기', style: TextStyle(fontFamily: RidiText.f, color: RidiColors.red)),
                ),
            ]),
            const SizedBox(height: 12),
            RidiOutlineButton('메모 남기기', icon: Icons.sticky_note_2_outlined, onTap: () {
              final n = note ?? add(4);
              Navigator.pop(ctx);
              showRidiMemoDialog(context, bookId: widget.bookId, chapter: widget.chapter, page: widget.page, line: widget.index, phrase: n.phrase, note: n, roomId: roomId);
            }),
          ]),
        ),
      ))),
    );
  }
}

// ---------------- 상단 도구 ----------------
/// 상단 도구 — 뒤로 · 책 제목(방이면 방 이름도) · 책갈피 켜기/끄기
class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.marked, required this.onBack, required this.onBookmark});

  final String title;
  final bool marked;
  final VoidCallback onBack;
  final VoidCallback onBookmark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: RidiColors.grayLight))),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22, color: RidiColors.gray), onPressed: onBack),
              Expanded(child: Text(title, textAlign: TextAlign.center, style: RidiText.body.copyWith(color: RidiColors.gray, fontSize: 16))),
              IconButton(
                tooltip: '책갈피',
                icon: Icon(marked ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded, size: 24, color: marked ? RidiColors.red : RidiColors.ink),
                onPressed: onBookmark,
              ),
              const SizedBox(width: 8),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------- 하단 도구 ----------------
/// 하단 도구 — 페이지 원 · 슬라이더(놓을 때 이동) · 되돌리기 · 목차 · 독서노트 · 방 메모 · 내 메모만 · AI 친구 · 보기 설정 · 뷰어 설정.
/// 방 메모 · 내 메모만 · AI 친구는 방에서 열었을 때만 보인다. "내 메모만"을 켜면 멤버·AI 말풍선이 숨는다.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.page,
    required this.ratio,
    required this.canUndo,
    required this.roomId,
    required this.onSlide,
    required this.onSlideEnd,
    required this.onUndo,
    required this.onChapters,
    required this.onNote,
    required this.onView,
    required this.onViewer,
    this.onRoomMemo,
  });

  final VoidCallback? onRoomMemo;
  final int page;
  final double ratio;
  final bool canUndo;
  final String? roomId;
  final ValueChanged<double> onSlide;
  final ValueChanged<double> onSlideEnd;
  final VoidCallback onUndo;
  final VoidCallback onChapters;
  final VoidCallback onNote;
  final VoidCallback onView;
  final VoidCallback onViewer;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: RidiColors.grayLight))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: RidiColors.grayLight)),
                  child: Text('$page / $ridiTotalPages', style: RidiText.sub.copyWith(fontSize: 11, color: RidiColors.ink)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      activeTrackColor: RidiColors.gray,
                      inactiveTrackColor: RidiColors.grayLight,
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12, elevation: 2),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(value: ratio.clamp(0.0, 1.0), onChanged: onSlide, onChangeEnd: onSlideEnd),
                  ),
                ),
                IconButton(
                  tooltip: '이동 전으로',
                  icon: Icon(Icons.undo_rounded, color: canUndo ? RidiColors.ink : RidiColors.grayLight),
                  onPressed: canUndo ? onUndo : null,
                ),
                const SizedBox(width: 16),
                _Tool(icon: Icons.format_list_bulleted_rounded, label: '목차', onTap: onChapters),
                _Tool(icon: Icons.sticky_note_2_outlined, label: '독서노트', onTap: onNote),
                if (onRoomMemo != null) _Tool(icon: Icons.forum_outlined, label: '방 메모', onTap: onRoomMemo!),
                if (roomId != null)
                  Builder(builder: (context) {
                    final store = context.watch<RidiStore>();
                    final on = store.onlyMyNotes;
                    return _Tool(
                      icon: on ? Icons.person_rounded : Icons.person_outline_rounded,
                      label: '내 메모만',
                      on: on,
                      onTap: () {
                        store.setOnlyMyNotes(!on);
                        ridiToast(context, on ? '멤버 메모도 보여요' : '내 메모만 보여요');
                      },
                    );
                  }),
                if (roomId != null)
                  _Tool(
                    icon: Icons.smart_toy_outlined,
                    label: 'AI 친구',
                    onTap: () => showPersonaPicker(context, roomId: roomId!),
                  ),
                _Tool(icon: Icons.text_fields_rounded, label: '보기 설정', onTap: onView),
                _Tool(icon: Icons.settings_outlined, label: '뷰어 설정', onTap: onViewer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 하단 도구 버튼 하나 (아이콘 + 글자). on = 켜진 상태(파랑)
class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap, this.on = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 78,
        height: 60,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 26, color: on ? RidiColors.blue : RidiColors.ink),
          const SizedBox(height: 6),
          Text(label, style: RidiText.sub.copyWith(fontSize: 11, color: on ? RidiColors.blue : RidiColors.gray, fontWeight: on ? FontWeight.w700 : null)),
        ]),
      ),
    );
  }
}

/// 문장 끝 방 메모 말풍선 — 첫 멤버 아바타 + 개수. 전부 스포일러면 자물쇠
class _RoomBadge extends StatelessWidget {
  const _RoomBadge({required this.notes, required this.locked, required this.scale, required this.onTap});

  final List<RidiNote> notes;
  final bool locked;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final first = notes.first;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: EdgeInsets.fromLTRB(3 * scale, 2 * scale, 8 * scale, 2 * scale),
        decoration: BoxDecoration(
          color: locked ? RidiColors.panel : const Color(0xFFE8F2FC),
          borderRadius: BorderRadius.circular(14 * scale),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (locked)
            Padding(padding: EdgeInsets.all(3 * scale), child: Icon(Icons.lock_outline_rounded, size: 14 * scale, color: RidiColors.gray))
          else
            RidiAvatar(label: first.author, ai: first.ai, size: 20 * scale),
          SizedBox(width: 4 * scale),
          Text('${notes.length}', style: TextStyle(fontFamily: RidiText.f, fontSize: 12 * scale, fontWeight: FontWeight.w700, color: locked ? RidiColors.gray : RidiColors.blue)),
        ]),
      ),
    );
  }
}

/// 책갈피 리본 — 위 가장자리에 매달린 빨간 띠 (아래는 V 홈)
class _Ribbon extends StatelessWidget {
  const _Ribbon();

  @override
  Widget build(BuildContext context) => const CustomPaint(size: Size(22, 38), painter: _RibbonPainter());
}

/// 위는 평평하고 아래는 V 로 파인 리본 모양 + 옅은 그림자
class _RibbonPainter extends CustomPainter {
  const _RibbonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - 8)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, Paint()..color = RidiColors.red);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
