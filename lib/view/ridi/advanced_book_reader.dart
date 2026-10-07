import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/api_client.dart';
import '../../model/book.dart';
import '../../model/shared_room_note.dart';
import '../../viewmodel/book_viewmodel.dart';
import '../../repository/reading_room_repository.dart';
import '../../repository/ai_reading_repository.dart';
import 'reading_rooms_screen.dart' show showSharedNoteComments;
import 'ridi_store.dart';

enum ReaderContextKind { personal, readingRoom }

/// A reader route explicitly owns either personal or one room's data.
class ReaderContext {
  const ReaderContext.personal()
    : kind = ReaderContextKind.personal,
      roomId = null;
  const ReaderContext.readingRoom(this.roomId)
    : kind = ReaderContextKind.readingRoom;
  final ReaderContextKind kind;
  final int? roomId;
  bool get isReadingRoom => kind == ReaderContextKind.readingRoom;
}

class AdvancedBookReaderScreen extends StatefulWidget {
  const AdvancedBookReaderScreen({
    super.key,
    required this.bookId,
    this.readerContext = const ReaderContext.personal(),
  });
  final int bookId;
  final ReaderContext readerContext;
  @override
  State<AdvancedBookReaderScreen> createState() =>
      _AdvancedBookReaderScreenState();
}

class _AdvancedBookReaderScreenState extends State<AdvancedBookReaderScreen> {
  late PageController _controller;
  final _pages = <_Page>[];
  int _page = 0, _order = 1;
  bool _ready = false,
      _controls = false,
      _sheetOpen = false,
      _twoColumns = false;
  bool _savingHighlight = false;
  List<ReadingNote> _sharedHighlights = const [];
  List<SharedRoomNote> _sharedMemos = const [];
  List<AiReadingFriend> _aiFriends = const [];
  final Set<int> _selectedAiFriendIds = <int>{};

