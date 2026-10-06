import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/api_client.dart';
import '../../model/book.dart';
import '../../model/shared_room_note.dart';
import '../../viewmodel/book_viewmodel.dart';
import '../../repository/reading_room_repository.dart';
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
      ).sharedNotes(roomId);
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
                            highlights: [
                              ...vm.readingNotes.where(
                                (n) => n.type == ReaderNoteType.highlight,
                              ),
                              ..._sharedHighlights,
                            ],
                            onHighlight: _saveHighlight,
                            memos: vm.readingNotes
                                .where((n) => n.type == ReaderNoteType.memo)
                                .toList(),
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
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 11)),
      );
  Future<void> _open(Widget sheet) async {
    setState(() => _sheetOpen = true);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
    if (mounted) setState(() => _sheetOpen = false);
  }

  void _chaptersFixed() => _open(
    _Sheet(
      title: '목차',
      child: ListView(
        children: context
            .read<BookViewModel>()
            .readerChapters
            .map(
              (c) => ListTile(
                title: Text(c.title),
                subtitle: Text('문단 ${c.startParagraphOrder}'),
                onTap: () {
                  Navigator.pop(context);
                  _go(c.startParagraphOrder);
                },
              ),
            )
            .toList(),
      ),
    ),
  );
  /*
  void _chapters()=>_open(_Sheet(title:'목차',child:ListView(children:context.read<BookViewModel>().readerChapters.map((c)=>ListTile(title:Text(c.title),subtitle:Text('문단 ${c.startParagraphOrder}'),onTap:(){Navigator.pop(context);_go(c.startParagraphOrder);}).toList()))));
  */
  void _chapters() => _chaptersFixed();
  void _notes() =>
      _open(_Notes(bookId: widget.bookId, order: _order, onGo: _go));
  void _viewSettings() => _open(
    _ViewSettings(
      onChange: (s) async {
        try {
          await context.read<BookViewModel>().saveSettings(s);
          _layoutKey = null;
        } on ApiException catch (e) {
          if (mounted)
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(e.message)));
        }
      },
    ),
  );
  void _viewerSettings() => _open(
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
        await _createRoomNote(selection, type: 'HIGHLIGHT', highlightColor: highlightColor);
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

  void _showParagraphMemos(int paragraphOrder) => _open(
    _ParagraphMemos(bookId: widget.bookId, paragraphOrder: paragraphOrder),
  );
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

class _ReaderPage extends StatelessWidget {
  const _ReaderPage({
    required this.page,
    required this.settings,
    required this.twoColumns,
    required this.highlights,
    required this.onHighlight,
    required this.memos,
    required this.onMemo,
    required this.onShowMemos,
  });
  final _Page page;
  final ReaderSettings settings;
  final bool twoColumns;
  final List<ReadingNote> highlights;
  final ValueChanged<_TextSelection> onHighlight;
  final List<ReadingNote> memos;
  final ValueChanged<_TextSelection> onMemo;
  final ValueChanged<int> onShowMemos;

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
              memos: memos.where((n) => n.paragraphOrder == s.order).toList(),
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

class _SelectableParagraphSlice extends StatelessWidget {
  const _SelectableParagraphSlice({
    required this.slice,
    required this.style,
    required this.highlights,
    required this.onHighlight,
    required this.memos,
    required this.onMemo,
    required this.onShowMemos,
  });
  final _Slice slice;
  final TextStyle style;
  final List<ReadingNote> highlights;
  final ValueChanged<_TextSelection> onHighlight;
  final List<ReadingNote> memos;
  final ValueChanged<_TextSelection> onMemo;
  final ValueChanged<int> onShowMemos;

  @override
  Widget build(BuildContext context) {
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
                buttonItems: [
                  ...editableTextState.contextMenuButtonItems,
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
          if (memos.isNotEmpty && slice.start == 0)
            Positioned(
              right: -4,
              top: -8,
              child: _MemoBadge(
                count: memos.length,
                onTap: () => onShowMemos(slice.order),
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
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .9),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
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

class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    height: MediaQuery.of(context).size.height * .58,
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: child),
      ],
    ),
  );
}

class _Notes extends StatefulWidget {
  const _Notes({required this.bookId, required this.order, required this.onGo});
  final int bookId;
  final int order;
  final ValueChanged<int> onGo;

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
    return Container(
      height: MediaQuery.of(context).size.height * .72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '독서노트',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: '모두 삭제',
                  onPressed: _currentNotes(vm).isEmpty ? null : _deleteAll,
                  icon: const Icon(Icons.delete_sweep_outlined),
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
                return ListView(
                  children: notes
                      .map(
                        (note) => ListTile(
                          title: Text(
                            note.type == ReaderNoteType.memo
                                ? (note.selectedText?.isNotEmpty == true
                                      ? '“${note.selectedText}”'
                                      : '현재 위치 메모')
                                : (note.selectedText?.isNotEmpty == true
                                      ? note.selectedText!
                                      : note.preview),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            note.type == ReaderNoteType.memo
                                ? '${note.memoContent ?? ''}\n문단 ${note.paragraphOrder} · ${note.createdAt ?? ''}'
                                : '문단 ${note.paragraphOrder} · ${note.type.api}',
                          ),
                          isThreeLine: note.type == ReaderNoteType.memo,
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onGo(note.paragraphOrder);
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (note.type == ReaderNoteType.memo)
                                IconButton(
                                  onPressed: _deletingIds.contains(note.id)
                                      ? null
                                      : () => _edit(note),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              IconButton(
                                onPressed: _deletingIds.contains(note.id)
                                    ? null
                                    : () => _delete(note),
                                icon: _deletingIds.contains(note.id)
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _memo,
                    child: const Text('현재 위치 메모'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _selectHighlight,
                    child: const Text('문단 형광펜'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _memo() async {
    // Read the notifier while this bottom-sheet context is alive. The dialog
    // receives only this callback and never looks up Provider with its own
    // route context.
    final viewModel = context.read<BookViewModel>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MemoEditorDialog(
        onSave: (memo) => viewModel.addNote(
          widget.bookId,
          ReaderNoteType.memo,
          widget.order,
          memo: memo,
        ),
      ),
    );
    if (!mounted || saved != true) return;
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

  List<ReadingNote> _currentNotes(BookViewModel vm) {
    const filters = <ReaderNoteType?>[
      null,
      ReaderNoteType.highlight,
      ReaderNoteType.memo,
      ReaderNoteType.bookmark,
    ];
    final type = filters[_tabs.index];
    return type == null
        ? vm.readingNotes
        : vm.readingNotes.where((n) => n.type == type).toList();
  }

  Future<void> _deleteAll() async {
    final vm = context.read<BookViewModel>();
    final notes = _currentNotes(vm);
    if (notes.isEmpty) return;
    const types = <ReaderNoteType?>[
      null,
      ReaderNoteType.highlight,
      ReaderNoteType.memo,
      ReaderNoteType.bookmark,
    ];
    final type = types[_tabs.index];
    final label = switch (type) {
      ReaderNoteType.highlight => '모든 형광펜',
      ReaderNoteType.memo => '모든 메모',
      ReaderNoteType.bookmark => '모든 책갈피',
      null => '이 책의 모든 독서노트',
    };
    var deleting = false;
    String? error;
    final deletedCount = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('독서노트 삭제'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$label를 삭제할까요?'),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: deleting ? null : () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: deleting
                  ? null
                  : () async {
                      setDialogState(() {
                        deleting = true;
                        error = null;
                      });
                      try {
                        final count = await vm.deleteNotes(
                          widget.bookId,
                          type: type,
                        );
                        if (dialogContext.mounted)
                          Navigator.of(dialogContext).pop(count);
                      } on ApiException catch (e) {
                        if (dialogContext.mounted)
                          setDialogState(() {
                            deleting = false;
                            error = e.message;
                          });
                      } catch (_) {
                        if (dialogContext.mounted)
                          setDialogState(() {
                            deleting = false;
                            error = '삭제하지 못했습니다. 다시 시도해주세요.';
                          });
                      }
                    },
              child: deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('모두 삭제'),
            ),
          ],
        ),
      ),
    );
    if (mounted && deletedCount != null)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('독서노트 ${deletedCount}개를 삭제했습니다.')));
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

  void _selectHighlight() {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('본문에서 길게 눌러 형광펜을 칠 문장 또는 구절을 선택해주세요.')),
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('메모 추가'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.selectedText?.isNotEmpty == true)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xfffff3c4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '“${widget.selectedText}”',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        TextField(
          controller: _controller,
          maxLines: 4,
          minLines: 3,
          autofocus: true,
          enabled: !_saving,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(errorText: _error, hintText: '메모를 입력하세요'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('저장'),
      ),
    ],
  );
}

class _ViewSettings extends StatelessWidget {
  const _ViewSettings({required this.onChange});
  final ValueChanged<ReaderSettings> onChange;
  static const _colors = [
    ('#FFF59D', Color(0xffFFF59D), '노랑'),
    ('#A5D6A7', Color(0xffA5D6A7), '초록'),
    ('#90CAF9', Color(0xff90CAF9), '파랑'),
    ('#FFCCBC', Color(0xffFFCCBC), '코랄'),
    ('#CE93D8', Color(0xffCE93D8), '보라'),
  ];
  @override
  Widget build(BuildContext context) {
    final s = context.watch<BookViewModel>().readerSettings;
    return _Sheet(
      title: '보기 설정',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('화면을 편하게 읽어보세요'),
            Row(
              children: [
                const Text('글자 크기'),
                Expanded(
                  child: Slider(
                    value: s.fontScale,
                    min: .8,
                    max: 1.4,
                    divisions: 6,
                    onChanged: (v) => onChange(s.copyWith(fontScale: v)),
                  ),
                ),
              ],
            ),
            const Text('행간'),
            Wrap(
              spacing: 8,
              children: List.generate(
                3,
                (i) => ChoiceChip(
                  label: Text(['좁게', '보통', '넓게'][i]),
                  selected: s.lineHeightStep == i,
                  onSelected: (_) => onChange(s.copyWith(lineHeightStep: i)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text('테마'),
            Wrap(
              spacing: 8,
              children: ReaderPaperTheme.values
                  .map(
                    (t) => ChoiceChip(
                      label: Text(t.name),
                      selected: s.theme == t,
                      onSelected: (_) => onChange(s.copyWith(theme: t)),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 18),
            const Text('형광펜 색상'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: _colors
                  .map(
                    (c) => Tooltip(
                      message: c.$3,
                      child: InkWell(
                        onTap: s.defaultHighlightColor == c.$1
                            ? null
                            : () => onChange(
                                s.copyWith(defaultHighlightColor: c.$1),
                              ),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c.$2,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: s.defaultHighlightColor == c.$1
                                  ? Colors.black87
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: s.defaultHighlightColor == c.$1
                              ? const Icon(Icons.check, size: 18)
                              : null,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerSettings extends StatelessWidget {
  const _ViewerSettings({required this.onChange});
  final ValueChanged<ReaderSettings> onChange;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<BookViewModel>().readerSettings;
    final wide = MediaQuery.of(context).size.width >= 700;
    return _Sheet(
      title: '뷰어 설정',
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('2단으로 보기'),
            subtitle: Text(
              wide ? '넓은 화면에서 두 컬럼으로 표시합니다.' : '넓은 화면에서 사용할 수 있습니다.',
            ),
            value: s.twoColumn,
            onChanged: (v) => onChange(s.copyWith(twoColumn: v)),
          ),
          SwitchListTile(
            title: const Text('읽는 동안 화면 켜 두기'),
            value: s.keepScreenOn,
            onChanged: (v) => onChange(s.copyWith(keepScreenOn: v)),
          ),
        ],
      ),
    );
  }
}