  final Map<int, List<AiReadingNote>> _aiNotesByFriend =
  <int, List<AiReadingNote>>{};
  String? _layoutKey;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = context.read<BookViewModel>();
      await vm.loadReader(widget.bookId);
      final p = vm.content?.paragraphs ?? const <BookParagraph>[];
      if (!mounted || p.isEmpty) return;
      final saved = vm.readingProgress?.lastReadPosition ?? p.first.order;
      // Progress is a stable paragraph_order, not a transient page index.
      // Older/deleted paragraph data falls back to the closest valid order.
      _order = p
          .reduce(
            (closest, candidate) =>
                (candidate.order - saved).abs() < (closest.order - saved).abs()
                ? candidate
                : closest,
          )
          .order;
      _ready = true;
      await _wake(vm.readerSettings.keepScreenOn);
      if (mounted) setState(() {});
      unawaited(_loadSharedHighlights());
    });
  }

  Future<void> _wake(bool enabled) =>
      enabled ? WakelockPlus.enable() : WakelockPlus.disable();

  Future<void> _loadSharedHighlights() async {
    final roomId = widget.readerContext.roomId;
    if (roomId == null || !mounted) return;
    final token = context.read<RidiStore>().accessToken;
    try {
      final notes = await ReadingRoomRepository(
        ApiClient(tokenProvider: () => token),
      ).sharedNotes(roomId, bookId: widget.bookId);
      if (!mounted) return;
      setState(() {
        _sharedHighlights = notes
            .where(
              (note) =>
                  !note.isSpoilerLocked &&
                  note.type == 'HIGHLIGHT' &&
                  note.startOffset != null &&
                  note.endOffset != null,
            )
            .map(_asReaderHighlight)
            .toList();
        // Keep shared memos separate from private ReadingNote state. The
        // server has already applied room/book membership and spoiler policy.
        _sharedMemos = notes
            .where((note) => note.type == 'MEMO')
            .toList();
      });
    } on ApiException {
      // Shared-note rendering is supplementary. The room note list keeps a
      // visible retry state, while a transient refresh failure must not block
      // the reader or reveal a server message.
    }
  }

  ReadingNote _asReaderHighlight(SharedRoomNote note) => ReadingNote(
    id: -note.id,
    type: ReaderNoteType.highlight,
    paragraphOrder: note.paragraphOrder,
    selectedText: note.selectedText,
    startOffset: note.startOffset,
    endOffset: note.endOffset,
    highlightColor: note.highlightColor,
    preview: '',
    createdAt: note.createdAt,
  );
  ReadingNote _asAiReaderHighlight(AiReadingNote note) => ReadingNote(
    id: -1000000000 - note.id,
    type: ReaderNoteType.highlight,
    paragraphOrder: note.paragraphOrder,
    selectedText: note.selectedText,
    startOffset: note.startOffset,
    endOffset: note.endOffset,
    highlightColor: 'BLUE',
    preview: note.content,
    createdAt: null,
  );
  Future<void> _save() async {
    _timer?.cancel();
    final p =
        context.read<BookViewModel>().content?.paragraphs ??
        const <BookParagraph>[];
    if (p.isNotEmpty)
      await context.read<BookViewModel>().saveReaderProgress(
        widget.bookId,
        _order,
        p.last.order,
      );
  }

  void _debounceSave() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), _save);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable();
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _back() async {
    if (_sheetOpen) return true;
    await _save();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BookViewModel>();
    final content = vm.content;
    return WillPopScope(
      onWillPop: _back,
      child: Scaffold(
        backgroundColor: _colors(vm.readerSettings).$1,
        body: vm.isReaderLoading
            ? const Center(child: CircularProgressIndicator())
            : content == null
            ? Center(child: Text(vm.readerErrorMessage ?? '본문을 불러올 수 없습니다.'))
            : LayoutBuilder(
                builder: (context, c) {
                  _schedulePagination(
                    content.paragraphs,
                    vm.readerSettings,
                    c,
                    MediaQuery.textScalerOf(context),
                  );
                  if (_pages.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Stack(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _sheetOpen
                            ? null
                            : () => setState(() => _controls = !_controls),
                        child: PageView.builder(
                          controller: _controller,
                          itemCount: _pages.length,
                          onPageChanged: (i) {
                            if (_pages.isEmpty) return;
                            setState(() {
                              _page = i;
                              _order = _pages[i].firstOrder;
                            });
                            _debounceSave();
                          },
                          itemBuilder: (_, i) => _ReaderPage(
                            page: _pages[i.clamp(0, _pages.length - 1)],
                            settings: vm.readerSettings,
                            twoColumns: _twoColumns,
                            highlights: vm.readerSettings.showHighlights ? [
                              // 내가 직접 만든 형광펜
                              ...vm.readingNotes.where(
                                    (n) => n.type == ReaderNoteType.highlight,
                              ),

                              // 교환독서 상대방 형광펜
                              ..._sharedHighlights,

                              // 선택한 AI 친구가 만든 형광펜
                              ..._selectedAiFriendIds
                                  .expand(
                                    (friendId) =>
                                _aiNotesByFriend[friendId] ?? const <AiReadingNote>[],
                              )
                                  .map(_asAiReaderHighlight),
                            ] : const <ReadingNote>[],
                            onHighlight: _saveHighlight,
                            onHighlightTap: _openHighlightMenu,
                            memos: vm.readingNotes
                                .where((n) => n.type == ReaderNoteType.memo)
                                .toList(),
                            roomMemoCounts: {
                              for (final memo in _sharedMemos)
                                memo.paragraphOrder:
                                    _sharedMemos.where((item) => item.paragraphOrder == memo.paragraphOrder).length,
                            },
                            onMemo: _saveSelectionMemo,
                            onShowMemos: _showParagraphMemos,
                          ),
                        ),
                      ),
                      if (_controls) _top(vm),
                      if (_controls) _bottom(vm),
                    ],
                  );
                },
              ),
      ),
    );
  }

  (Color, Color) _colors(ReaderSettings s) => switch (s.theme) {
    ReaderPaperTheme.dark => (const Color(0xff1d1d20), const Color(0xfff5f0e7)),
    ReaderPaperTheme.sepia => (
      const Color(0xfff4e8d0),
      const Color(0xff493b2d),
    ),
    _ => (const Color(0xfffffefa), const Color(0xff262626)),
  };
  void _schedulePagination(
    List<BookParagraph> p,
    ReaderSettings s,
    BoxConstraints c,
    TextScaler textScaler,
  ) {
    final two = s.twoColumn && c.maxWidth >= 700;
    final key =
        '${c.maxWidth.toInt()}:${c.maxHeight.toInt()}:${s.fontScale}:${s.lineHeightStep}:$two:${p.length}:$textScaler';
    if (!_ready || _layoutKey == key || c.maxWidth <= 0 || c.maxHeight <= 0)
      return;
    _layoutKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _layoutKey != key) return;
      final pages = _paginate(p, s, c.maxWidth, c.maxHeight, two, textScaler);
      final at = pages.indexWhere((e) => e.contains(_order));
      final targetPage = pages.isEmpty
          ? 0
          : (at < 0 ? 0 : at.clamp(0, pages.length - 1));
      // On the first layout there is no attached PageView yet.  Recreate the
      // controller with its true initial page so the user never sees page 0
      // flash before the saved paragraph's page.
      if (!_controller.hasClients) {
        _controller.dispose();
        _controller = PageController(initialPage: targetPage);
      }
      setState(() {
        _pages
          ..clear()
          ..addAll(pages);
        _page = targetPage;
        _twoColumns = two;
      });
      // The PageView is created by the setState above.  Jumping in the same
      // callback runs before it attaches to PageController, so it was silently
      // skipped and the controller's initial page (0) won.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _layoutKey == key &&
            _controller.hasClients &&
            pages.isNotEmpty)
          _controller.jumpToPage(targetPage);
      });
    });
  }

  List<_Page> _paginate(
    List<BookParagraph> all,
    ReaderSettings s,
    double width,
    double height,
    bool two,
    TextScaler textScaler,
  ) {
    final style = TextStyle(
      fontFamily: 'NotoSerifKR',
      fontSize: 18 * s.fontScale,
      height: [1.6, 1.85, 2.15][s.lineHeightStep],
    );
    // The rendered page has 142px vertical padding. Keep additional room for
    // font metrics/margins so a Column never exceeds the PageView viewport.
    final columnWidth = (width - (two ? 86 : 60)) / (two ? 2 : 1),
        limit = height - 200;
    final result = <_Page>[];
    var columns = <List<_Slice>>[[]];
    var used = 0.0;
    void next() {
      if (columns.length < (two ? 2 : 1)) {
        columns.add([]);
        used = 0;
      } else {
        result.add(_Page(columns));
        columns = [[]];
        used = 0;
      }
    }

    for (final para in all) {
      // Keep the source string and its offsets intact.  The offsets sent to
      // the API are always offsets into BookParagraph.text, never a trimmed
      // or reflowed display string.
      var start = 0;
      while (start < para.text.length) {
        final rest = para.text.substring(start);
        final h = _height(rest, style, columnWidth, textScaler);
        if (used + h + 16 <= limit) {
          columns.last.add(_Slice(para.order, start, rest));
          used += h + 16;
          start = para.text.length;
        } else if (h <= limit && columns.last.isNotEmpty) {
          next();
        } else {
          var cut = _fit(
            rest,
            style,
            columnWidth,
            limit - used - 8,
            textScaler,
          );
          if (cut <= 0) {
            if (columns.last.isNotEmpty) {
              next();
              continue;
            }
            cut = 1;
          }
          columns.last.add(_Slice(para.order, start, rest.substring(0, cut)));
          start += cut;
          next();
        }
      }
    }
    if (columns.any((e) => e.isNotEmpty)) result.add(_Page(columns));
    return result;
  }

  double _height(
    String text,
    TextStyle style,
    double width,
    TextScaler textScaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: width);
    return painter.height;
  }

  int _fit(
    String text,
    TextStyle style,
    double width,
    double maxHeight,
    TextScaler textScaler,
  ) {
    var lo = 1, hi = text.length, best = 0;
    while (lo <= hi) {
      final m = (lo + hi) >> 1;
      if (_height(text.substring(0, m), style, width, textScaler) <=
          maxHeight) {
        best = m;
        lo = m + 1;
      } else {
        hi = m - 1;
      }
    }
    final space = text.lastIndexOf(RegExp(r'\s'), best);
    return space > best ~/ 2 ? space + 1 : best;
  }

  Widget _top(BookViewModel vm) {
    final fg = _colors(vm.readerSettings).$2;
    final chapters = vm.readerChapters
        .where((c) => c.startParagraphOrder <= _order)
        .toList();
    final title = chapters.isEmpty ? vm.content!.title : chapters.last.title;
    final marked = vm.readingNotes.any(
      (n) => n.type == ReaderNoteType.bookmark && n.paragraphOrder == _order,
    );
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          color: _colors(vm.readerSettings).$1.withValues(alpha: .97),
          child: Row(
            children: [
              IconButton(
                onPressed: () async {
                  await _save();
                  if (mounted) Navigator.pop(context);
                },
                icon: Icon(Icons.arrow_back_ios_new, color: fg),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: () => _bookmark(vm),
                icon: Icon(
                  marked ? Icons.bookmark : Icons.bookmark_border,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _bookmark(BookViewModel vm) async {
    final hits = vm.readingNotes
        .where(
          (n) =>
              n.type == ReaderNoteType.bookmark && n.paragraphOrder == _order,
        )
        .toList();
    if (hits.isEmpty) {
      await vm.addNote(widget.bookId, ReaderNoteType.bookmark, _order);
    } else {
      await vm.deleteNote(widget.bookId, hits.first.id);
    }
  }

  Widget _bottom(BookViewModel vm) {
    final total = _pages.length, fg = _colors(vm.readerSettings).$2;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Container(
          color: _colors(vm.readerSettings).$1.withValues(alpha: .97),
          padding: const EdgeInsets.fromLTRB(18, 7, 18, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_page + 1} / $total',
                style: TextStyle(color: fg, fontSize: 12),
              ),
              Slider(
                value: total < 2 ? 0 : _page / (total - 1),
                onChanged: (v) {
                  final n = (v * (total - 1)).round();
                  if (n != _page) {
                    _controller.jumpToPage(n);
                    setState(() {
                      _page = n;
                      _order = _pages[n].firstOrder;
                    });
                  }
                },
                onChangeEnd: (_) => _save(),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _menu(Icons.format_list_bulleted, '목차', _chapters),
                  _menu(Icons.sticky_note_2_outlined, '독서노트', _notes),
                  _menu(Icons.text_fields, '보기 설정', _viewSettings),
                  _menu(Icons.tune, '뷰어 설정', _viewerSettings),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(IconData icon, String label, VoidCallback action) =>
      TextButton.icon(
        onPressed: action,
        icon: Icon(icon, size: 26),
        label: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      );

  /// 창 열기 — 목차·독서노트는 화면 가운데, 보기·뷰어 설정은 오른쪽 아래(메뉴 바로 위)에 뜬다.
  Future<void> _open(
    Widget sheet, {
    _SheetPlace place = _SheetPlace.center,
  }) async {
    setState(() => _sheetOpen = true);
    final child = _SheetMode(place: place, child: sheet);
    if (place == _SheetPlace.center) {
      await showDialog<void>(
        context: context,
        builder: (_) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(color: Colors.transparent, child: child),
            ),
          ),
        ),
      );
    } else {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '닫기',
        barrierColor: Colors.black26,
        pageBuilder: (_, _, _) => SafeArea(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
              child: SizedBox(
                width: 420,
                child: Material(color: Colors.transparent, child: child),
              ),
            ),
          ),
        ),
      );
    }
    if (mounted) setState(() => _sheetOpen = false);
  }

  /// 목차 — "1장, 2장 …" 한 줄씩 (리디 목차처럼). 지금 읽는 장은 굵게.
  void _chaptersFixed() {
    final chapters = context.read<BookViewModel>().readerChapters;
    final current = chapters.lastIndexWhere(
      (c) => c.startParagraphOrder <= _order,
    );
    _open(
      _Sheet(
        title: '목차',
        child: chapters.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('이 책에는 확인된 목차 정보가 없습니다.'),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () async {
                          await context.read<BookViewModel>().loadReader(widget.bookId);
                          if (mounted) {
                            Navigator.pop(context);
                            _chaptersFixed();
                          }
                        },
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
          itemCount: chapters.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, color: Color(0xFFEDEDED)),
          itemBuilder: (_, i) {
            final c = chapters[i];
            final label = '${c.number}장';
            final on = i == current;
            return InkWell(
              onTap: () {
                Navigator.pop(context);
                _go(c.startParagraphOrder);
              },
              child: Container(
                color: on ? const Color(0xFFF5F5F5) : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                    if (c.title.trim().isNotEmpty &&
                        c.title.trim() != label) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF8A8A8A),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /*
  void _chapters()=>_open(_Sheet(title:'목차',child:ListView(children:context.read<BookViewModel>().readerChapters.map((c)=>ListTile(title:Text(c.title),subtitle:Text('문단 ${c.startParagraphOrder}'),onTap:(){Navigator.pop(context);_go(c.startParagraphOrder);}).toList()))));
  */
  void _chapters() => _chaptersFixed();
  void _notes() => _open(
    _Notes(
      bookId: widget.bookId,
      order: _order,
      onGo: _go,
      roomId: widget.readerContext.roomId,
      aiFriends: _aiFriends,
      aiNotesByFriend: _aiNotesByFriend,
    ),
  );

  Future<void> _viewSettings() async {
    final store = context.read<RidiStore>();

    final repository = AiReadingRepository(
      ApiClient(
        tokenProvider: () => store.accessToken,
      ),
    );

    try {
      // 보기 설정을 열 때 서버에서 현재 사용 가능한 AI 친구 목록을 가져온다.
      final friends = await repository.getDefaultFriends();

      if (!mounted) return;

      _aiFriends = friends;

      await _open(
        place: _SheetPlace.corner,
        _ViewSettings(
          onChange: (s) async {
            try {
              await context.read<BookViewModel>().saveSettings(s);
              _layoutKey = null;
            } on ApiException catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  SnackBar(content: Text(e.message)),
                );
              }
            }
          },

          aiFriends: _aiFriends,

          selectedAiFriendIds: _selectedAiFriendIds,

          onAiFriendDone: (selectedIds) async {
            final loadedNotes =
            <int, List<AiReadingNote>>{};

            try {
              // 선택된 친구들만 처리한다.
              for (final friendId in selectedIds) {
                // 먼저 DB에 기존 메모가 있는지 확인
                var notes = await repository.getNotes(
                  bookId: widget.bookId,
                  friendId: friendId,
                );

                // 기존 메모가 없을 때만 Gemini 생성
                if (notes.isEmpty) {
                  notes = await repository.generateNotes(
                    bookId: widget.bookId,
                    friendId: friendId,
                  );
                }

                loadedNotes[friendId] = notes;
              }

              if (!mounted) return;

              setState(() {
                // 완료를 눌렀을 때만 실제 선택 상태 변경
                _selectedAiFriendIds
                  ..clear()
                  ..addAll(selectedIds);

                // 화면에서 사용할 AI 메모 갱신
                _aiNotesByFriend
                  ..clear()
                  ..addAll(loadedNotes);
              });

              // 모든 작업이 성공한 뒤 보기 설정 팝업 닫기
              if (mounted) {
                Navigator.of(context).pop();
              }
            } on ApiException catch (e) {
              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'AI 메모를 불러오지 못했습니다: ${e.message}',
                  ),
                ),
              );

              // 실패하면 팝업은 그대로 둔다.
              rethrow;
            } catch (e) {
              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'AI 메모를 불러오는 중 오류가 발생했습니다.',
                  ),
                ),
              );

              rethrow;
            }
          },
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'AI 친구 목록을 불러오지 못했습니다: ${e.message}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'AI 친구 목록을 불러오는 중 오류가 발생했습니다.',
          ),
        ),
      );
    }
  }

  void _viewerSettings() => _open(
    place: _SheetPlace.corner,
    _ViewerSettings(
      onChange: (s) async {
        await context.read<BookViewModel>().saveSettings(s);
        await _wake(s.keepScreenOn);
        _layoutKey = null;
      },
    ),
  );

  void _go(int order) {
    final i = _pages.indexWhere((e) => e.contains(order));
    if (i >= 0) {
      _controller.jumpToPage(i);
      setState(() {
        _page = i;
        _order = order;
      });
      _debounceSave();
    }
  }

  Future<void> _openHighlightMenu(ReadingNote note) async {
    // Shared and AI highlights are rendered with negative local ids. They are
    // intentionally read-only here; the server remains the final authority.
    if (!mounted || widget.readerContext.isReadingRoom || note.id <= 0) return;
    final action = await showModalBottomSheet<_HighlightAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('삭제'),
              onTap: () => Navigator.pop(sheetContext, _HighlightAction.delete),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('형광펜 색깔'),
              onTap: () => Navigator.pop(sheetContext, _HighlightAction.color),
            ),
            ListTile(
              leading: const Icon(Icons.mode_comment_outlined),
              title: const Text('메모'),
              onTap: () => Navigator.pop(sheetContext, _HighlightAction.memo),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    if (action == _HighlightAction.delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('형광펜 삭제'),
          content: const Text('선택한 형광펜을 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        await context.read<BookViewModel>().deleteNote(widget.bookId, note.id);
      } on ApiException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
      }
      return;
    }

    if (action == _HighlightAction.color) {
      final color = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Wrap(
            children: ['#FFF59D', '#A5D6A7', '#90CAF9', '#FFCCBC', '#CE93D8']
                .map(
                  (value) => ListTile(
                    leading: CircleAvatar(backgroundColor: _highlightColor(value)),
                    title: Text(value),
                    onTap: () => Navigator.pop(sheetContext, value),
                  ),
                )
                .toList(),
          ),
        ),
      );
      if (!mounted || color == null) return;
      try {
        await context.read<BookViewModel>().updateNote(
              widget.bookId,
              note.id,
              color: color,
            );
      } on ApiException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
      }
      return;
    }

    final start = note.startOffset;
    final end = note.endOffset;
    final text = note.selectedText;
    if (start == null || end == null || text == null || end <= start) return;
    await _saveSelectionMemo(_TextSelection(note.paragraphOrder, start, end, text));
  }

  Future<void> _saveHighlight(_TextSelection selection) async {
    if (selection.start < 0 ||
        selection.end <= selection.start ||
        selection.selectedText.trim().isEmpty)
      return;
    if (_savingHighlight) return;
    final vm = context.read<BookViewModel>();
    final highlightColor = vm.readerSettings.highlightColor;
    setState(() => _savingHighlight = true);
    try {
      if (widget.readerContext.isReadingRoom) {
        await _createRoomNote(
          selection,
          type: 'HIGHLIGHT',
          highlightColor: highlightColor,
        );
      } else {
        await vm.addNote(
          widget.bookId,
          ReaderNoteType.highlight,
          selection.paragraphOrder,
          selectedText: selection.selectedText,
          startOffset: selection.start,
          endOffset: selection.end,
          color: highlightColor,
        );
      }
    } on ApiException catch (e) {
      // Reapplying an identical range is a successful last-write-wins action.
      // Any remaining error is a real validation/network/authorization error.
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_sharedNoteError(e))));
    } finally {
      if (mounted) setState(() => _savingHighlight = false);
    }
  }

  Future<void> _saveSelectionMemo(_TextSelection selection) async {
    if (selection.start < 0 ||
        selection.end <= selection.start ||
        selection.selectedText.trim().isEmpty)
      return;
    await showDialog<bool>(
      context: context,
      builder: (_) => _MemoEditorDialog(
        selectedText: selection.selectedText,
        onSave: (memo) async {
          if (widget.readerContext.isReadingRoom) {
            await _createRoomNote(selection, type: 'MEMO', content: memo);
          } else {
            await context.read<BookViewModel>().addNote(
              widget.bookId,
              ReaderNoteType.memo,
              selection.paragraphOrder,
              memo: memo,
              selectedText: selection.selectedText,
              startOffset: selection.start,
              endOffset: selection.end,
            );
          }
        },
      ),
    );
  }

  Future<void> _createRoomNote(
    _TextSelection selection, {
    required String type,
    String? content,
    String? highlightColor,
  }) async {
    final roomId = widget.readerContext.roomId;
    if (roomId == null) throw ApiException('독서방 정보를 찾을 수 없습니다.');
    final roomRepository = ReadingRoomRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    await roomRepository.createSharedNote(roomId, {
      'bookId': widget.bookId,
      'type': type,
      'paragraphOrder': selection.paragraphOrder,
      'startOffset': selection.start,
      'endOffset': selection.end,
      'selectedText': selection.selectedText,
      if (content != null) 'content': content,
      if (highlightColor != null) 'highlightColor': highlightColor,
    });
    await _loadSharedHighlights();
  }

  String _sharedNoteError(ApiException error) => switch (error.errorCode) {
    'ROOM_MEMBER_REQUIRED' => '독서방 참여자만 공유할 수 있습니다.',
    'ROOM_BOOK_REQUIRED' => '이 독서방에는 대표 도서가 설정되어 있지 않습니다.',
    'DUPLICATE_SHARED_HIGHLIGHT' => '이미 이 독서방에 공유한 형광펜입니다.',
    'INVALID_SHARED_NOTE' => '공유할 메모 또는 형광펜 범위를 확인해주세요.',
    _ when error.isUnauthorized => '로그인이 만료되었습니다. 다시 로그인해주세요.',
    _ => '공유 독서노트를 저장하지 못했습니다. 잠시 후 다시 시도해주세요.',
  };

  Future<void> _showParagraphMemos(
    int paragraphOrder,
    BuildContext anchorContext,
  ) async {
    if (!mounted) return;
    if (widget.readerContext.isReadingRoom) {
      await _showSharedParagraphMemos(paragraphOrder, anchorContext);
      return;
    }
    final notes = context
        .read<BookViewModel>()
        .readingNotes
        .where(
          (note) =>
              note.type == ReaderNoteType.memo &&
              note.paragraphOrder == paragraphOrder,
        )
        .toList();
    if (notes.isEmpty) return;
    final anchor = anchorContext.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchor == null || overlay == null) return;
    final topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      topLeft & anchor.size,
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<ReadingNote>(
      context: context,
      position: position,
      constraints: const BoxConstraints(maxWidth: 300, maxHeight: 360),
      items: [
        for (final note in notes)
          PopupMenuItem<ReadingNote>(
            value: note,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                note.memoContent ?? '메모',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                note.createdAt == null
                    ? '내 메모'
                    : '${note.createdAt!.year}.${note.createdAt!.month.toString().padLeft(2, '0')}.${note.createdAt!.day.toString().padLeft(2, '0')}.',
              ),
            ),
          ),
      ],
    );
    if (!mounted || selected == null) return;
    _open(_ParagraphMemos(bookId: widget.bookId, paragraphOrder: paragraphOrder));
  }

  Future<void> _showSharedParagraphMemos(
    int paragraphOrder,
    BuildContext anchorContext,
  ) async {
    final notes = _sharedMemos
        .where((note) => note.paragraphOrder == paragraphOrder)
        .toList();
    if (!mounted || notes.isEmpty) return;
    final anchor = anchorContext.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchor == null || overlay == null) return;
    final topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      topLeft & anchor.size,
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<SharedRoomNote>(
      context: context,
      position: position,
      constraints: const BoxConstraints(maxWidth: 300, maxHeight: 360),
      items: [
        for (final note in notes)
          PopupMenuItem<SharedRoomNote>(
            value: note,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(note.nickname),
              subtitle: Text(
                note.isSpoilerLocked
                    ? '내 진행률 이후 내용입니다.'
                    : (note.content ?? note.selectedText ?? '메모'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: note.createdAt == null
                  ? null
                  : Text(
                      '${note.createdAt!.month}/${note.createdAt!.day}',
                      style: const TextStyle(fontSize: 11),
                    ),
            ),
          ),
      ],
    );
    if (!mounted || selected == null) return;
    final detail = selected.isSpoilerLocked
        ? '내 진행률 이후 내용입니다.'
        : (selected.content ?? selected.selectedText ?? '메모 내용이 없습니다.');
    await showMenu<void>(
      context: context,
      position: position,
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 420),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(selected.nickname, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(detail),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Slice {
  const _Slice(this.order, this.start, this.text);
  final int order;
  final int start;
  final String text;
}

class _Page {
  const _Page(this.columns);
  final List<List<_Slice>> columns;
  int get firstOrder => columns.expand((e) => e).first.order;
  bool contains(int order) =>
      columns.expand((e) => e).any((s) => s.order == order);
}

Color _highlightColor(String? value) => switch (value ?? 'YELLOW') {
  'PEACH' || '#FFCCBC' => const Color(0x88FFCCBC),
  'PINK' => const Color(0x88F8BBD0),
  'GREEN' || '#A5D6A7' => const Color(0x88A5D6A7),
  'BLUE' || '#90CAF9' => const Color(0x8890CAF9),
  'PURPLE' || '#CE93D8' => const Color(0x88CE93D8),
  _ => const Color(0x88FFF59D),
};

enum _HighlightAction { delete, color, memo }

class _ReaderPage extends StatelessWidget {
  const _ReaderPage({
    required this.page,
    required this.settings,
    required this.twoColumns,
    required this.highlights,
    required this.onHighlight,
    required this.onHighlightTap,
    required this.memos,
    required this.roomMemoCounts,
    required this.onMemo,
    required this.onShowMemos,
  });
  final _Page page;
  final ReaderSettings settings;
  final bool twoColumns;
  final List<ReadingNote> highlights;
  final ValueChanged<_TextSelection> onHighlight;
  final ValueChanged<ReadingNote> onHighlightTap;
  final List<ReadingNote> memos;
  final Map<int, int> roomMemoCounts;
  final ValueChanged<_TextSelection> onMemo;
  final void Function(int paragraphOrder, BuildContext anchorContext) onShowMemos;

  @override
  Widget build(BuildContext context) {
    final color = switch (settings.theme) {
      ReaderPaperTheme.dark => const Color(0xfff5f0e7),
      ReaderPaperTheme.sepia => const Color(0xff493b2d),
      _ => const Color(0xff262626),
    };
    final style = TextStyle(
      fontFamily: 'NotoSerifKR',
      fontSize: 18 * settings.fontScale,
      height: [1.6, 1.85, 2.15][settings.lineHeightStep],
      color: color,
    );
    Widget textColumn(List<_Slice> list) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: list
          .map(
            (s) => _SelectableParagraphSlice(
              slice: s,
              style: style,
              highlights: highlights
                  .where((n) => n.paragraphOrder == s.order)
                  .toList(),
              onHighlight: onHighlight,
              onHighlightTap: onHighlightTap,
              memos: memos.where((n) => n.paragraphOrder == s.order).toList(),
              roomMemoCount: roomMemoCounts[s.order] ?? 0,
              onMemo: onMemo,
              onShowMemos: onShowMemos,
            ),
          )
          .toList(),
    );
    final content = twoColumns
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: textColumn(page.columns[0])),
              const SizedBox(width: 28),
              Expanded(
                child: page.columns.length > 1
                    ? textColumn(page.columns[1])
                    : const SizedBox(),
              ),
            ],
          )
        : textColumn(page.columns.first);
    // The page calculation normally fits this content exactly.  A vertically
    // bounded scroll view is a safety net for font fallback/accessibility line
    // metric differences; it preserves all paragraphs instead of clipping or
    // overflowing the RenderFlex.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        twoColumns ? 34 : 30,
        72,
        twoColumns ? 34 : 30,
        70,
      ),
      child: SingleChildScrollView(
        primary: false,
        physics: const ClampingScrollPhysics(),
        // 오른쪽 여백의 메모 표시가 잘리지 않게
        clipBehavior: Clip.none,
        child: content,
      ),
    );
  }
}

class _TextSelection {
  const _TextSelection(
    this.paragraphOrder,
    this.start,
    this.end,
    this.selectedText,
  );
  final int paragraphOrder;
  final int start;
  final int end;
  final String selectedText;
}

class _SelectableParagraphSlice extends StatefulWidget {
  const _SelectableParagraphSlice({
    required this.slice,
    required this.style,
    required this.highlights,
    required this.onHighlight,
    required this.onHighlightTap,
    required this.memos,
    required this.roomMemoCount,
    required this.onMemo,
    required this.onShowMemos,
  });
  final _Slice slice;
  final TextStyle style;
  final List<ReadingNote> highlights;
  final ValueChanged<_TextSelection> onHighlight;
  final ValueChanged<ReadingNote> onHighlightTap;
  final List<ReadingNote> memos;
  final int roomMemoCount;
  final ValueChanged<_TextSelection> onMemo;
  final void Function(int paragraphOrder, BuildContext anchorContext) onShowMemos;

  @override
  State<_SelectableParagraphSlice> createState() =>
      _SelectableParagraphSliceState();
}

class _SelectableParagraphSliceState extends State<_SelectableParagraphSlice> {
  final Map<int, TapGestureRecognizer> _highlightRecognizers = {};

  TapGestureRecognizer _recognizerFor(ReadingNote note) {
    final recognizer = _highlightRecognizers.putIfAbsent(
      note.id,
      TapGestureRecognizer.new,
    );
    recognizer.onTap = () => widget.onHighlightTap(note);
    return recognizer;
  }

  @override
  void dispose() {
    for (final recognizer in _highlightRecognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slice = widget.slice;
    final style = widget.style;
    final highlights = widget.highlights;
    final memos = widget.memos;
    final memoCount = memos.length + widget.roomMemoCount;
    final onHighlight = widget.onHighlight;
    final onMemo = widget.onMemo;
    final onShowMemos = widget.onShowMemos;
    final spans = <InlineSpan>[];
    final points = <int>{0, slice.text.length};
    for (final note in highlights) {
      final start = note.startOffset, end = note.endOffset;
      if (start == null || end == null) continue;
      final localStart = (start - slice.start).clamp(0, slice.text.length);
      final localEnd = (end - slice.start).clamp(0, slice.text.length);
      if (localEnd > localStart) {
        points
          ..add(localStart)
          ..add(localEnd);
      }
    }
    final cuts = points.toList()..sort();
    for (var i = 0; i < cuts.length - 1; i++) {
      final from = cuts[i], to = cuts[i + 1];
      // The server normalizes new writes so they do not overlap.  For legacy
      // overlapping rows, use the newest write too, rather than list order.
      final covered = highlights.where(
        (n) =>
            n.startOffset != null &&
            n.endOffset != null &&
            n.startOffset! <= slice.start + from &&
            n.endOffset! >= slice.start + to,
      );
      final highlight = covered.fold<ReadingNote?>(null, (latest, candidate) {
        if (latest == null) return candidate;
        // Local/private annotations retain their existing visual priority.
        // Shared notes use a negative id in this renderer; among them the
        // server-created timestamp, then server id, is the deterministic
        // top-layer rule. Client clocks and update timestamps are excluded.
        if (latest.id >= 0) return latest;
        if (candidate.id >= 0) return candidate;
        final latestTime = latest.createdAt;
        final candidateTime = candidate.createdAt;
        if (candidateTime == null) return latest;
        if (latestTime == null || candidateTime.isAfter(latestTime)) {
          return candidate;
        }
        if (candidateTime == latestTime && candidate.id < latest.id) {
          return candidate;
        }
        return latest;
      });
      spans.add(
        TextSpan(
          text: slice.text.substring(from, to),
          recognizer: highlight != null && highlight.id > 0
              ? _recognizerFor(highlight)
              : null,
          style: highlight == null
              ? style
              : style.copyWith(
                  backgroundColor: _highlightColor(highlight.highlightColor),
                ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SelectableText.rich(
            TextSpan(children: spans),
            contextMenuBuilder: (context, editableTextState) {
              final selection = editableTextState.textEditingValue.selection;
              final hasText = selection.isValid && !selection.isCollapsed;
              return AdaptiveTextSelectionToolbar.buttonItems(
                anchors: editableTextState.contextMenuAnchors,
                // 문장 선택 메뉴는 형광펜 · 메모 두 개만 (복사·공유·전체 선택·읽어 주기·Gemini 는 뺌)
                buttonItems: [
                  if (hasText)
                    ContextMenuButtonItem(
                      label: '형광펜',
                      onPressed: () {
                        final start = selection.start.clamp(
                          0,
                          slice.text.length,
                        );
                        final end = selection.end.clamp(0, slice.text.length);
                        editableTextState.hideToolbar();
                        if (end > start)
                          onHighlight(
                            _TextSelection(
                              slice.order,
                              slice.start + start,
                              slice.start + end,
                              slice.text.substring(start, end),
                            ),
                          );
                      },
                    ),
                  if (hasText)
                    ContextMenuButtonItem(
                      label: '메모',
                      onPressed: () {
                        final start = selection.start.clamp(
                          0,
                          slice.text.length,
                        );
                        final end = selection.end.clamp(0, slice.text.length);
                        editableTextState.hideToolbar();
                        if (end > start)
                          onMemo(
                            _TextSelection(
                              slice.order,
                              slice.start + start,
                              slice.start + end,
                              slice.text.substring(start, end),
                            ),
                          );
                      },
                    ),
                ],
              );
            },
          ),
          // 메모 표시는 글자를 가리지 않게 문단 오른쪽 바깥 여백에 둔다
          if (memoCount > 0 && slice.start == 0)
            Positioned(
              right: -29,
              top: -2,
              child: _MemoBadge(
                count: memoCount,
                onTap: (anchorContext) => onShowMemos(slice.order, anchorContext),
              ),
            ),
        ],
      ),
    );
  }
}

class _MemoBadge extends StatelessWidget {
  const _MemoBadge({required this.count, required this.onTap});
  final int count;
  final ValueChanged<BuildContext> onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .9),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: () => onTap(context),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(
              Icons.mode_comment_outlined,
              size: 17,
              color: Color(0xff8d6e63),
            ),
            if (count > 1)
              Positioned(
                right: -7,
                top: -7,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 1,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xff8d6e63),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _ParagraphMemos extends StatelessWidget {
  const _ParagraphMemos({required this.bookId, required this.paragraphOrder});
  final int bookId;
  final int paragraphOrder;
  @override
  Widget build(BuildContext context) {
    final notes = context
        .watch<BookViewModel>()
        .readingNotes
        .where(
          (n) =>
              n.type == ReaderNoteType.memo &&
              n.paragraphOrder == paragraphOrder,
        )
        .toList();
    return Container(
      height: MediaQuery.of(context).size.height * .56,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              '문단 $paragraphOrder의 메모',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: notes
                  .map(
                    (note) => ListTile(
                      title: Text(note.memoContent ?? '메모'),
                      subtitle: Text(
                        note.selectedText?.isNotEmpty == true
                            ? '“${note.selectedText}”'
                            : '현재 위치 메모',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(context, note),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(context, note),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, ReadingNote note) async {
    final vm = context.read<BookViewModel>();
    await showDialog<bool>(
      context: context,
      builder: (_) => _MemoEditorDialog(
        selectedText: note.selectedText,
        initialMemo: note.memoContent ?? '',
        onSave: (memo) => vm.updateNote(bookId, note.id, memo: memo),
      ),
    );
  }

  Future<void> _delete(BuildContext context, ReadingNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('메모 삭제'),
        content: const Text('이 메모를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted)
      await context.read<BookViewModel>().deleteNote(bookId, note.id);
  }
}

/// 창이 뜨는 자리: 가운데(목차·독서노트) / 오른쪽 아래(보기·뷰어 설정)
enum _SheetPlace { center, corner }

class _SheetMode extends InheritedWidget {
  const _SheetMode({required this.place, required super.child});
  final _SheetPlace place;
  static _SheetPlace of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SheetMode>()?.place ??
      _SheetPlace.center;
  @override
  bool updateShouldNotify(_SheetMode old) => old.place != place;
}

/// 창 틀 — 머리(가운데 제목 + 오른쪽 "닫기") + 내용.
/// 가운데 창은 높이 고정(목록·탭이 들어감), 오른쪽 아래 창은 내용만큼(최대 화면 60%).
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final place = _SheetMode.of(context);
    final screenH = MediaQuery.of(context).size.height;
    final head = SizedBox(
      height: 56,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          Positioned(
            right: 8,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                '닫기',
                style: TextStyle(color: Color(0xFF8A8A8A)),
              ),
            ),
          ),
        ],
      ),
    );
    final box = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    );
    if (place == _SheetPlace.center) {
      return Container(
        height: (screenH * .72).clamp(320.0, 680.0),
        clipBehavior: Clip.antiAlias,
        decoration: box,
        child: Column(
          children: [
            head,
            const Divider(height: 1),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Container(
      constraints: BoxConstraints(maxHeight: screenH * .78),
      clipBehavior: Clip.antiAlias,
      decoration: box,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          head,
          const Divider(height: 1),
          Flexible(child: child),
        ],
      ),
    );
  }
}

class _Notes extends StatefulWidget {
  const _Notes({
    required this.bookId,
    required this.order,
    required this.onGo,
    required this.aiFriends,
    required this.aiNotesByFriend,
    this.roomId,
  });

  final int? roomId;
  final int bookId;
  final int order;
  final ValueChanged<int> onGo;

  final List<AiReadingFriend> aiFriends;
  final Map<int, List<AiReadingNote>> aiNotesByFriend;

  @override
  State<_Notes> createState() => _NotesState();
}

class _NotesState extends State<_Notes> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final Set<int> _deletingIds = <int>{};

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (mounted && !_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BookViewModel>();
    final filters = <ReaderNoteType?>[
      null,
      ReaderNoteType.highlight,
      ReaderNoteType.memo,
      ReaderNoteType.bookmark,
    ];
    // 화면 가운데 창 (목차와 같은 틀): 머리 = 가운데 "독서노트" · 왼쪽 모두 삭제 · 오른쪽 닫기
    return Container(
      height: (MediaQuery.of(context).size.height * .72).clamp(320.0, 680.0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Text(
                  '독서노트',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Positioned(
                  right: 8,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      '닫기',
                      style: TextStyle(color: Color(0xFF8A8A8A)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: '전체'),
              Tab(text: '형광펜'),
              Tab(text: '메모'),
              Tab(text: '책갈피'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: List.generate(4, (index) {
                // 메모 탭: 사람별 거르기 + 메모 카드 (사용자 첨부 이미지, 수정2-1쪽 "메모 선택시")
                if (index == 2) {
                  return _MemoTab(
                    roomId: widget.roomId,
                    myMemos: vm.readingNotes
                        .where((n) => n.type == ReaderNoteType.memo)
                        .toList(),
                    chapters: vm.readerChapters,
                    myNickname: context.read<RidiStore>().nickname,

                    aiFriends: widget.aiFriends,
                    aiNotesByFriend: widget.aiNotesByFriend,

                    onGo: (order) {
                      Navigator.of(context).pop();
                      widget.onGo(order);
                    },
                    onEdit: _edit,
                    onDelete: _delete,
                  );
                }
                final notes =
                    (filters[index] == null
                          ? vm.readingNotes
                          : vm.readingNotes
                                .where((note) => note.type == filters[index])
                                .toList())
                      ..sort(
                        (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
                          a.createdAt ?? DateTime(0),
                        ),
                      );
                if (notes.isEmpty)
                  return Center(
                    child: Text(
                      index == 2
                          ? '저장한 메모가 없습니다.'
                          : index == 3
                          ? '저장한 책갈피가 없습니다.'
                          : '저장한 독서노트가 없습니다.',
                    ),
                  );
                // 목차와 같은 모양: 줄마다 위 = 문장, 아래 = 메모 · "문단 N · 날짜", 오른쪽 작은 수정/삭제
                return ListView.separated(
                  itemCount: notes.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0xFFEDEDED)),
                  itemBuilder: (_, i) {
                    final note = notes[i];
                    final busy = _deletingIds.contains(note.id);
                    final d = note.createdAt?.toLocal();
                    final date = d == null
                        ? ''
                        : ' · ${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
                    final kind = switch (note.type) {
                      ReaderNoteType.memo => '메모',
                      ReaderNoteType.bookmark => '책갈피',
                      ReaderNoteType.highlight => '형광펜',
                    };
                    final head = note.selectedText?.isNotEmpty == true
                        ? (note.type == ReaderNoteType.memo
                              ? '“${note.selectedText}”'
                              : note.selectedText!)
                        : (note.type == ReaderNoteType.memo
                              ? '현재 위치 메모'
                              : note.preview);
                    return InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onGo(note.paragraphOrder);
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 14, 12, 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    head,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (note.type == ReaderNoteType.memo &&
                                      (note.memoContent?.isNotEmpty ??
                                          false)) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      note.memoContent!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    '$kind · 문단 ${note.paragraphOrder}$date',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF8A8A8A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (note.type == ReaderNoteType.memo)
                              IconButton(
                                tooltip: '수정',
                                onPressed: busy ? null : () => _edit(note),
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  size: 20,
                                  color: Color(0xFF8A8A8A),
                                ),
                              ),
                            IconButton(
                              tooltip: '삭제',
                              onPressed: busy ? null : () => _delete(note),
                              icon: busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                      color: Color(0xFF8A8A8A),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
          // 아래 버튼 줄(현재 위치 메모 · 문단 형광펜 · 모두 삭제)은 뺌 (수정 확인 피드백)
        ],
      ),
    );
  }

  Future<void> _delete(ReadingNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('독서노트 삭제'),
        content: Text(
          note.type == ReaderNoteType.memo ? '이 메모를 삭제할까요?' : '이 독서노트를 삭제할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _deletingIds.contains(note.id)) return;
    setState(() => _deletingIds.add(note.id));
    try {
      await context.read<BookViewModel>().deleteNote(widget.bookId, note.id);
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _deletingIds.remove(note.id));
    }
  }

  Future<void> _edit(ReadingNote note) async {
    final viewModel = context.read<BookViewModel>();
    await showDialog<bool>(
      context: context,
      builder: (_) => _MemoEditorDialog(
        selectedText: note.selectedText,
        initialMemo: note.memoContent ?? '',
        onSave: (memo) =>
            viewModel.updateNote(widget.bookId, note.id, memo: memo),
      ),
    );
  }
}

class _MemoEditorDialog extends StatefulWidget {
  const _MemoEditorDialog({
    required this.onSave,
    this.selectedText,
    this.initialMemo = '',
  });
  final Future<void> Function(String memo) onSave;
  final String? selectedText;
  final String initialMemo;

  @override
  State<_MemoEditorDialog> createState() => _MemoEditorDialogState();
}

class _MemoEditorDialogState extends State<_MemoEditorDialog> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialMemo);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final memo = _controller.text.trim();
    if (memo.isEmpty) {
      setState(() => _error = '메모 내용을 입력해 주세요.');
      return;
    }
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(memo);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = error.message;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = '메모를 저장하지 못했습니다. 다시 시도해 주세요.';
        });
    }
  }

  /// 리디 메모 창처럼: 머리 = 닫기 · 메모(글자 수/1500) · 저장, 고른 문장, 넓은 입력 칸, 아래 날짜
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final count = _controller.text.characters.length;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 56,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '메모',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: '  ($count/1500)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9E9E9E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 8,
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text(
                        '닫기',
                        style: TextStyle(color: Color(0xFF8A8A8A)),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    child: _saving
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : TextButton(
                            onPressed: _save,
                            child: const Text(
                              '저장',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (widget.selectedText?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 5, right: 10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF2C94C),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.selectedText!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Container(
                height: 300,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _controller,
                  expands: true,
                  maxLines: null,
                  maxLength: 1500,
                  autofocus: true,
                  enabled: !_saving,
                  textAlignVertical: TextAlignVertical.top,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: const InputDecoration(
                    hintText: '메모를 남겨주세요.',
                    border: InputBorder.none,
                    counterText: '',
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFE53935),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Text(
                '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 보기 설정 (사용자 첨부 이미지 = 리디 보기 설정에서 고른 것만):
/// 바탕색 동그라미 · 글자 크기 [−][+] · 행간 [−][+] · AI 친구 설정 › · 스포일러 켜기/끄기.
/// (밝기·글꼴·문단 간격·문단 너비·문단 정렬·형광펜 색상은 뺌)
/// ※ AI 친구 설정·스포일러는 아직 동작을 정하지 않아 모양만 있다 (수정2 질문 4).
class _ViewSettings extends StatefulWidget {
  const _ViewSettings({
    required this.onChange,
    required this.aiFriends,
    required this.selectedAiFriendIds,
    required this.onAiFriendDone,
  });

  final ValueChanged<ReaderSettings> onChange;

  // 서버에서 받아온 AI 친구 목록
  final List<AiReadingFriend> aiFriends;

  // 현재 실제로 적용되어 있는 AI 친구들
  final Set<int> selectedAiFriendIds;

  // AI 친구 화면에서 "완료"를 눌렀을 때 호출
  final Future<void> Function(Set<int> selectedIds) onAiFriendDone;

  @override
  State<_ViewSettings> createState() => _ViewSettingsState();
}

class _ViewSettingsState extends State<_ViewSettings> {
  static const _themes = [
    (ReaderPaperTheme.light, Color(0xFFFFFFFF), '기본'),
    (ReaderPaperTheme.sepia, Color(0xFFF4ECD8), '세피아'),
    (ReaderPaperTheme.dark, Color(0xFF2B2B2B), '어둡게'),
  ];

  static const _lineLabels = ['좁게', '보통', '넓게'];

  static final _spoiler = ValueNotifier<bool>(false);

  bool _showAiFriends = false;
  bool _savingAiFriends = false;

  late Set<int> _draftSelectedIds;

  @override
  void initState() {
    super.initState();

    // 아직 완료를 누르지 않은 임시 선택 상태
    _draftSelectedIds = <int>{
      ...widget.selectedAiFriendIds,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_showAiFriends) {
      return _buildAiFriendSettings(context);
    }

    return _buildViewSettings(context);
  }

  Widget _buildViewSettings(BuildContext context) {
    final s = context.watch<BookViewModel>().readerSettings;

    final fontLevel =
        ((s.fontScale - .8) / .1).round() + 1;

    const divider = Divider(
      height: 1,
      indent: 20,
      endIndent: 20,
      color: Color(0xFFEDEDED),
    );

    return _Sheet(
      title: '보기 설정',
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
              const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  const Icon(
                    Icons.format_color_fill,
                    size: 20,
                    color: Color(0xFFB0B0B0),
                  ),
                  const SizedBox(width: 14),

                  for (final t in _themes) ...[
                    Tooltip(
                      message: t.$3,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: s.theme == t.$1
                            ? null
                            : () => widget.onChange(
                          s.copyWith(theme: t.$1),
                        ),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: t.$2,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: s.theme == t.$1
                                  ? const Color(0xFF1E88E5)
                                  : const Color(0xFFD0D0D0),
                              width:
                              s.theme == t.$1 ? 2.5 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ],
              ),
            ),

            divider,

            Semantics(
              label: '형광펜 보기',
              toggled: s.showHighlights,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.highlight_outlined,
                      size: 20,
                      color: Color(0xFF9E9E9E),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('형광펜 보기', style: TextStyle(fontSize: 15)),
                    ),
                    Switch(
                      value: s.showHighlights,
                      onChanged: (value) =>
                          widget.onChange(s.copyWith(showHighlights: value)),
                    ),
                  ],
                ),
              ),
            ),

            divider,

            _StepRow(
              icon: Icons.format_size,
              label: '글자 크기',
              value: '$fontLevel',
              onMinus: s.fontScale <= .8 + 1e-6
                  ? null
                  : () => widget.onChange(
                s.copyWith(
                  fontScale:
                  ((s.fontScale - .1) * 10)
                      .round() /
                      10,
                ),
              ),
              onPlus: s.fontScale >= 1.4 - 1e-6
                  ? null
                  : () => widget.onChange(
                s.copyWith(
                  fontScale:
                  ((s.fontScale + .1) * 10)
                      .round() /
                      10,
                ),
              ),
            ),

            divider,

            _StepRow(
              icon: Icons.format_line_spacing,
              label: '행간',
              value: _lineLabels[
              s.lineHeightStep.clamp(0, 2)],
              onMinus: s.lineHeightStep <= 0
                  ? null
                  : () => widget.onChange(
                s.copyWith(
                  lineHeightStep:
                  s.lineHeightStep - 1,
                ),
              ),
              onPlus: s.lineHeightStep >= 2
                  ? null
                  : () => widget.onChange(
                s.copyWith(
                  lineHeightStep:
                  s.lineHeightStep + 1,
                ),
              ),
            ),

            divider,

            // AI 친구 설정
            InkWell(
              onTap: () {
                setState(() {
                  _draftSelectedIds = <int>{
                    ...widget.selectedAiFriendIds,
                  };

                  _showAiFriends = true;
                });
              },
              child: const Padding(
                padding:
                EdgeInsets.fromLTRB(20, 14, 16, 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 20,
                      color: Color(0xFF9E9E9E),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'AI 친구 설정',
                      style: TextStyle(fontSize: 15),
                    ),
                    Spacer(),
                    Icon(
                      Icons.chevron_right,
                      color: Color(0xFFB0B0B0),
                    ),
                  ],
                ),
              ),
            ),

            divider,

            ValueListenableBuilder<bool>(
              valueListenable: _spoiler,
              builder: (_, on, _) => Padding(
                padding:
                const EdgeInsets.fromLTRB(20, 6, 12, 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.visibility_off_outlined,
                      size: 20,
                      color: Color(0xFF9E9E9E),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '스포일러',
                      style: TextStyle(fontSize: 15),
                    ),
                    const Spacer(),
                    Switch(
                      value: on,
                      onChanged: (v) =>
                      _spoiler.value = v,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiFriendSettings(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 상단
          SizedBox(
            height: 56,
            child: Row(
              children: [
                // 뒤로가기
                SizedBox(
                  width: 64,
                  child: IconButton(
                    tooltip: '뒤로',
                    onPressed: _savingAiFriends
                        ? null
                        : () {
                      setState(() {
                        _showAiFriends = false;
                      });
                    },
                    icon: const Icon(
                      Icons.chevron_left,
                      size: 28,
                      color: Color(0xFF555555),
                    ),
                  ),
                ),

                // 가운데 제목
                const Expanded(
                  child: Center(
                    child: Text(
                      'AI 친구 설정',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // 완료
                SizedBox(
                  width: 64,
                  child: TextButton(
                    onPressed:
                    _savingAiFriends ? null : _completeAiFriends,
                    child: _savingAiFriends
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                        : const Text(
                      '완료',
                      style: TextStyle(
                        color: Color(0xFF1E88E5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          if (widget.aiFriends.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(
                vertical: 32,
                horizontal: 20,
              ),
              child: Center(
                child: Text(
                  '사용할 수 있는 AI 친구가 없습니다.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF8A8A8A),
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: widget.aiFriends.length,
                separatorBuilder: (_, _) =>
                const Divider(
                  height: 1,
                  indent: 20,
                  endIndent: 20,
                  color: Color(0xFFEDEDED),
                ),
                itemBuilder: (_, index) {
                  final friend =
                  widget.aiFriends[index];

                  final selected =
                  _draftSelectedIds
                      .contains(friend.id);

                  return InkWell(
                    onTap: _savingAiFriends
                        ? null
                        : () {
                      setState(() {
                        if (selected) {
                          _draftSelectedIds
                              .remove(friend.id);
                        } else {
                          _draftSelectedIds
                              .add(friend.id);
                        }
                      });
                    },
                    child: Padding(
                      padding:
                      const EdgeInsets.fromLTRB(
                        20,
                        14,
                        18,
                        14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration:
                            const BoxDecoration(
                              color: Color(0xFFF2F3F7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.smart_toy_outlined,
                              size: 20,
                              color: Color(0xFF666666),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              friend.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight:
                                FontWeight.w500,
                              ),
                            ),
                          ),

                          // 선택된 친구만 체크 표시.
                          // > 화살표는 없음.
                          if (selected)
                            const Icon(
                              Icons.check,
                              size: 23,
                              color:
                              Color(0xFF1E88E5),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _completeAiFriends() async {
    setState(() {
      _savingAiFriends = true;
    });

    try {
      // 여기서만 부모에게 최종 선택을 전달한다.
      // 친구를 누르는 것만으로는 Gemini가 실행되지 않는다.
      await widget.onAiFriendDone(
        Set<int>.from(_draftSelectedIds),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingAiFriends = false;
        });
      }
    }
  }
}
/// 보기 설정 한 줄: 아이콘 · 이름 · 값 · [−] [+]
class _StepRow extends StatelessWidget {
const _StepRow({
required this.icon,
required this.label,
required this.value,
this.onMinus,
this.onPlus,
});
final IconData icon;
final String label;
final String value;
final VoidCallback? onMinus;
final VoidCallback? onPlus;

Widget _btn(IconData i, VoidCallback? f) => InkWell(
onTap: f,
borderRadius: BorderRadius.circular(20),
    child: Container(
      width: 46,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: f == null ? const Color(0xFFDDDDDD) : const Color(0xFF1E88E5),
        ),
      ),
      child: Icon(
        i,
        size: 18,
        color: f == null ? const Color(0xFFBBBBBB) : const Color(0xFF1E88E5),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
    child: Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF9E9E9E)),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 10),
        Text(
          value,
          style: const TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
        ),
        const Spacer(),
        _btn(Icons.remove, onMinus),
        const SizedBox(width: 6),
        _btn(Icons.add, onPlus),
      ],
    ),
  );
}

/// 뷰어 설정 — 두 항목만 (사용자 첨부 이미지): 2단으로 보기 · 읽는 동안 화면 켜 두기.
/// 창은 오른쪽 아래(메뉴 바로 위)에 뜬다.
class _ViewerSettings extends StatelessWidget {
  const _ViewerSettings({required this.onChange});
  final ValueChanged<ReaderSettings> onChange;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BookViewModel>().readerSettings;
    final wide = MediaQuery.of(context).size.width >= 700;
    return _Sheet(
      title: '뷰어 설정',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ToggleRow(
              title: '2단으로 보기',
              sub: wide ? '넓은 화면에서 두 컬럼으로 표시합니다.' : '넓은 화면에서 사용할 수 있습니다.',
              value: s.twoColumn,
              onChanged: (v) => onChange(s.copyWith(twoColumn: v)),
            ),
            _Line(),
            _ToggleRow(
              title: '읽는 동안 화면 켜 두기',
              value: s.keepScreenOn,
              onChanged: (v) => onChange(s.copyWith(keepScreenOn: v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 20, color: Color(0xFFEDEDED));
}

/// 뷰어 설정 — 켜기/끄기 줄 (제목 · 아래 작은 회색 설명)
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    this.sub,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15)),
              if (sub != null) ...[
                const SizedBox(height: 2),
                Text(
                  sub!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9E9E9E),
                  ),
                ),
              ],
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    ),
  );
}

// ---------------- 독서노트 › 메모 탭 ----------------
/// 메모 탭 (첨부 이미지): 위 = 사람별 거르기 칩(전체 · 나 · 멤버…), 장 제목, 메모 카드
/// (머리글자 · 이름 · 나 · 언제 · 형광펜 색 점 / 고른 문장 / 메모 / 댓글 N · 이 문장으로 ›).
/// 방에서 읽으면 방에 공유된 메모 전부(서버), 혼자 읽으면 내 메모만.
class _MemoTab extends StatefulWidget {
  const _MemoTab({
    required this.roomId,
    required this.myMemos,
    required this.chapters,
    required this.myNickname,
    required this.aiFriends,
    required this.aiNotesByFriend,
    required this.onGo,
    required this.onEdit,
    required this.onDelete,
  });

  final int? roomId;
  final List<ReadingNote> myMemos;
  final List<ReaderChapter> chapters;
  final String myNickname;

  final List<AiReadingFriend> aiFriends;
  final Map<int, List<AiReadingNote>> aiNotesByFriend;

  final ValueChanged<int> onGo;
  final Future<void> Function(ReadingNote) onEdit;
  final Future<void> Function(ReadingNote) onDelete;

  @override
  State<_MemoTab> createState() => _MemoTabState();
}

class _MemoItem {
  _MemoItem({
    required this.author,
    required this.mine,
    required this.order,
    this.quote,
    this.memo,
    this.color,
    this.at,
    this.comments,
    this.shared,
    this.own,
    this.locked = false,
  });
  final String author;
  final bool mine;
  final int order;
  final String? quote, memo, color;
  final DateTime? at;
  final int? comments;
  final SharedRoomNote? shared;
  final ReadingNote? own;
  final bool locked;
}

class _MemoTabState extends State<_MemoTab> {
  Future<List<SharedRoomNote>>? _room;
  String _who = '전체';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final roomId = widget.roomId;
    if (roomId == null) return;
    final token = context.read<RidiStore>().accessToken;
    _room = ReadingRoomRepository(ApiClient(tokenProvider: () => token))
        .sharedNotes(roomId);
  }

  List<_MemoItem> _items(List<SharedRoomNote>? shared) {
    final items = <_MemoItem>[];

    // 혼자 읽는 경우: 내 메모
    if (shared == null) {
      for (final n in widget.myMemos) {
        items.add(
          _MemoItem(
            author: widget.myNickname,
            mine: true,
            order: n.paragraphOrder,
            quote: n.selectedText,
            memo: n.memoContent,
            color: n.highlightColor,
            at: n.createdAt,
            own: n,
          ),
        );
      }
    } else {
      // 교환독서 방: 공유된 사람 메모
      for (final n in shared.where((n) => n.type == 'MEMO')) {
        items.add(
          _MemoItem(
            author: n.nickname,
            mine: n.nickname == widget.myNickname,
            order: n.paragraphOrder,
            quote: n.selectedText,
            memo: n.content,
            color: n.highlightColor,
            at: n.createdAt,
            comments: n.commentCount,
            shared: n,
            locked: n.isSpoilerLocked,
          ),
        );
      }
    }

    // 선택된 AI 친구들의 메모
    for (final friend in widget.aiFriends) {
      final notes = widget.aiNotesByFriend[friend.id];

      if (notes == null || notes.isEmpty) {
        continue;
      }

      for (final note in notes) {
        items.add(
          _MemoItem(
            author: friend.name,
            mine: false,
            order: note.paragraphOrder,
            quote: note.selectedText,
            memo: note.content,
            color: '#8FA8FF',
          ),
        );
      }
    }

    return items;
  }

  String _chapterOf(int order) {
    final i = widget.chapters.lastIndexWhere(
      (c) => c.startParagraphOrder <= order,
    );
    if (i < 0) return '';
    final c = widget.chapters[i];
    return c.title.trim().isEmpty ? '${c.number}장' : c.title;
  }

  static String _ago(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return '방금';
    if (d.inHours < 1) return '${d.inMinutes}분 전';
    if (d.inDays < 1) return '${d.inHours}시간 전';
    return '${d.inDays}일 전';
  }

  static Color _dot(String? hex) {
    final v = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
    return v == null ? const Color(0xFFF2C94C) : Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    if (_room == null) return _body(_items(null));
    return FutureBuilder<List<SharedRoomNote>>(
      future: _room,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(_load),
              child: const Text('방 메모를 불러오지 못했습니다. 다시 시도'),
            ),
          );
        }
        return _body(_items(snap.data));
      },
    );
  }

  Widget _body(List<_MemoItem> all) {
    final others = <String>{
      for (final m in all)
        if (!m.mine) m.author,
    }.toList()..sort();
    final chips = ['전체', '나', ...others];
    final shown =
        all
            .where(
              (m) => _who == '전체' || (_who == '나' ? m.mine : m.author == _who),
            )
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    final rows = <Widget>[];
    String? lastChapter;
    for (final m in shown) {
      final ch = _chapterOf(m.order);
      if (ch != lastChapter && ch.isNotEmpty) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
            child: Text(
              ch,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
            ),
          ),
        );
        lastChapter = ch;
      }
      rows.add(_card(m));
      rows.add(
        const Divider(
          height: 1,
          indent: 20,
          endIndent: 20,
          color: Color(0xFFEDEDED),
        ),
      );
    }
    final empty = _who == '전체' ? '저장한 메모가 없습니다.' : '$_who 님의 메모가 없습니다.';
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: [
              for (final c in chips) ...[
                ChoiceChip(
                  label: Text(c),
                  selected: _who == c,
                  showCheckmark: false,
                  selectedColor: const Color(0xFF111111),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: _who == c ? Colors.white : const Color(0xFF333333),
                  ),
                  shape: const StadiumBorder(
                    side: BorderSide(color: Color(0xFFDDDDDD)),
                  ),
                  onSelected: (_) => setState(() => _who = c),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text(empty))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: rows,
                ),
        ),
      ],
    );
  }

  Widget _card(_MemoItem m) {
    const gray = Color(0xFF9E9E9E);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: const Color(0xFFEFF1F5),
                child: Text(
                  m.author.isEmpty ? '?' : m.author.characters.first,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF555555),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                m.author,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (m.mine) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '나',
                    style: TextStyle(fontSize: 11, color: gray),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                _ago(m.at),
                style: const TextStyle(fontSize: 12, color: gray),
              ),
              const Spacer(),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: _dot(m.color),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (m.locked)
            const Padding(
              padding: EdgeInsets.only(left: 36),
              child: Text(
                '아직 안 읽은 부분이라 가려 뒀어요',
                style: TextStyle(fontSize: 13, color: gray),
              ),
            )
          else ...[
            if (m.quote?.isNotEmpty == true)
              Container(
                margin: const EdgeInsets.only(left: 36, bottom: 6),
                padding: const EdgeInsets.only(left: 10),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Color(0xFFDDDDDD), width: 2),
                  ),
                ),
                child: Text(
                  '“${m.quote}”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B6B6B),
                  ),
                ),
              ),
            if (m.memo?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: Text(m.memo!, style: const TextStyle(fontSize: 14)),
              ),
          ],
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Row(
              children: [
                if (m.shared != null)
                  TextButton.icon(
                    onPressed: m.locked ? null : () => _openComments(m.shared!),
                    icon: const Icon(
                      Icons.chat_bubble_outline,
                      size: 16,
                      color: gray,
                    ),
                    label: Text(
                      (m.comments ?? 0) > 0 ? '댓글 ${m.comments}' : '댓글 쓰기',
                      style: const TextStyle(fontSize: 12, color: gray),
                    ),
                  ),
                if (m.own != null) ...[
                  IconButton(
                    tooltip: '수정',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => widget.onEdit(m.own!),
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: gray,
                    ),
                  ),
                  IconButton(
                    tooltip: '삭제',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => widget.onDelete(m.own!),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: gray,
                    ),
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: () => widget.onGo(m.order),
                  child: const Text(
                    '이 문장으로 ›',
                    style: TextStyle(fontSize: 12, color: gray),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openComments(SharedRoomNote note) async {
    final token = context.read<RidiStore>().accessToken;
    await showSharedNoteComments(
      context,
      ReadingRoomRepository(ApiClient(tokenProvider: () => token)),
      widget.roomId!,
      note,
    );
    if (mounted) setState(_load);
  }
}
