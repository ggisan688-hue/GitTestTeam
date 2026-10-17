import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/app_config.dart';
import '../../core/room_sync_client.dart';
import '../../model/book.dart';
import '../../model/note_range.dart';
import '../../model/shared_room_note.dart';
import '../../viewmodel/book_viewmodel.dart';
import '../../viewmodel/favorite_viewmodel.dart';
import '../../repository/book_repository.dart';
import '../../repository/reading_room_repository.dart';
import '../../model/reading_room.dart';
import '../../repository/ai_reading_repository.dart';
import 'reading_rooms_screen.dart' show showSharedNoteComments, buildSharedNoteCommentsPanel, showSharedMemoWithComments;
import 'ridi_store.dart';

Widget _aiFriendAvatar(AiReadingFriend friend, {double radius = 18}) {
  const images = {
    'moru': 'assets/images/moru.png',
    'popo': 'assets/images/popo.png',
    'onyou': 'assets/images/onyou.png',
  };
  final path = friend.isDefault ? images[friend.builtinKey] : null;
  final profile = friend.profileImageUrl;
  final fallback = Text(
    friend.name.isEmpty ? '?' : friend.name.characters.take(2).toString(),
    style: TextStyle(fontSize: radius * 0.65, color: const Color(0xFF555555)),
  );
  return CircleAvatar(
    radius: radius,
    foregroundImage: profile?.isNotEmpty == true
        ? NetworkImage(profile!.startsWith('http') ? profile : '${AppConfig.baseUrl}$profile') : null,
    onForegroundImageError: profile?.isNotEmpty == true ? (_, __) {} : null,
    backgroundColor: const Color(0xFFF2F3F7),
    child: path == null ? fallback : ClipOval(
      child: Image.asset(path, width: radius * 2, height: radius * 2,
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
    ),
  );
}

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
    this.initialNoteId,
    this.openInitialComments = false,
  });
  final int bookId;
  final ReaderContext readerContext;
  final int? initialNoteId;
  final bool openInitialComments;
  @override
  State<AdvancedBookReaderScreen> createState() =>
      _AdvancedBookReaderScreenState();
}

class _AdvancedBookReaderScreenState extends State<AdvancedBookReaderScreen> {
  bool _initialNotebookOpened = false;
  late bool _notificationOnly = widget.initialNoteId != null;
  static Future<void>? _referenceFontReady;
  static Future<void> _loadReferenceFont() async {
    final loader = FontLoader('NotoSerifKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSerifKR-Variable.ttf'));
    await loader.load();
  }
  late PageController _controller;
  final _pages = <_Page>[];
  // Reference v1 is independent of device size, user typography and columns.
  final Map<int, List<({int page, int end})>> _standardPageEnds = {};
  final Set<int> _recordedStandardPages = {};
  final Set<int> _pendingStandardPages = {};
  Timer? _standardPageTimer;
  bool _pageStatsBusy = false;

  int _page = 0, _order = 1;
  int _furthestReadOrder = 1;
  Offset? _highlightTapPosition;
  Offset? _pageTapStart;
  DateTime? _pageTapTime;
  bool _annotationTapHandled = false;
  Timer? _pageTapTimer;
  bool _suppressPageTap = false;
  final Map<String, _TextSelection> _activeSelection = {};
  NoteRange? _continuedStart;
  NoteRange? _continuedEnd;
  bool _continuingSelection = false;
  bool _selectionRefreshScheduled = false;
  SelectableRegionState? _currentSelectionRegion;
  final Map<String, GlobalKey<SelectionAreaState>> _selectionAreas = {};
  bool _autoSelectContinuedPage = false;
  int? _continuedTargetOrder;

  String _selectionPageId(_Page page) {
    final slices = page.columns.expand((c) => c).toList();
    return '${slices.first.order}:${slices.first.start}:${slices.last.order}:${slices.last.start}';
  }

  void _selectContinuedPage([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_autoSelectContinuedPage || !_continuingSelection || _pages.isEmpty) return;
      final firstSlice = _pages[_page].columns.expand((c) => c).first;
      if (_continuedTargetOrder != null && firstSlice.order != _continuedTargetOrder) {
        if (attempt < 10) { _selectContinuedPage(attempt + 1); WidgetsBinding.instance.ensureVisualUpdate(); }
        return;
      }
      final area = _selectionAreas[_selectionPageId(_pages[_page])]?.currentState;
      if (area == null) {
        if (attempt < 5) { _selectContinuedPage(attempt + 1); WidgetsBinding.instance.ensureVisualUpdate(); }
        return;
      }
      _autoSelectContinuedPage = false;
      _continuedTargetOrder = null;
      _currentSelectionRegion = area.selectableRegion;
      area.selectableRegion.selectAll(SelectionChangedCause.toolbar);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
  bool _ready = false,
      _controls = false,
      _sheetOpen = false,
      _twoColumns = false;
  bool _savingHighlight = false;
  bool _favorite = false;
  bool _favoriteLoading = true;
  bool _favoriteSaving = false;
  List<ReadingNote> _sharedHighlights = const [];
  List<SharedRoomNote> _sharedMemos = const [];
  List<SharedRoomNote> _roomBookmarks = const [];
  bool _bookmarkSaving = false;
  bool _roomBookmarksLoaded = false;
  bool? _bookmarkPreview;
  ({int order, int offset})? _bookmarkPreviewAnchor;
  int _roomLoadGeneration = 0;
  RoomSyncClient? _readerRoomSync;
  Timer? _roomBodyRefreshTimer;

  List<AiReadingFriend> _aiFriends = const [];
  final Set<int> _selectedAiFriendIds = <int>{};

// AI 친구별 형광펜 색상
  final Map<int, String> _aiFriendHighlightColors = {};

  final Map<int, List<AiReadingNote>> _aiNotesByFriend =
  <int, List<AiReadingNote>>{};

  // AI 친구별 실제 독서 진행률 (0~100)
  final Map<int, int> _aiProgressPercent = <int, int>{};

  // 현재 AI 메모를 생성하고 있는 친구
  final Set<int> _generatingAiFriendIds = <int>{};
  Timer? _aiProgressTimer;
  bool _aiProgressRefreshBusy = false;
  final ValueNotifier<int> _aiProgressVersion = ValueNotifier<int>(0);
  final Set<int> _aiFailedFriendIds = <int>{};
  bool _aiSelectionSaving = false;

  void _notifyAiProgress() {
    if (!mounted) return;
    _aiProgressVersion.value++;
  }

  void _aiMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
  }

  String _friendName(int friendId) {
    for (final friend in _aiFriends) {
      if (friend.id == friendId) return friend.name;
    }
    return 'AI 친구';
  }

  String? _layoutKey;
  int _windowStart = 0;
  int _windowEnd = 0;
  List<BookParagraph> _paginationSource = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _ViewSettingsState._spoiler.addListener(_spoilerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      unawaited(_loadFavorite());
      await _ViewSettingsState._loadSpoilerPreference(context);
      if (!mounted) return;
      final vm = context.read<BookViewModel>();
      await vm.loadReader(widget.bookId);
      final p = vm.content?.paragraphs ?? const <BookParagraph>[];
      if (!mounted || p.isEmpty) return;
      var saved = vm.readingProgress?.lastReadPosition ?? p.first.order;
      // All reading contexts resume from the account/book cursor.
      if (!mounted) return;
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
      _furthestReadOrder = ((vm.readingProgress?.maxReadPosition ?? 0) > _order ? vm.readingProgress!.maxReadPosition : _order);
      // Use the bundled face before measuring either display or reference pages.
      await (_referenceFontReady ??= _loadReferenceFont());
      if (!mounted) return;
      _ready = true;
      await _wake(vm.readerSettings.keepScreenOn);
      if (mounted) setState(() {});
      if (widget.readerContext.roomId != null) {
        _readerRoomSync = RoomSyncClient(
          repository: _readerRoomRepository,baseUrl: AppConfig.baseUrl,
          token: context.read<RidiStore>().accessToken,
          roomId: widget.readerContext.roomId!,
          onChanged: () {
            _roomBodyRefreshTimer?.cancel();
            _roomBodyRefreshTimer = Timer(const Duration(milliseconds: 150), () {
              if (!mounted) return;
              unawaited(_loadSharedHighlights().catchError((Object error) {
                debugPrint('본문 메모 갱신 실패: $error');
              }));
            });
          },
        )..start();
      }
      unawaited(_loadSharedHighlights().catchError((Object error) {
        if (mounted) _aiMessage('독서방 메모를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.');
      }));
      unawaited(_restoreAiFriendSelection());
    });
  }

  Future<void> _wake(bool enabled) =>
      enabled ? WakelockPlus.enable() : WakelockPlus.disable();

  // AI 친구별 실제 진행률 가져오기
  Future<void> _refreshAiProgress() async {
    if (!mounted || _generatingAiFriendIds.isEmpty || _aiProgressRefreshBusy)
      return;
    _aiProgressRefreshBusy = true;
    try {
      final token = context.read<RidiStore>().accessToken;
      final repository = AiReadingRepository(
        ApiClient(tokenProvider: () => token),
      );
      for (final friendId in _generatingAiFriendIds.toList()) {
        try {
          final result = await repository.getReadingProgress(
            bookId: widget.bookId,
            friendId: friendId,
          );
          if (!mounted) return;
          final percent = (result['percent'] as num?)?.toInt() ?? 0;
          _aiProgressPercent[friendId] = percent.clamp(0, 100).toInt();
          _notifyAiProgress();
        } catch (e) {
          debugPrint('AI 친구 진행률 조회 실패: $e');
        }
      }
    } finally {
      _aiProgressRefreshBusy = false;
    }
  }

  void _startAiProgressPolling() {
    _aiProgressTimer?.cancel();
    unawaited(_refreshAiProgress());
    _aiProgressTimer = Timer.periodic(
      const Duration(seconds: 2),
          (_) => unawaited(_refreshAiProgress()),
    );
  }

  // 메모 생성은 보기 설정 팝업과 독립적으로 실행한다.
  Future<void> _generateAiNotesInReader(
      AiReadingRepository repository,
      Set<int> selectedIds,
      ) async {
    for (final friendId in selectedIds) {
      if (!mounted) return;
      _generatingAiFriendIds.add(friendId);
      _aiFailedFriendIds.remove(friendId);
      _aiProgressPercent[friendId] = 0;
      _notifyAiProgress();
      _startAiProgressPolling();
      try {
        final startedAt = DateTime.now();
        final notes = await repository.generateNotes(
          bookId: widget.bookId,
          friendId: friendId,
        );
        if (!mounted) return;
        // generateNotes는 파싱 실패 시 정상 반환할 수 있으므로 완료 상태를 검증한다.
        final progress = await repository.getReadingProgress(
          bookId: widget.bookId,
          friendId: friendId,
        );
        if (!mounted) return;
        final completed = progress['completed'] == true;
        final percent = (progress['percent'] as num?)?.toInt() ?? 0;
        setState(() {
          _aiNotesByFriend[friendId] = notes;
          _aiProgressPercent[friendId] = completed
              ? 100
              : percent.clamp(0, 99).toInt();
        });
        if (completed) {
          if (DateTime.now().difference(startedAt).inSeconds >= 3) _aiMessage('${_friendName(friendId)}가 AI 메모 작성을 완료했어요.');
        } else {
          _aiFailedFriendIds.add(friendId);
          _aiMessage(
            '${_friendName(friendId)}의 AI 메모 작성이 중간에 멈췄어요. 다시 시도해 주세요.',
          );
        }
      } catch (e) {
        if (!mounted) return;
        _aiFailedFriendIds.add(friendId);
        _aiMessage('${_friendName(friendId)}의 AI 메모 작성 중 오류가 발생했어요.');
        debugPrint('AI 메모 생성 실패 (friendId=$friendId): $e');
        // 오류가 나도 다른 친구의 작업은 이어서 시도한다.
      } finally {
        _generatingAiFriendIds.remove(friendId);
        if (_generatingAiFriendIds.isEmpty) {
          _aiProgressTimer?.cancel();
          _aiProgressTimer = null;
        }
        _notifyAiProgress();
      }
    }
  }

  Future<void> _restoreAiFriendSelection() async {
    if (!mounted || widget.readerContext.isReadingRoom) return;

    final token = context.read<RidiStore>().accessToken;
    final repository = AiReadingRepository(
      ApiClient(tokenProvider: () => token),
    );

    try {
      // 현재 계정과 책에 저장된 AI 친구 목록 조회
      final selectedIds = await repository.getSelectedFriendIds(
        bookId: widget.bookId,
      );

      // 책을 다시 열 때 AI 친구 정보도 함께 복원
      final friendLists = await Future.wait([
        repository.getDefaultFriends(),
        repository.getMyFriends(),
      ]);


      final loadedFriends = <AiReadingFriend>[
        ...friendLists[0],
        ...friendLists[1],
      ];

// AI 친구별 저장된 형광펜 색상 불러오기
      final loadedColors = <int, String>{};

      await Future.wait(
        loadedFriends.map((friend) async {
          try {
            loadedColors[friend.id] =
            await repository.getFriendHighlightColor(friend.id);
          } catch (e) {
            debugPrint('AI 친구 ${friend.id} 색상 조회 실패: $e');
            loadedColors[friend.id] = '#FFF59D';
          }
        }),
      );

      final loadedNotes = <int, List<AiReadingNote>>{};


      // 기존 AI 메모만 조회한다. 새로 생성하지 않는다.
      for (final friendId in selectedIds) {
        loadedNotes[friendId] = await repository.getNotes(
          bookId: widget.bookId,
          friendId: friendId,
        );
      }

      if (!mounted) return;

      setState(() {
        _aiFriends = loadedFriends;

        _aiFriendHighlightColors
          ..clear()
          ..addAll(loadedColors);

        _selectedAiFriendIds
          ..clear()
          ..addAll(selectedIds);

        _aiNotesByFriend
          ..clear()
          ..addAll(loadedNotes);
      });
    } on ApiException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 친구 선택 상태를 불러오지 못했습니다: ${e.message}')),
      );
    }
  }

  ReadingRoomRepository get _readerRoomRepository => ReadingRoomRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken));

  void _applyRoomNotes(List<SharedRoomNote> notes) {
    if (!mounted) return;
    setState(() {
      _sharedHighlights = notes.where((n) => !n.isSpoilerLocked &&
          n.type == 'HIGHLIGHT' && n.startOffset != null && n.endOffset != null)
          .map(_asReaderHighlight).toList();
      _sharedMemos = notes.where((n) => n.type == 'MEMO').toList();
      _roomBookmarks = notes.where((n) => n.mine && n.type == 'BOOKMARK').toList();
      _roomBookmarksLoaded = true;
    });
  }

  Future<void> _loadSharedHighlights() async {
    final roomId = widget.readerContext.roomId;
    if (roomId == null || !mounted) return;
    final generation = ++_roomLoadGeneration;
    final notes = await _readerRoomRepository.sharedNotes(roomId, bookId: widget.bookId, reader: true);
    if (mounted && generation == _roomLoadGeneration) _applyRoomNotes(notes);
  }

  Future<void> _updateReaderNote(int id, {String? memo, String? color}) async {
    if (!widget.readerContext.isReadingRoom) {
      await context.read<BookViewModel>().updateNote(widget.bookId, id, memo: memo, color: color);
      return;
    }
    await _readerRoomRepository.updateSharedNote(widget.readerContext.roomId!, id, {
      if (memo != null) 'content': memo,
      if (color != null) 'highlightColor': color,
    });
    await _loadSharedHighlights();
  }

  Future<void> _deleteReaderNote(int id) async {
    if (!widget.readerContext.isReadingRoom) {
      await context.read<BookViewModel>().deleteNote(widget.bookId, id);
      return;
    }
    await _readerRoomRepository.deleteSharedNote(widget.readerContext.roomId!, id);
    await _loadSharedHighlights();
  }

  ReadingNote _asReaderHighlight(SharedRoomNote note) => ReadingNote(
    id: note.mine ? note.id : -note.id,
    type: ReaderNoteType.highlight,
    paragraphOrder: note.paragraphOrder,
    selectedText: note.selectedText,
    startOffset: note.startOffset,
    endOffset: note.endOffset,
    highlightColor: note.highlightColor,
    preview: '',
    createdAt: note.createdAt,
    readOnly: !note.mine,
  );
  ReadingNote _asAiReaderHighlight(AiReadingNote note) => ReadingNote(
    id: -1000000000 - note.id,
    type: ReaderNoteType.highlight,
    paragraphOrder: note.paragraphOrder,
    selectedText: note.selectedText,
    startOffset: note.startOffset,
    endOffset: note.endOffset,
    highlightColor: note.highlightColor,
    preview: note.content,
    createdAt: null,
  );
  void _scheduleStandardPageRead() {
    _standardPageTimer?.cancel();
    if (_notificationOnly || _sheetOpen || _pages.isEmpty || !context.read<RidiStore>().loggedIn) return;
    final visible = _pages[_page];
    _standardPageTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
          _pages.isEmpty || !identical(_pages[_page], visible)) return;
      // A reference page is visited when its final character is displayed.
      // A jump records only visible endpoints, never the pages skipped over.
      for (final slice in visible.columns.expand((column) => column)) {
        for (final marker in _standardPageEnds[slice.order] ??
            const <({int page, int end})>[]) {
          if (marker.end > slice.start && marker.end <= slice.start + slice.text.length &&
              !_recordedStandardPages.contains(marker.page)) {
            _pendingStandardPages.add(marker.page);
          }
        }
      }
      unawaited(_flushStandardPages());
    });
  }

  Future<void> _flushStandardPages() async {
    if (_pageStatsBusy || _pendingStandardPages.isEmpty || !mounted) return;
    _pageStatsBusy = true;
    final vm = context.read<BookViewModel>();
    try {
      while (_pendingStandardPages.isNotEmpty && mounted) {
        final batch = _pendingStandardPages.take(200).toList();
        await vm.recordStandardPages(widget.bookId, batch);
        _recordedStandardPages.addAll(batch);
        _pendingStandardPages.removeAll(batch);
      }
    } catch (error) {
      // Retain pending pages; a retry is safe because the server deduplicates.
      debugPrint('페이지 독서량 저장 실패: $error');
    } finally {
      _pageStatsBusy = false;
    }
  }

  Future<void> _save() async {
    if (_notificationOnly) return;
    _timer?.cancel();
    final p =
        context.read<BookViewModel>().content?.paragraphs ??
            const <BookParagraph>[];
    if (p.isEmpty || !mounted) return;
    await _flushStandardPages();
    if (!mounted) return;
    if (widget.readerContext.isReadingRoom) {
      final percent = ((_order / p.last.order) * 100)
          .round()
          .clamp(0, 100)
          .toInt();
      await ReadingRoomRepository(
        ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
      ).saveProgress(
        widget.readerContext.roomId!,
        widget.bookId,
        progressPercent: percent,
        lastReadPosition: _order,
      );
      if (mounted) await context.read<BookViewModel>().loadRecentBooks();
      return;
    }
    await context.read<BookViewModel>().saveReaderProgress(
      widget.bookId,
      _order,
      p.last.order,
    );
  }

  void _spoilerChanged() { if (mounted) setState(() {}); }

  void _debounceSave() {
    if (_order > _furthestReadOrder) _furthestReadOrder = _order;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), _save);
  }

  @override
  void dispose() {
    _standardPageTimer?.cancel();
    _roomBodyRefreshTimer?.cancel();
    _readerRoomSync?.dispose();
    _ViewSettingsState._spoiler.removeListener(_spoilerChanged);
    _timer?.cancel();
    _pageTapTimer?.cancel();
    _aiProgressTimer?.cancel();
    _aiProgressVersion.dispose();
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
        // The editor dialog handles the keyboard; keep book pagination stable.
        resizeToAvoidBottomInset: false,
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
                Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (event) {
                    _highlightTapPosition = event.position;
                    // A second press during the double-tap window belongs to
                    // text selection. Cancel the pending single-tap action.
                    _suppressPageTap = (_pageTapTimer?.isActive ?? false) ||
                        _activeSelection.isNotEmpty || _continuingSelection;
                    _pageTapTimer?.cancel();
                    _annotationTapHandled = false;
                    _pageTapStart = event.localPosition;
                    _pageTapTime = DateTime.now();
                  },
                  onPointerCancel: (_) {
                    _pageTapTimer?.cancel();
                    _suppressPageTap = false;
                    _pageTapStart = null;
                    _pageTapTime = null;
                    _annotationTapHandled = false;
                  },
                  onPointerUp: (event) {
                    final start = _pageTapStart;
                    final time = _pageTapTime;
                    final end = event.localPosition;
                    final width = c.maxWidth;

                    _pageTapStart = null;
                    _pageTapTime = null;

                    if (_suppressPageTap || _sheetOpen ||
                        ModalRoute.of(context)?.isCurrent != true ||
                        start == null || time == null) {
                      return;
                    }

                    // 길게 누르기와 드래그 제외
                    if (DateTime.now().difference(time).inMilliseconds > 250 ||
                        (end - start).distance > 10) {
                      return;
                    }

                    // Wait for the double-tap selection window before treating
                    // this as a single tap for page navigation or controls.
                    _pageTapTimer = Timer(
                        kDoubleTapTimeout + const Duration(milliseconds: 50), () {
                      if (!mounted || _sheetOpen ||
                          ModalRoute.of(context)?.isCurrent != true ||
                          _annotationTapHandled || _activeSelection.isNotEmpty || _continuingSelection) {
                        return;
                      }

                      final x = end.dx;

                      if (x < width * 0.25) {
                        if (_page > 0 && _controller.hasClients) {
                          _controller.previousPage(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          );
                        }
                      } else if (x > width * 0.75) {
                        if (_page < _pages.length - 1 && _controller.hasClients) {
                          _controller.nextPage(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          );
                        }
                      } else {
                        setState(() => _controls = !_controls);
                      }
                    });

                    WidgetsBinding.instance.ensureVisualUpdate();
                  },
                  child: PageView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) {
                      _activeSelection.clear();
                      if (!_continuingSelection) {
                        _continuedStart = null;
                        _continuedEnd = null;
                      }
                      if (_pages.isEmpty) return;
                      setState(() {
                        _page = i;
                        _order = _pages[i].firstOrder;
                      });
                      _scheduleStandardPageRead();
                      if (!_sheetOpen && _initialNotebookOpened) _notificationOnly = false;
                      _debounceSave();
                      _expandWindowIfNeeded();
                    },
                    itemBuilder: (_, i) => _ReaderPage(
                      selectionKey: _selectionAreas.putIfAbsent(
                          _selectionPageId(_pages[i]), () => GlobalKey<SelectionAreaState>()),
                      onSelection: (key, value) {
                        if (i != _page) return;
                        if (value == null) {
                          _activeSelection.remove(key);
                        } else {
                          _activeSelection[key] = value;
                          _pageTapTimer?.cancel();
                          if (_continuingSelection) {
                            final current = _currentRange();
                            if (current != null) {
                              final end = current.ranges.last;
                              if (_continuedEnd?.paragraphOrder != end.paragraphOrder ||
                                  _continuedEnd?.endOffset != end.endOffset) {
                                _continuedEnd = end;
                                if (!_selectionRefreshScheduled) {
                                  _selectionRefreshScheduled = true;
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    _selectionRefreshScheduled = false;
                                    if (mounted) setState(() {});
                                  });
                                }
                              }
                            }
                          }
                        }
                      },
                      selectionToolbar: (context, region) => _selectionToolbar(i, region),
                      continuedRanges: _continuedStart == null || _continuedEnd == null
                          ? const [] : _rangeBetween(_continuedStart!, _continuedEnd!),
                      page: _pages[i.clamp(0, _pages.length - 1)],
                      settings: vm.readerSettings,
                      twoColumns: _twoColumns,
                      highlights: vm.readerSettings.showHighlights
                          ? [
                        // 내가 직접 만든 형광펜
                        ...(widget.readerContext.isReadingRoom ? const <ReadingNote>[] : vm.readingNotes).where(
                              (n) => n.type == ReaderNoteType.highlight,
                        ),

                        // 교환독서 상대방 형광펜
                        ..._sharedHighlights,

                        // 메모에 저장된 선택 범위도 동일한 위치에 표시한다.
                        ...(widget.readerContext.isReadingRoom ? const <ReadingNote>[] : vm.readingNotes).expand(_memoFragments)
                            .where(
                              (n) =>
                          n.type == ReaderNoteType.memo &&
                              n.startOffset != null &&
                              n.endOffset != null,
                        )
                            .map(
                              (n) => ReadingNote(
                            id: -2000000000 - n.id,
                            type: ReaderNoteType.highlight,
                            paragraphOrder: n.paragraphOrder,
                            selectedText: n.selectedText,
                            startOffset: n.startOffset,
                            endOffset: n.endOffset,
                            highlightColor: n.highlightColor ?? '#FFF59D',
                            preview: n.memoContent ?? '',
                            createdAt: n.createdAt,
                          ),
                        ),
                        ..._sharedMemos.expand(_sharedMemoFragments)
                            .where(
                              (n) =>
                          !n.isSpoilerLocked &&
                              n.startOffset != null &&
                              n.endOffset != null,
                        )
                            .map(
                              (n) => ReadingNote(
                            id: -3000000000 - n.id,
                            type: ReaderNoteType.highlight,
                            paragraphOrder: n.paragraphOrder,
                            selectedText: n.selectedText,
                            startOffset: n.startOffset,
                            endOffset: n.endOffset,
                            highlightColor: n.highlightColor ?? '#FFF59D',
                            preview: n.content ?? '',
                            createdAt: n.createdAt,
                          ),
                        ),

// 선택한 AI 친구가 만든 형광펜
                        ..._selectedAiFriendIds.expand(
                              (friendId) => (_aiNotesByFriend[friendId] ??
                              const <AiReadingNote>[])
                              .map(
                                (note) => ReadingNote(
                              id: -1000000000 - note.id,
                              type: ReaderNoteType.highlight,
                              paragraphOrder: note.paragraphOrder,
                              selectedText: note.selectedText,
                              startOffset: note.startOffset,
                              endOffset: note.endOffset,
                              highlightColor:
                              _aiFriendHighlightColors[friendId] ?? '#FFF59D',
                              preview: note.content,
                              createdAt: null,
                            ),
                          ),
                        ),

                      ]
                          : const <ReadingNote>[],
                      onHighlight: _saveHighlight,
                      onHighlightTap: _openHighlightMenu,
                      memos: widget.readerContext.isReadingRoom
                          ? const <ReadingNote>[]
                          : vm.readingNotes
                          .where((n) => n.type == ReaderNoteType.memo)
                          .map((note) => _memoFragments(note).last).toList(),
                      additionalMemoRanges: [
                        ..._selectedAiFriendIds
                            .expand(
                              (friendId) =>
                          _aiNotesByFriend[friendId] ??
                              const <AiReadingNote>[],
                        )
                            .where((note) => note.endOffset != null)
                            .map(
                              (note) => _MemoRange(
                            note.paragraphOrder,
                            note.startOffset,
                            note.endOffset!,
                          ),
                        ),
                        ..._sharedMemos.map((note) => _sharedMemoFragments(note).last)
                            .where(
                              (note) =>
                          !note.isSpoilerLocked &&
                              note.endOffset != null,
                        )
                            .map(
                              (note) => _MemoRange(
                            note.paragraphOrder,
                            note.startOffset,
                            note.endOffset!,
                            noteId: note.id,
                          ),
                        ),
                      ],
                      roomMemoCounts: {
                        for (final memo in _sharedMemos.map((note) => _sharedMemoFragments(note).last))
                          memo.paragraphOrder: _sharedMemos.map((note) => _sharedMemoFragments(note).last)
                              .where(
                                (item) =>
                            item.paragraphOrder ==
                                memo.paragraphOrder,
                          )
                              .length,
                      },
                      onMemo: _saveSelectionMemo,
                      onShowMemos: _showParagraphMemos,
                    ),
                  ),
                ),
                if (_continuingSelection)
                  Positioned(
                    left: 24, right: 24, bottom: 24,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: 3,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(children: [
                          const Expanded(child: Text('선택 끝을 조절한 뒤 형광펜 또는 메모를 선택하세요.')),
                          TextButton(onPressed: _clearContinuedSelection, child: const Text('선택 취소')),
                        ]),
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
    final settingsChanged = _layoutKey != null && _layoutKey != key;
    _layoutKey = key;
    _paginationSource = p;
    final orderIndex = p.indexWhere((paragraph) => paragraph.order == _order);
    if (settingsChanged || _windowEnd == 0 || _windowEnd > p.length) {
      final anchor = orderIndex < 0 ? 0 : orderIndex;
      _windowStart = (anchor - 24).clamp(0, p.length);
      _windowEnd = (anchor + 96).clamp(_windowStart + 1, p.length);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _layoutKey != key) return;
      // TextPainter measurement is deliberately bounded to the visible
      // reading window. More paragraphs are paginated only as the reader
      // approaches the window edge; this avoids long-book entry jank.
      _windowStart = 0;
      _windowEnd = p.length;

      if (_standardPageEnds.isEmpty) {
        final reference = _paginate(p, const ReaderSettings(),
            1280, 800, false, TextScaler.noScaling);
        for (var i = 0; i < reference.length; i++) {
          final last = reference[i].columns.expand((column) => column).last;
          _standardPageEnds.putIfAbsent(last.order, () => []).add(
            (page: i + 1, end: last.start + last.text.length),
          );
        }
      }
      final pages = _paginate(
        p,
        s,
        c.maxWidth,
        c.maxHeight,
        two,
        textScaler,
      );
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
      _scheduleStandardPageRead();
      // The PageView is created by the setState above.  Jumping in the same
      // callback runs before it attaches to PageController, so it was silently
      // skipped and the controller's initial page (0) won.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _layoutKey == key &&
            _controller.hasClients &&
            pages.isNotEmpty)
          _controller.jumpToPage(targetPage);
        if (mounted && pages.isNotEmpty && widget.initialNoteId != null && !_initialNotebookOpened) {
          _initialNotebookOpened = true;
          _notes(targetNoteId: widget.initialNoteId, openComments: widget.openInitialComments);
        }
      });
    });
  }

  void _expandWindowIfNeeded() {
    if (_pages.isEmpty) return;
    if (_page <= 2 && _windowStart > 0) {
      _windowStart = (_windowStart - 80).clamp(0, _windowStart);
    } else if (_page >= _pages.length - 3 &&
        _windowEnd < _paginationSource.length) {
      _windowEnd = (_windowEnd + 80).clamp(
        _windowEnd,
        _paginationSource.length,
      );
    } else {
      return;
    }
    _layoutKey = null;
    if (mounted) setState(() {});
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
    // 상·하단 여백 260 + 글꼴 및 문단 높이 오차 여유 40
    final columnWidth = (width - (two ? 86 : 60)) / (two ? 2 : 1),
        limit = height - 300;
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

  Future<void> _loadFavorite() async {
    if (!context.read<RidiStore>().loggedIn) {
      setState(() => _favoriteLoading = false);
      return;
    }
    try {
      final repository = BookRepository(
        ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
      );
      final favorite = await repository.favoriteStatus(widget.bookId);
      if (mounted) setState(() => _favorite = favorite);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('즐겨찾기 상태를 불러오지 못했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _favoriteLoading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteLoading || _favoriteSaving) return;
    if (!context.read<RidiStore>().loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }
    final before = _favorite;
    setState(() {
      _favorite = !before;
      _favoriteSaving = true;
    });
    try {
      await context.read<FavoriteViewModel>().setFavorite(widget.bookId, !before);
    } catch (error) {
      if (mounted) {
        setState(() => _favorite = before);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is ApiException
              ? error.message
              : '즐겨찾기를 변경하지 못했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _favoriteSaving = false);
    }
  }

  Widget _top(BookViewModel vm) {
    final fg = _colors(vm.readerSettings).$2;
    final chapters = vm.readerChapters
        .where((c) => c.startParagraphOrder <= _order)
        .toList();
    final title = chapters.isEmpty ? vm.content!.title : chapters.last.title;
    final previewAnchor = _bookmarkPreviewAnchor;
    final marked = widget.readerContext.isReadingRoom
        ? (_bookmarkPreview != null && previewAnchor != null &&
        _isBookmarkOnPage(previewAnchor.order, previewAnchor.offset)
        ? _bookmarkPreview!
        : _roomBookmarks.any((note) =>
        _isBookmarkOnPage(note.paragraphOrder, note.startOffset)))
        : vm.readingNotes.any((note) =>
    note.type == ReaderNoteType.bookmark && note.paragraphOrder == _order);
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
                tooltip: _favorite ? '즐겨찾기 해제' : '즐겨찾기',
                onPressed: _favoriteLoading || _favoriteSaving
                    ? null
                    : _toggleFavorite,
                icon: _favoriteSaving
                    ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg,
                  ),
                )
                    : Icon(
                  _favorite ? Icons.favorite : Icons.favorite_border,
                  color: _favorite ? Colors.red : fg,
                ),
              ),
              IconButton(
                onPressed: _bookmarkSaving || (widget.readerContext.isReadingRoom && !_roomBookmarksLoaded)
                    ? null : () => _bookmark(vm),
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

  bool _isBookmarkOnPage(int order, int? offset, {_Page? page}) {
    final target = page ?? (_pages.isEmpty ? null : _pages[_page]);
    if (target == null) return order == _order;
    final position = offset ?? 0;
    return target.columns.expand((column) => column).any((slice) =>
    slice.order == order && position >= slice.start &&
        position < slice.start + slice.text.length);
  }

  Future<void> _bookmark(BookViewModel vm) async {
    if (_bookmarkSaving) return;
    if (widget.readerContext.isReadingRoom) {
      final roomId = widget.readerContext.roomId!;
      final visible = _pages.isEmpty ? null : _pages[_page];
      final anchor = visible?.columns.expand((column) => column).first;
      final order = anchor?.order ?? _order;
      final offset = anchor?.start ?? 0;
      if (!_roomBookmarksLoaded) return;
      final hits = _roomBookmarks.where((note) =>
          _isBookmarkOnPage(note.paragraphOrder, note.startOffset, page: visible)).toList();
      setState(() {
        _bookmarkSaving = true;
        _bookmarkPreview = hits.isEmpty;
        _bookmarkPreviewAnchor = (order: order, offset: offset);
      });
      try {
        if (hits.isEmpty) {
          final saved = await _readerRoomRepository.createSharedNote(roomId, {
            'type': 'BOOKMARK',
            'bookId': widget.bookId,
            'paragraphOrder': order,
            'startOffset': offset,
          });
          if (mounted) setState(() {
            ++_roomLoadGeneration;
            _roomBookmarks = [..._roomBookmarks.where((note) => note.id != saved.id), saved];
          });
        } else {
          for (final note in hits) {
            await _readerRoomRepository.deleteSharedNote(roomId, note.id);
            if (mounted) setState(() {
              ++_roomLoadGeneration;
              _roomBookmarks = _roomBookmarks.where((value) => value.id != note.id).toList();
            });
          }
        }
      } catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('책갈피 저장 실패: $error')));
      } finally {
        if (mounted) setState(() {
          _bookmarkSaving = false;
          _bookmarkPreview = null;
          _bookmarkPreviewAnchor = null;
        });
      }
      return;
    }
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
        onPressed: action,style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: MediaQuery.sizeOf(context).width < 600 ? 2 : 12)),
        icon: Icon(icon, size: MediaQuery.sizeOf(context).width < 600 ? 18 : 26),
        label: Text(
          label,
          style: TextStyle(fontSize: MediaQuery.sizeOf(context).width < 600 ? 12 : 18, fontWeight: FontWeight.w600),
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
        // Dialog applies keyboard insets before constraining the notes panel.
        // Keep the reader Scaffold itself fixed to avoid repaginating the book.
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(color: Colors.transparent, child: child),
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
                    await context.read<BookViewModel>().loadReader(
                      widget.bookId,
                    );
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
                        fontWeight: on
                            ? FontWeight.w800
                            : FontWeight.w500,
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
  void _notes({int? targetNoteId, bool openComments = false}) => _open(
    _Notes(
      bookId: widget.bookId,
      targetNoteId: targetNoteId,
      openInitialComments: openComments,
      order: _order,
      currentPage: _page + 1,
      spoilerReadOrder: _furthestReadOrder,
      onGo: _go,
      pageOf: (order, offset) {
        final index = _pages.indexWhere(
              (page) => page.columns
              .expand((column) => column)
              .any(
                (slice) =>
            slice.order == order &&
                (offset == null ||
                    (offset >= slice.start &&
                        offset <
                            slice.start + slice.text.length)),
          ),
        );

        return index < 0 ? null : index + 1;
      },
      roomId: widget.readerContext.roomId,
      initialRoomBookmarks: _roomBookmarksLoaded ? List.of(_roomBookmarks) : null,
      onRoomNotesLoaded: (_) {
        // Notebook responses are masked; the body must use its unmasked view.
        unawaited(_loadSharedHighlights().catchError((Object error) {
          debugPrint('본문 메모 갱신 실패: $error');
        }));
      },
      aiFriends: _aiFriends,
      selectedAiFriendIds: _selectedAiFriendIds,
      aiNotesByFriend: _aiNotesByFriend,
      aiFriendHighlightColors: _aiFriendHighlightColors,
    ),
  );

  Future<void> _viewSettings() async {
    final store = context.read<RidiStore>();

    final repository = AiReadingRepository(
      ApiClient(tokenProvider: () => store.accessToken),
    );

    try {
      // 보기 설정을 열 때 서버에서 현재 사용 가능한 AI 친구 목록을 가져온다.
      final loaded = await Future.wait([
        repository.getDefaultFriends(),
        repository.getMyFriends(),
      ]);
      final friends = <AiReadingFriend>[...loaded[0], ...loaded[1]];

      if (!mounted) return;

      _aiFriends = friends;

      await _open(
        place: _SheetPlace.corner,
        _ViewSettings(
          showAiFriends: !widget.readerContext.isReadingRoom,
          onChange: (s) async {
            try {
              await context.read<BookViewModel>().saveSettings(s);
              _layoutKey = null;
            } on ApiException catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(e.message)));
              }
            }
          },

          aiFriends: _aiFriends,

          selectedAiFriendIds: _selectedAiFriendIds,

          progressVersion: _aiProgressVersion,
          progressPercent: _aiProgressPercent,
          generatingFriendIds: _generatingAiFriendIds,
          failedFriendIds: _aiFailedFriendIds,
          onAiFriendDone: (selectedIds) async {
            if (widget.readerContext.isReadingRoom || _aiSelectionSaving) return;
            _aiSelectionSaving = true;
            try {
              // 선택을 먼저 저장한다. AI 생성 완료까지 팝업을 붙잡지 않는다.
              await repository.saveSelectedFriendIds(
                bookId: widget.bookId,
                friendIds: selectedIds,
              );
              if (!mounted) return;
              setState(() {
                _selectedAiFriendIds
                  ..clear()
                  ..addAll(selectedIds);
                _aiNotesByFriend.removeWhere(
                      (friendId, _) => !selectedIds.contains(friendId),
                );
              });
              _notifyAiProgress();
              final pending = selectedIds
                  .where((id) => !_generatingAiFriendIds.contains(id))
                  .toSet();
              if (pending.isNotEmpty) {
                unawaited(_generateAiNotesInReader(repository, pending));
              }
            } finally {
              _aiSelectionSaving = false;
            }
          },
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 친구 목록을 불러오지 못했습니다: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 친구 목록을 불러오는 중 오류가 발생했습니다.')),
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

  void _go(int order, [int? offset]) {
    _notificationOnly = false;
    // A paragraph can span several pages. Match the saved character offset
    // instead of always selecting the paragraph's first page.
    var i = offset == null ? -1 : _pages.indexWhere((page) =>
        page.columns.expand((column) => column).any((slice) =>
        slice.order == order && offset >= slice.start &&
            offset < slice.start + slice.text.length));
    if (i < 0) i = _pages.indexWhere((page) => page.contains(order));
    if (i >= 0) {
      _controller.jumpToPage(i);
      setState(() {
        _page = i;
        _order = order;
      });
      _debounceSave();
      return;
    }
    // TOC targets can sit outside the lazy window. Re-anchor first; the next
    // layout pass paginates only the target neighbourhood and restores it.
    final sourceIndex = _paginationSource.indexWhere((p) => p.order == order);
    if (sourceIndex < 0) return;
    setState(() {
      _order = order;
      _windowStart = (sourceIndex - 24).clamp(0, _paginationSource.length);
      _windowEnd = (sourceIndex + 96).clamp(
        _windowStart + 1,
        _paginationSource.length,
      );
      _layoutKey = null;
    });
  }

  Future<bool> _showAllMatchingMemos(
      int paragraphOrder, {
        int? startOffset,
        int? endOffset,
      }) async {
    _annotationTapHandled = true;
    if (!mounted) return false;

    final items = <({
    String author,
    String content,
    String quote,
    Color color,
    int? editableNoteId,
    })>[];

    bool matches(int order, int? start, int? end) {
      if (order != paragraphOrder) return false;

      // 범위를 알 수 없는 아이콘은 해당 문단의 메모를 모두 표시
      if (startOffset == null || endOffset == null) return true;

      // 범위 없는 메모를 특정 선택 범위에 섞지 않음
      if (start == null || end == null) return false;

      // 선택 범위가 동일하거나 일부라도 겹치는 메모
      return start < endOffset! && end > startOffset!;
    }

    bool matchesRanges(List<NoteRange> ranges, int order, int? start, int? end) {
      return ranges.isEmpty ? matches(order, start, end)
          : ranges.any((r) => matches(r.paragraphOrder, r.startOffset, r.endOffset));
    }

    if (widget.readerContext.isReadingRoom) {
      final notes = _sharedMemos.where((note) => !note.isSpoilerLocked &&
          matchesRanges(note.ranges, note.paragraphOrder, note.startOffset, note.endOffset)).toList();
      if (notes.isNotEmpty) {
        final wasOpen = _sheetOpen;
        setState(() => _sheetOpen = true);
        try {
          await showSharedMemoWithComments(context,
              ReadingRoomRepository(ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken)),
              widget.readerContext.roomId!, notes);
        } finally {
          if (mounted) {
            setState(() => _sheetOpen = wasOpen);
            try { await _loadSharedHighlights(); }
            catch (_) { /* Keep the last rendered notes when refresh is offline. */ }
          }
        }
        return true;
      }
    }

    // 개인 독서 화면의 내 메모
    if (!widget.readerContext.isReadingRoom) {
      for (final note in context.read<BookViewModel>().readingNotes) {
        if (note.type == ReaderNoteType.memo &&
            matchesRanges(note.ranges, note.paragraphOrder, note.startOffset, note.endOffset)) {
          items.add((
          editableNoteId: note.id,
          author: '내 메모',
          content: note.memoContent ?? '메모 내용이 없습니다.',
          quote: note.selectedText ?? '',
          color: _highlightColor(note.highlightColor),
          ));
        }
      }
    }

    // 독서방의 공유 메모
    if (widget.readerContext.isReadingRoom) {
      for (final note in _sharedMemos) {
        // 잠긴 메모의 내용과 선택 범위는 표시하지 않음
        if (note.isSpoilerLocked) continue;

        if (matchesRanges(note.ranges, note.paragraphOrder, note.startOffset, note.endOffset)) {
          items.add((
          editableNoteId: note.mine ? note.id : null,
          author: note.nickname,
          content: note.content ?? '메모 내용이 없습니다.',
          quote: note.selectedText ?? '',
          color: _highlightColor(note.highlightColor),
          ));
        }
      }
    }

    // 현재 선택한 AI 친구의 메모
    for (final friendId in _selectedAiFriendIds) {
      for (final note
      in _aiNotesByFriend[friendId] ?? const <AiReadingNote>[]) {
        if (matches(
          note.paragraphOrder,
          note.startOffset,
          note.endOffset,
        )) {
          items.add((
          editableNoteId: null,
          author: _friendName(friendId),
          content: note.content,
          quote: note.selectedText ?? '',
          color: _highlightColor(
            _aiFriendHighlightColors[friendId] ?? '#FFF59D',
          ),
          ));
        }
      }
    }

    if (items.isEmpty) return false;

    int currentIndex = 0;
    bool saving = false;
    String? saveError;
    final editors = items.map((item) => item.editableNoteId == null
        ? null : TextEditingController(text: item.content)).toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _MemoEditorLifetime(
        controllers: editors,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final item = items[currentIndex];

            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.all(24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 560,
                  maxHeight: MediaQuery.sizeOf(context).height - 80,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 56,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Text(
                              '메모',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Positioned(
                              left: 8,
                              child: TextButton(
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                },
                                child: const Text(
                                  '닫기',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 8,
                              child: TextButton(
                                onPressed: saving ? null : () async {
                                  if (item.editableNoteId == null) {
                                    Navigator.pop(dialogContext);
                                    return;
                                  }
                                  final text = editors[currentIndex]!.text.trim();
                                  if (text.isEmpty || text.length > 3000) {
                                    setDialogState(() => saveError = text.isEmpty
                                        ? '메모 내용을 입력해 주세요.' : '메모는 3,000자까지 입력할 수 있어요.');
                                    return;
                                  }
                                  setDialogState(() { saving = true; saveError = null; });
                                  try {
                                    await _updateReaderNote(item.editableNoteId!, memo: text);
                                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                                  } catch (e) {
                                    if (dialogContext.mounted) setDialogState(() {
                                      saving = false;
                                      saveError = '메모 저장 실패: $e';
                                    });
                                  }
                                },
                                child: Text(
                                  item.editableNoteId == null ? '완료' : (saving ? '저장 중' : '저장'),
                                  style: TextStyle(
                                    color: Color(0xFF1E88E5),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),

                      // 메모를 남긴 선택 문장
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                color: item.color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: item.color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.quote,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF555555),
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 작성자
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Text(
                          item.author,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF555555),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      // 기존 회색 메모 내용 박스
                      Container(
                        height: 280,
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: item.editableNoteId != null
                            ? TextField(
                          key: ValueKey('edit-$currentIndex'),
                          controller: editors[currentIndex],
                          enabled: !saving,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(fontSize: 15, height: 1.7),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        )
                            : SingleChildScrollView(
                          key: ValueKey(currentIndex),
                          child: SelectableText(
                            item.content,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.7,
                            ),
                          ),
                        ),
                      ),

                      if (saveError != null && item.editableNoteId != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Text(saveError!, style: const TextStyle(color: Colors.red)),
                        ),
                      // 여러 메모일 때만 이동 버튼 표시
                      if (items.length > 1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: '이전 메모',
                                onPressed: !saving && currentIndex > 0
                                    ? () {
                                  setDialogState(() {
                                    currentIndex--;
                                    saveError = null;
                                  });
                                }
                                    : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Text(
                                '${currentIndex + 1} / ${items.length}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF555555),
                                ),
                              ),
                              IconButton(
                                tooltip: '다음 메모',
                                onPressed: !saving && currentIndex < items.length - 1
                                    ? () {
                                  setDialogState(() {
                                    currentIndex++;
                                    saveError = null;
                                  });
                                }
                                    : null,
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    return true;
  }

  Future<void> _openHighlightMenu(ReadingNote note) async {
    _annotationTapHandled = true;
    if (!mounted) return;

    final opened = await _showAllMatchingMemos(
      note.paragraphOrder,
      startOffset: note.startOffset,
      endOffset: note.endOffset,
    );

    if (opened || !mounted) return;

    final viewModel = context.read<BookViewModel>();

    // 클릭한 형광펜과 같은 범위에 저장된 내 메모 찾기
    final matchingMemos = viewModel.readingNotes.where(
          (memo) =>
      memo.type == ReaderNoteType.memo &&
          memo.paragraphOrder == note.paragraphOrder &&
          memo.startOffset == note.startOffset &&
          memo.endOffset == note.endOffset,
    ).toList();

    final privateMemoTap = !widget.readerContext.isReadingRoom &&
        !note.readOnly &&
        (note.id > 0 ||
            (note.id <= -2000000000 && note.id > -3000000000));
    if (privateMemoTap && matchingMemos.isNotEmpty) {
      ReadingNote? selectedMemo;

      if (matchingMemos.length == 1) {
        selectedMemo = matchingMemos.single;
      } else {
        selectedMemo = await showDialog<ReadingNote>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('메모 ${matchingMemos.length}개'),
            content: SizedBox(
              width: 420,
              height: 300,
              child: ListView.separated(
                itemCount: matchingMemos.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (_, index) {
                  final memo = matchingMemos[index];

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('메모 ${index + 1}'),
                    subtitle: Text(
                      memo.memoContent ?? '메모 내용이 없습니다.',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(dialogContext, memo);
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('닫기'),
              ),
            ],
          ),
        );
      }

      if (!mounted || selectedMemo == null) return;

      final memo = selectedMemo;

      await showDialog<bool>(
        context: context,
        builder: (_) => _MemoEditorDialog(
          selectedText: memo.selectedText,
          initialMemo: memo.memoContent ?? '',
          onSave: (text) => viewModel.updateNote(
            widget.bookId,
            memo.id,
            memo: text,
          ),
        ),
      );

      return;
    }
    // AI 친구 형광펜: 메모 내용을 읽기 전용으로 보여준다.
    if (note.id <= -1000000000) {
      String friendName = 'AI 친구';
      int? friendId;
      final aiNoteId = -1000000000 - note.id;

      for (final entry in _aiNotesByFriend.entries) {
        if (entry.value.any((aiNote) => aiNote.id == aiNoteId)) {
          friendName = _friendName(entry.key);
          friendId = entry.key;
          break;
        }
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Text(
                        '메모',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Positioned(
                        left: 8,
                        child: TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text(
                            '닫기',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        child: TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text(
                            '완료',
                            style: TextStyle(
                              color: Color(0xFF1E88E5),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          color: _highlightColor(
                            friendId == null
                                ? note.highlightColor
                                : (_aiFriendHighlightColors[friendId] ?? '#FFF59D'),
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF90CAF9),
                            width: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          note.selectedText ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF555555),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 280,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      note.preview.isNotEmpty
                          ? note.preview
                          : 'AI 메모 내용이 없습니다.',
                      style: const TextStyle(fontSize: 15, height: 1.7),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      );

      return;
    }
    // Shared room highlights keep their server id encoded as a negative local
    // id.  They deliberately never enter the private edit menu.  Showing an
    // explicit read-only sheet makes that distinction visible to readers.
    if (note.readOnly || note.id < 0) {
      await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '공유 형광펜',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Text(
                  note.selectedText?.isNotEmpty == true
                      ? '“${note.selectedText}”'
                      : '공유된 형광펜입니다.',
                  style: const TextStyle(height: 1.5),
                ),
                const SizedBox(height: 12),
                const Text(
                  '공유 형광펜은 읽기 전용입니다. 수정·삭제는 개인 형광펜에서만 할 수 있습니다.',
                  style: TextStyle(color: Color(0xFF666666), height: 1.45),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('닫기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    // 내가 작성한 메모는 형광펜 메뉴 대신 메모 창을 바로 열기
    if (!note.readOnly && !widget.readerContext.isReadingRoom && note.id > 0 && note.type == ReaderNoteType.memo) {
      if (!mounted) return;

      final viewModel = context.read<BookViewModel>();

      await showDialog<bool>(
        context: context,
        builder: (_) => _MemoEditorDialog(
          selectedText: note.selectedText,
          initialMemo: note.memoContent ?? '',
          onSave: (memo) => viewModel.updateNote(
            widget.bookId,
            note.id,
            memo: memo,
          ),
        ),
      );

      return;
    }
    if (!mounted || note.id == 0) return;
    final screen = MediaQuery.sizeOf(context);
    final tap = _highlightTapPosition ?? Offset(screen.width / 2, screen.height / 2);
    const menuWidth = 220.0;
    final left = (tap.dx - menuWidth / 2).clamp(12.0, screen.width - menuWidth - 12);
    final above = tap.dy > MediaQuery.paddingOf(context).top + 80;
    final top = (above ? tap.dy - 66 : tap.dy + 20)
        .clamp(MediaQuery.paddingOf(context).top + 8, screen.height - 80.0);
    final action = await showGeneralDialog<_HighlightAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '형광펜 메뉴 닫기',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (menuContext, _, __) => Stack(children: [
        Positioned(left: left, top: top, width: menuWidth,
          child: Material(
            color: const Color(0xFFF7F7F7),
            elevation: 8,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(height: 48, child: IntrinsicHeight(child: Row(children: [
              Expanded(child: TextButton(
                onPressed: () => Navigator.pop(menuContext, _HighlightAction.delete),
                child: const Text('삭제', style: TextStyle(color: Colors.black87)),
              )),
              const VerticalDivider(width: 1),
              Expanded(child: IconButton(
                tooltip: '색상 변경',
                onPressed: () => Navigator.pop(menuContext, _HighlightAction.color),
                icon: Container(width: 22, height: 22,
                    decoration: BoxDecoration(color: _highlightColor(note.highlightColor).withAlpha(255),
                        shape: BoxShape.circle, border: Border.all(color: Colors.black12))),
              )),
              const VerticalDivider(width: 1),
              Expanded(child: TextButton(
                onPressed: () => Navigator.pop(menuContext, _HighlightAction.memo),
                child: const Text('메모', style: TextStyle(color: Colors.black87)),
              )),
            ]))),
          ),
        ),
      ]),
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
        await _deleteReaderNote(note.id);
      } on ApiException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
      }
      return;
    }

    if (action == _HighlightAction.color) {
      const palette = ['#FFF59D', '#F8BBD0', '#A5D6A7', '#90CAF9', '#CE93D8',
        '#FFCC80', '#EF9A9A', '#80CBC4', '#B3E5FC', '#BDBDBD'];
      final color = await showDialog<String>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (dialogContext) => AlertDialog(
          title: const Text('색상 변경'),
          content: SizedBox(width: 300, child: Wrap(spacing: 12, runSpacing: 16,
            children: palette.map((value) => InkWell(
              onTap: () => Navigator.pop(dialogContext, value),
              borderRadius: BorderRadius.circular(24),
              child: Container(width: 44, height: 44,
                decoration: BoxDecoration(color: _highlightColor(value).withAlpha(255),
                    shape: BoxShape.circle, border: Border.all(color: Colors.black26)),
                child: _highlightColor(note.highlightColor) == _highlightColor(value)
                    ? const Icon(Icons.check, size: 22) : null,
              ),
            )).toList(),
          )),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'))],
        ),
      );
      if (!mounted || color == null) return;
      try {
        await _updateReaderNote(note.id, color: color);
      } on ApiException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
      }
      return;
    }

    final start = note.startOffset;
    final end = note.endOffset;
    final text = note.selectedText;
    if (start == null || end == null || text == null || end <= start) return;
    await _saveSelectionMemo(
      _TextSelection(note.paragraphOrder, start, end, text),
      color: note.highlightColor,
    );
  }

  List<NoteRange> _rangeBetween(NoteRange first, NoteRange last) {
    final paragraphs = context.read<BookViewModel>().content?.paragraphs ?? const <BookParagraph>[];
    final startIndex = paragraphs.indexWhere((p) => p.order == first.paragraphOrder);
    final endIndex = paragraphs.indexWhere((p) => p.order == last.paragraphOrder);
    if (startIndex < 0 || endIndex < startIndex) return const [];
    return [
      for (var index = startIndex; index <= endIndex; index++)
        NoteRange(paragraphs[index].order,
            index == startIndex ? first.startOffset : 0,
            index == endIndex ? last.endOffset : paragraphs[index].text.length),
    ];
  }

  _TextSelection? _currentRange() {
    if (_activeSelection.isEmpty) return null;
    final selections = _activeSelection.values.toList()
      ..sort((a, b) => a.paragraphOrder != b.paragraphOrder
          ? a.paragraphOrder.compareTo(b.paragraphOrder) : a.start.compareTo(b.start));
    final first = selections.first;
    final last = selections.last;
    final beginning = NoteRange(first.paragraphOrder, first.start, first.end);
    final ending = NoteRange(last.paragraphOrder, last.start, last.end);
    final ranges = _rangeBetween(beginning, ending);
    if (ranges.isEmpty) return null;
    final paragraphs = context.read<BookViewModel>().content!.paragraphs;
    final byOrder = {for (final p in paragraphs) p.order: p.text};
    final text = ranges.map((r) => byOrder[r.paragraphOrder]!.substring(r.startOffset, r.endOffset)).join('\n\n');
    if (text.isEmpty) return null;
    return _TextSelection(ranges.first.paragraphOrder, ranges.first.startOffset,
        ranges.first.endOffset, text, ranges: ranges);
  }

  void _clearContinuedSelection() {
    _pageTapTimer?.cancel();
    final region = _currentSelectionRegion;
    if (region != null && region.mounted) { region.hideToolbar(); region.clearSelection(); }
    setState(() {
      _activeSelection.clear();
      _continuedStart = null;
      _continuedEnd = null;
      _continuingSelection = false;
      _autoSelectContinuedPage = false;
      _continuedTargetOrder = null;
    });
  }

  Widget _selectionToolbar(int pageIndex, SelectableRegionState region) {
    _currentSelectionRegion = region;
    final selection = _currentRange();
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: region.contextMenuAnchors,
      buttonItems: [
        if (selection != null) ContextMenuButtonItem(
          label: '형광펜', onPressed: () {
          region.hideToolbar(); region.clearSelection();
          _saveHighlight(selection);
        },
        ),
        if (selection != null) ContextMenuButtonItem(
          label: '메모', onPressed: () {
          region.hideToolbar(); region.clearSelection();
          _saveSelectionMemo(selection);
        },
        ),
      ],
    );
  }

  List<ReadingNote> _memoFragments(ReadingNote note) {
    if (note.ranges.isEmpty) return [note];
    return [for (final r in note.ranges) ReadingNote(
      id: note.id, type: note.type, paragraphOrder: r.paragraphOrder,
      memoContent: note.memoContent, selectedText: note.selectedText,
      startOffset: r.startOffset, endOffset: r.endOffset,
      highlightColor: note.highlightColor, linkedHighlightId: note.linkedHighlightId,
      preview: note.preview, createdAt: note.createdAt, updatedAt: note.updatedAt,
      ranges: note.ranges,
    )];
  }

  List<SharedRoomNote> _sharedMemoFragments(SharedRoomNote note) {
    if (note.ranges.isEmpty) return [note];
    return [for (final r in note.ranges) SharedRoomNote(
      id: note.id, userId: note.userId, nickname: note.nickname,
      profileImageUrl: note.profileImageUrl, type: note.type,
      paragraphOrder: r.paragraphOrder, startOffset: r.startOffset, endOffset: r.endOffset,
      selectedText: note.selectedText, content: note.content,
      highlightColor: note.highlightColor, isSpoilerLocked: note.isSpoilerLocked,
      commentCount: note.commentCount, mine: note.mine, canDelete: note.canDelete,
      version: note.version, explicitlyRevealed: note.explicitlyRevealed, createdAt: note.createdAt,
      ranges: note.ranges,
    )];
  }

  Future<void> _saveHighlight(_TextSelection selection) async {
    if (selection.start < 0 ||
        selection.end <= selection.start ||
        selection.selectedText.trim().isEmpty)
      return;
    if (_savingHighlight) return;
    if (selection.selectedText.length > 30000 || selection.ranges.length > 200) {
      _aiMessage('선택 범위가 너무 깁니다. 30,000자 또는 200문단 이내로 선택해 주세요.');
      return;
    }
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
          ranges: selection.ranges,
          color: highlightColor,
        );
      }
      if (mounted) _clearContinuedSelection();
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

  Future<void> _saveSelectionMemo(_TextSelection selection, {String? color}) async {
    if (selection.start < 0 ||
        selection.end <= selection.start ||
        selection.selectedText.trim().isEmpty)
      return;
    if (selection.selectedText.length > 30000 || selection.ranges.length > 200) {
      _aiMessage('선택 범위가 너무 깁니다. 30,000자 또는 200문단 이내로 선택해 주세요.');
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MemoEditorDialog(
        selectedText: selection.selectedText,
        onSave: (memo) async {
          if (widget.readerContext.isReadingRoom) {
            await _createRoomNote(selection, type: 'MEMO', content: memo,
                highlightColor: color ?? context.read<BookViewModel>().readerSettings.highlightColor);
          } else {
            await context.read<BookViewModel>().addNote(
              widget.bookId,
              ReaderNoteType.memo,
              selection.paragraphOrder,
              memo: memo,
              selectedText: selection.selectedText,
              startOffset: selection.start,
              endOffset: selection.end,
              ranges: selection.ranges,
            );
          }
        },
      ),
    );
    if (saved == true && mounted) _clearContinuedSelection();
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
      if (selection.ranges.isNotEmpty) 'ranges': selection.ranges.map((r) => r.toJson()).toList(),
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
      BuildContext anchorContext, {
        int? noteId,
      }) async {
    _annotationTapHandled = true;
    if (!mounted) return;

    int? start;
    int? end;

    if (noteId != null) {
      if (widget.readerContext.isReadingRoom) {
        for (final note in _sharedMemos) {
          if (note.id == noteId &&
              (note.paragraphOrder == paragraphOrder || note.ranges.any((r) => r.paragraphOrder == paragraphOrder))) {
            if (note.isSpoilerLocked) return;
            final ranges = note.ranges.where((r) => r.paragraphOrder == paragraphOrder);
            start = ranges.isEmpty ? note.startOffset : ranges.first.startOffset;
            end = ranges.isEmpty ? note.endOffset : ranges.first.endOffset;
            break;
          }
        }
      } else {
        for (final note in context.read<BookViewModel>().readingNotes) {
          if (note.id == noteId &&
              note.type == ReaderNoteType.memo &&
              (note.paragraphOrder == paragraphOrder || note.ranges.any((r) => r.paragraphOrder == paragraphOrder))) {
            final ranges = note.ranges.where((r) => r.paragraphOrder == paragraphOrder);
            start = ranges.isEmpty ? note.startOffset : ranges.first.startOffset;
            end = ranges.isEmpty ? note.endOffset : ranges.first.endOffset;
            break;
          }
        }
      }
    }

    await _showAllMatchingMemos(
      paragraphOrder,
      startOffset: start,
      endOffset: end,
    );
  }

  Future<void> _showSharedParagraphMemos(
      int paragraphOrder,
      BuildContext anchorContext, {
        int? noteId,
      }) async {
    final paragraphMemos = _sharedMemos
        .where((note) => note.paragraphOrder == paragraphOrder)
        .toList();

    final clickedIndex = noteId == null
        ? -1
        : paragraphMemos.indexWhere((note) => note.id == noteId);

    final List<SharedRoomNote> notes;

    if (noteId == null) {
      notes = paragraphMemos;
    } else if (clickedIndex < 0) {
      return;
    } else {
      final clickedMemo = paragraphMemos[clickedIndex];

      notes = paragraphMemos.where((note) {
        return note.startOffset == clickedMemo.startOffset &&
            note.endOffset == clickedMemo.endOffset;
      }).toList();
    }
    if (!mounted || notes.isEmpty) return;
    final position = _memoPopupPosition(anchorContext);
    if (position == null) return;
    final selected = notes.length == 1
        ? notes.single
        : await showMenu<SharedRoomNote>(
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
                Text(
                  selected.nickname,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(detail),
              ],
            ),
          ),
        ),
      ],
    );
  }

  RelativeRect? _memoPopupPosition(BuildContext anchorContext) {
    final anchor = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
    Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchor == null || overlay == null || !anchor.attached) return null;
    final topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    return RelativeRect.fromRect(
      topLeft & anchor.size,
      Offset.zero & overlay.size,
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

String _bookmarkChapterTitle(List<ReaderChapter> chapters, int order) {
  final candidates = chapters.where((chapter) => chapter.startParagraphOrder <= order).toList()
    ..sort((a, b) => a.startParagraphOrder.compareTo(b.startParagraphOrder));
  if (candidates.isEmpty) return '목차 정보 없음';
  final chapter = candidates.last;
  final title = chapter.title.trim();
  if (title.isEmpty) return '제 ${chapter.number}장';
  return RegExp(r'^(제\s*)?\d+\s*장').hasMatch(title)
      ? title : '제 ${chapter.number}장 : $title';
}

String _bookmarkDate(DateTime? value) {
  final date = value?.toLocal();
  return date == null ? '' : '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}.';
}

class _BookmarkNoteTile extends StatelessWidget {
  const _BookmarkNoteTile({required this.title, required this.location,
    required this.date, required this.onTap, this.onDelete, this.busy = false});
  final String title, location, date;
  final VoidCallback? onTap, onDelete;
  final bool busy;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.bookmark, size: 20, color: Color(0xFFD94A45)),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15, height: 1.5))),
        ]),
        Padding(padding: const EdgeInsets.only(left: 32), child: Row(children: [
          Expanded(child: Text(date.isEmpty ? location : '$location  |  $date',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)))),
          if (onDelete != null) PopupMenuButton<String>(
            tooltip: '책갈피 메뉴', enabled: !busy,
            icon: const Icon(Icons.more_horiz, color: Color(0xFF9E9E9E)),
            onSelected: (action) { if (action == 'delete') onDelete!(); },
            itemBuilder: (_) => const [PopupMenuItem<String>(value: 'delete',
                child: Text('삭제', style: TextStyle(color: Colors.red)))],
          ),
        ])),
      ]),
    ),
  );
}

Color _highlightColor(String? value) {
  final color = value?.trim().toUpperCase();

  return switch (color) {
    'PEACH' || '#FFCCBC' => const Color(0x88FFCCBC),
    'PINK' || '#F8BBD0' => const Color(0x88F8BBD0),
    'GREEN' || '#A5D6A7' => const Color(0x88A5D6A7),
    'BLUE' || '#90CAF9' => const Color(0x8890CAF9),
    'PURPLE' || '#CE93D8' => const Color(0x88CE93D8),
    'ORANGE' || '#FFCC80' || '#FFAB40' => const Color(0x88FFCC80),
    'RED' || '#EF9A9A' => const Color(0x88EF9A9A),
    'MINT' || '#80CBC4' => const Color(0x8880CBC4),
    'SKY' || '#B3E5FC' => const Color(0x88B3E5FC),
    'GRAY' || '#BDBDBD' => const Color(0x88BDBDBD),
    _ => const Color(0x88FFF59D),
  };
}

// Hide only highlight entries represented by a memo in the All tab.
bool _memoCoversHighlight(int order, int? start, int? end,
    int memoOrder, int? memoStart, int? memoEnd, List<NoteRange> ranges) {
  if (start == null || end == null) return false;
  if (ranges.isNotEmpty) {
    return ranges.any((range) => range.paragraphOrder == order &&
        range.startOffset <= start && range.endOffset >= end);
  }
  return order == memoOrder && memoStart != null && memoEnd != null &&
      memoStart <= start && memoEnd >= end;
}

bool _isUnreadChapter(int noteOrder, int readOrder, List<ReaderChapter> chapters) {
  if (chapters.isEmpty) return noteOrder > readOrder;
  final noteChapter = chapters.lastIndexWhere((c) => c.startParagraphOrder <= noteOrder);
  final readChapter = chapters.lastIndexWhere((c) => c.startParagraphOrder <= readOrder);
  return noteChapter > readChapter;
}

enum _HighlightAction { delete, color, memo }

class _ReaderPage extends StatelessWidget {
  const _ReaderPage({
    required this.selectionKey,
    required this.onSelection,
    required this.selectionToolbar,
    required this.continuedRanges,
    required this.page,
    required this.settings,
    required this.twoColumns,
    required this.highlights,
    required this.onHighlight,
    required this.onHighlightTap,
    required this.memos,
    required this.roomMemoCounts,
    required this.additionalMemoRanges,
    required this.onMemo,
    required this.onShowMemos,
  });
  final GlobalKey<SelectionAreaState> selectionKey;
  final void Function(String key, _TextSelection? selection) onSelection;
  final Widget Function(BuildContext, SelectableRegionState) selectionToolbar;
  final List<NoteRange> continuedRanges;
  final _Page page;
  final ReaderSettings settings;
  final bool twoColumns;
  final List<ReadingNote> highlights;
  final ValueChanged<_TextSelection> onHighlight;
  final ValueChanged<ReadingNote> onHighlightTap;
  final List<ReadingNote> memos;
  final Map<int, int> roomMemoCounts;
  final List<_MemoRange> additionalMemoRanges;
  final ValueChanged<_TextSelection> onMemo;
  final void Function(
      int paragraphOrder,
      BuildContext anchorContext, {
      int? noteId,
      })
  onShowMemos;

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
    Widget textColumn(List<_Slice> list) => _ReaderSelectionColumn(
      children: list
          .map(
            (s) => _SelectableParagraphSlice(
          key: ValueKey('${s.order}:${s.start}'),
          onSelection: (value) => onSelection('${s.order}:${s.start}', value),
          continuedRanges: continuedRanges.where((r) => r.paragraphOrder == s.order).toList(),
          slice: s,
          style: style,
          highlights: highlights
              .where((n) => n.paragraphOrder == s.order)
              .toList(),
          onHighlight: onHighlight,
          onHighlightTap: onHighlightTap,
          memos: memos.where((n) => n.paragraphOrder == s.order).toList(),
          roomMemoCount: roomMemoCounts[s.order] ?? 0,
          additionalMemoRanges: additionalMemoRanges
              .where((memo) => memo.paragraphOrder == s.order)
              .toList(),
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
    return SelectionArea(
      key: selectionKey,
      contextMenuBuilder: selectionToolbar,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          twoColumns ? 34 : 30,
          110,
          twoColumns ? 34 : 30,
          150,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              primary: false,
              physics: const ClampingScrollPhysics(),
              clipBehavior: Clip.none,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    content,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReaderSelectionColumn extends StatefulWidget {
  const _ReaderSelectionColumn({required this.children});
  final List<Widget> children;
  @override
  State<_ReaderSelectionColumn> createState() => _ReaderSelectionColumnState();
}

class _ReaderSelectionColumnState extends State<_ReaderSelectionColumn> {
  final SelectionListenerNotifier _notifier = SelectionListenerNotifier();
  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => SelectionListener(
    selectionNotifier: _notifier,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.children,
    ),
  );
}

class _MemoRange {
  const _MemoRange(
      this.paragraphOrder,
      this.startOffset,
      this.endOffset, {
        this.noteId,
      });
  final int paragraphOrder;
  final int? startOffset;
  final int endOffset;
  final int? noteId;
}

class _MemoIconAnchor {
  const _MemoIconAnchor(this.position, this.noteId);
  final Offset position;
  final int? noteId;
}

class _TextSelection {
  const _TextSelection(
      this.paragraphOrder,
      this.start,
      this.end,
      this.selectedText, {
        this.ranges = const [],
      });
  final List<NoteRange> ranges;
  final int paragraphOrder;
  final int start;
  final int end;
  final String selectedText;
}

class _SelectableParagraphSlice extends StatefulWidget {
  const _SelectableParagraphSlice({
    super.key,
    required this.onSelection,
    required this.continuedRanges,
    required this.slice,
    required this.style,
    required this.highlights,
    required this.onHighlight,
    required this.onHighlightTap,
    required this.memos,
    required this.roomMemoCount,
    required this.additionalMemoRanges,
    required this.onMemo,
    required this.onShowMemos,
  });
  final ValueChanged<_TextSelection?> onSelection;
  final List<NoteRange> continuedRanges;
  final _Slice slice;
  final TextStyle style;
  final List<ReadingNote> highlights;
  final ValueChanged<_TextSelection> onHighlight;
  final ValueChanged<ReadingNote> onHighlightTap;
  final List<ReadingNote> memos;
  final int roomMemoCount;
  final List<_MemoRange> additionalMemoRanges;
  final ValueChanged<_TextSelection> onMemo;
  final void Function(
      int paragraphOrder,
      BuildContext anchorContext, {
      int? noteId,
      })
  onShowMemos;

  @override
  State<_SelectableParagraphSlice> createState() =>
      _SelectableParagraphSliceState();
}

class _SelectableParagraphSliceState extends State<_SelectableParagraphSlice> {
  final GlobalKey _selectableTextKey = GlobalKey();
  final SelectionListenerNotifier _selectionNotifier = SelectionListenerNotifier();

  @override
  void initState() {
    super.initState();
    _selectionNotifier.addListener(_reportSelection);
  }

  void _reportSelection() {
    if (!_selectionNotifier.registered || !mounted) return;
    final range = _selectionNotifier.selection.range;
    final slice = widget.slice;
    if (range == null || range.endOffset <= range.startOffset) {
      widget.onSelection(null);
      return;
    }
    final start = range.startOffset.clamp(0, slice.text.length).toInt();
    final end = range.endOffset.clamp(0, slice.text.length).toInt();
    widget.onSelection(end <= start ? null : _TextSelection(slice.order,
        slice.start + start, slice.start + end, slice.text.substring(start, end)));
  }
  final GlobalKey _textStackKey = GlobalKey();
  List<_MemoIconAnchor> _memoIconPositions = const [];

  // 실제 화면의 SelectableText가 사용하는 RenderEditable에서 위치를 얻는다.
  void _updateMemoIconPositions(Map<int, int?> ends, int textLength) {
    if (!mounted) return;
    final textContext = _selectableTextKey.currentContext;
    final stackContext = _textStackKey.currentContext;
    if (textContext == null || stackContext == null) return;
    final stackBox = stackContext.findRenderObject();
    if (stackBox is! RenderBox || !stackBox.hasSize) return;

    RenderParagraph? editable;
    void visit(Element element) {
      if (editable != null) return;
      if (element is RenderObjectElement &&
          element.renderObject is RenderParagraph) {
        editable = element.renderObject as RenderParagraph;
        return;
      }
      element.visitChildren(visit);
    }

    (textContext as Element).visitChildren(visit);
    final renderEditable = editable;
    if (renderEditable == null || !renderEditable.hasSize) return;

    final next = <_MemoIconAnchor>[];
    for (final entry in ends.entries) {
      final end = entry.key;
      if (end <= 0 || end > textLength) continue;
      final boxes = renderEditable.getBoxesForSelection(
        TextSelection(baseOffset: end - 1, extentOffset: end),
      );
      if (boxes.isEmpty) continue;
      final last = boxes.last;
      final global = renderEditable.localToGlobal(
        Offset(last.right, last.bottom),
      );
      final local = stackBox.globalToLocal(global);

      next.add(
        _MemoIconAnchor(
          Offset(local.dx + 1, local.dy - 2),
          entry.value,
        ),
      );
    }
    if (next.length == _memoIconPositions.length &&
        List.generate(
          next.length,
              (i) =>
          next[i].position == _memoIconPositions[i].position &&
              next[i].noteId == _memoIconPositions[i].noteId,
        ).every((same) => same))
      return;
    setState(() => _memoIconPositions = next);
  }

  final Map<int, TapGestureRecognizer> _highlightRecognizers = {};

  TapGestureRecognizer _recognizerFor(ReadingNote note) {
    final recognizer = _highlightRecognizers.putIfAbsent(
      note.id,
      TapGestureRecognizer.new,
    );
    recognizer.onTap = () {
      if (note.id <= -3000000000) {
        widget.onShowMemos(
          note.paragraphOrder,
          context,
          noteId: -3000000000 - note.id,
        );
      } else {
        widget.onHighlightTap(note);
      }
    };
    return recognizer;
  }

  @override
  void dispose() {
    _selectionNotifier.removeListener(_reportSelection);
    _selectionNotifier.dispose();
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
    final spans = <InlineSpan>[];

    // 메모를 남길 때의 선택 범위와 같은 형광펜만 연결한다.
    // 서로 닿거나 겹치는 별개의 형광펜은 합치지 않는다.
    final memoRanges = <_MemoRange>[
      ...widget.additionalMemoRanges,
      ...memos
          .where((m) => m.endOffset != null)
          .map(
            (m) => _MemoRange(
          m.paragraphOrder,
          m.startOffset,
          m.endOffset!,
          noteId: m.id,
        ),
      ),
    ];
    final anchoredMemoEnds = <int, Set<int?>>{};
    for (final memo in memoRanges) {
      var end = memo.endOffset;
      if (memo.startOffset != null) {
        for (final highlight in highlights) {
          if (highlight.startOffset == memo.startOffset &&
              highlight.endOffset == memo.endOffset) {
            end = highlight.endOffset!;
            break;
          }
        }
      }
      if (end > slice.start && end <= slice.start + slice.text.length) {
        anchoredMemoEnds
            .putIfAbsent(end - slice.start, () => <int?>{})
            .add(memo.noteId);
      }
    }

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
    for (final range in widget.continuedRanges) {
      points.add((range.startOffset - slice.start).clamp(0, slice.text.length).toInt());
      points.add((range.endOffset - slice.start).clamp(0, slice.text.length).toInt());
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
      // 겹치는 형광펜 색상 혼합
      final coveredNotes = covered.toList();
      Color? mixedColor;

      if (coveredNotes.length == 1) {
        mixedColor = _highlightColor(coveredNotes.first.highlightColor);
      } else if (coveredNotes.length > 1) {
        final colors = coveredNotes
            .map((note) => _highlightColor(note.highlightColor))
            .toList();

        final red = colors.map((c) => (c.r * 255).round()).reduce((a, b) => a + b) ~/ colors.length;
        final green = colors.map((c) => (c.g * 255).round()).reduce((a, b) => a + b) ~/ colors.length;
        final blue = colors.map((c) => (c.b * 255).round()).reduce((a, b) => a + b) ~/ colors.length;

        mixedColor = Color.fromARGB(136, red, green, blue);
      }

      final continued = widget.continuedRanges.any((r) =>
      r.startOffset <= slice.start + from && r.endOffset >= slice.start + to);
      spans.add(
        TextSpan(
          text: slice.text.substring(from, to),
          recognizer: highlight == null ? null : _recognizerFor(highlight),
          style: continued ? style.copyWith(backgroundColor: const Color(0x806694E8))
              : mixedColor == null ? style : style.copyWith(backgroundColor: mixedColor),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final memoEnds = <int, int?>{
          for (final entry in anchoredMemoEnds.entries)
            entry.key: entry.value.length == 1 ? entry.value.single : null,
        };
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateMemoIconPositions(memoEnds, slice.text.length);
        });
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Stack(
            key: _textStackKey,
            clipBehavior: Clip.none,
            children: [
              SelectionListener(
                selectionNotifier: _selectionNotifier,
                child: Text.rich(
                  TextSpan(children: spans),
                  key: _selectableTextKey,
                  style: style,
                  selectionColor: const Color(0x806694E8),
                ),
              ),
              for (final position in _memoIconPositions)
                Positioned(
                  left: position.position.dx,
                  top: position.position.dy,
                  child: _MemoBadge(
                    count: memoCount,
                    onTap: (anchorContext) => widget.onShowMemos(
                      slice.order,
                      anchorContext,
                      noteId: position.noteId,
                    ),
                  ),
                ),
              if (memoCount > 0 && memoRanges.isEmpty && _memoIconPositions.isEmpty)
                Positioned(
                  right: 0,
                  top: 0,
                  child: _MemoBadge(
                    count: memoCount,
                    onTap: (anchorContext) => widget.onShowMemos(
                      slice.order,
                      anchorContext,
                      noteId: null,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
        padding: EdgeInsets.zero,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(
              Icons.mode_comment_outlined,
              size: 10,
              color: Color(0xff8d6e63),
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

class _SharedRoomNotesTab extends StatefulWidget {
  const _SharedRoomNotesTab({
    this.targetNoteId,
    required this.roomId,
    required this.bookId,
    required this.type,
    required this.onGo,
    required this.pageOf,
    required this.currentPage,
    required this.cachedNotes,
    required this.onRefresh,
    required this.onOpenComments,
  });

  final int? targetNoteId;
  final int roomId;
  final int bookId;
  final String? type;
  final void Function(int order, [int? offset]) onGo;
  final int? Function(int order, int? offset) pageOf;
  final int currentPage;
  final List<SharedRoomNote> cachedNotes;
  final VoidCallback onRefresh;
  final ValueChanged<SharedRoomNote> onOpenComments;

  @override
  State<_SharedRoomNotesTab> createState() => _SharedRoomNotesTabState();
}

class _SharedRoomNotesTabState extends State<_SharedRoomNotesTab> {
  bool _canChangeHighlightColor(SharedRoomNote note) =>
      note.mine && note.type == 'HIGHLIGHT' &&
          !widget.cachedNotes.any((memo) => memo.type == 'MEMO' && memo.userId == note.userId &&
              _memoCoversHighlight(note.paragraphOrder,note.startOffset,note.endOffset,
                  memo.paragraphOrder,memo.startOffset,memo.endOffset,memo.ranges));
  void _reload() => widget.onRefresh();

  Future<void> _delete(SharedRoomNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('공유 독서노트 삭제'),
        content: const Text('이 독서노트를 삭제할까요?'),
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
      final token = context.read<RidiStore>().accessToken;
      await ReadingRoomRepository(
        ApiClient(tokenProvider: () => token),
      ).deleteSharedNote(widget.roomId, note.id);
      if (mounted) setState(_reload);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  ReadingRoomRepository get _repository => ReadingRoomRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken));

  Future<void> _action(SharedRoomNote note, String action) async {
    if (note.isSpoilerLocked) return;
    if (action == 'delete') {
      if (note.canDelete) await _delete(note);
      return;
    }
    if (!note.mine) return;
    if (action == 'color' && !_canChangeHighlightColor(note)) return;
    if (action == 'edit') {
      await showDialog<bool>(context: context, builder: (_) => _MemoEditorDialog(
        selectedText: note.selectedText, initialMemo: note.content ?? '',
        onSave: (text) async {
          await _repository.updateSharedNote(widget.roomId, note.id, {'content': text});
        },
      ));
      if (mounted) setState(_reload);
      return;
    }
    const colors = ['#FFF59D','#F8BBD0','#A5D6A7','#90CAF9','#CE93D8',
      '#FFCC80','#EF9A9A','#80CBC4','#B3E5FC','#BDBDBD'];
    final color = await showDialog<String>(context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => AlertDialog(
        title: const Text('색상 변경'),
        content: SizedBox(width: 300, child: Wrap(spacing: 12, runSpacing: 16,
          children: colors.map((value) => InkWell(
            onTap: () => Navigator.pop(dialogContext, value),
            child: Container(width: 44, height: 44,
              decoration: BoxDecoration(color: _highlightColor(value).withAlpha(255),
                  shape: BoxShape.circle, border: Border.all(color: Colors.black26)),
              child: _highlightColor(note.highlightColor) == _highlightColor(value)
                  ? const Icon(Icons.check, size: 22) : null,
            ),
          )).toList(),
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소'))],
      ),
    );
    if (color == null || !mounted) return;
    try {
      await _repository.updateSharedNote(widget.roomId, note.id, {'highlightColor': color});
      if (mounted) setState(_reload);
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('색상 변경 실패: $e')));
    }
  }

  Widget _recordCard(SharedRoomNote note) {
    final page = widget.pageOf(note.paragraphOrder, note.startOffset);
    if (note.type == 'BOOKMARK') {
      return _BookmarkNoteTile(
        title: _bookmarkChapterTitle(context.read<BookViewModel>().readerChapters, note.paragraphOrder),
        location: page == null ? '페이지 확인 불가' : '$page 페이지',
        date: _bookmarkDate(note.createdAt),
        onTap: () => widget.onGo(note.paragraphOrder, note.startOffset),
        onDelete: note.mine ? () => _action(note, 'delete') : null,
      );
    }
    final date = note.createdAt?.toLocal();
    final location = page == null ? '페이지 확인 불가' : '$page 페이지';
    final dateText = date == null ? '' : '  |  ${date.year}.${date.month.toString().padLeft(2,'0')}.${date.day.toString().padLeft(2,'0')}.';
    final chapters = context.read<BookViewModel>().readerChapters;
    final chapterIndex = chapters.lastIndexWhere((c) => c.startParagraphOrder <= note.paragraphOrder);
    final title = note.type == 'BOOKMARK'
        ? (chapterIndex < 0 ? '책갈피' : chapters[chapterIndex].title)
        : (note.selectedText ?? '형광펜');
    return InkWell(
        onTap: note.isSpoilerLocked ? null : () => widget.onGo(note.paragraphOrder, note.startOffset),
        child: Padding(padding: const EdgeInsets.fromLTRB(20,16,12,8), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(onTap: note.isSpoilerLocked ? null : () => widget.onGo(note.paragraphOrder, note.startOffset),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (note.type == 'BOOKMARK') const Icon(Icons.bookmark_outline, size: 20)
                else Container(width: 12,height: 12,margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(color: _highlightColor(note.highlightColor),shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(child: Text(note.isSpoilerLocked ? '아직 안 읽은 부분이라 가려 뒀어요' : title,
                    style: const TextStyle(fontSize: 15,height: 1.5))),
              ]),
            ),
            Padding(padding: const EdgeInsets.only(left: 24),child: Row(children: [
              Expanded(child: Text('$location$dateText',style: const TextStyle(fontSize: 12,color: Color(0xFF9E9E9E)))),
              if (note.mine) PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz,color: Color(0xFF9E9E9E)),
                onSelected: (action) => _action(note,action),
                itemBuilder: (_) => [
                  if (_canChangeHighlightColor(note)) const PopupMenuItem(value:'color',child:Text('색상 변경')),
                  const PopupMenuItem(value:'delete',child:Text('삭제',style:TextStyle(color:Colors.red))),
                ],
              ),
            ])),
          ],
        )));
  }

  @override
  Widget build(BuildContext context) {
    final allNotes = widget.cachedNotes;
    final notes = allNotes.where((note) {
      if (widget.type != null && note.type != widget.type) return false;
      if (note.type != 'HIGHLIGHT') return true;
      return !allNotes.any((memo) => memo.type == 'MEMO' &&
          memo.userId == note.userId &&
          _memoCoversHighlight(
            note.paragraphOrder, note.startOffset, note.endOffset,
            memo.paragraphOrder, memo.startOffset, memo.endOffset, memo.ranges,
          ));
    }).toList();
    notes.sort((a,b) {
      final order = a.paragraphOrder.compareTo(b.paragraphOrder);
      return order != 0 ? order : (a.startOffset ?? 0).compareTo(b.startOffset ?? 0);
    });
    if (widget.type == null || widget.type == 'MEMO') {
      final vm = context.read<BookViewModel>();
      final otherNotes = notes.where((n) => n.type != 'MEMO').map((n) => ReadingNote(
        id: n.id, type: n.type == 'BOOKMARK' ? ReaderNoteType.bookmark : ReaderNoteType.highlight,
        paragraphOrder: n.paragraphOrder, selectedText: n.selectedText,
        startOffset: n.startOffset, endOffset: n.endOffset,
        highlightColor: n.highlightColor, preview: '', createdAt: n.createdAt,
      )).toList();
      return _MemoTab(
        allNotesMode: widget.type == null,
        currentPage: widget.currentPage, pageOf: widget.pageOf,
        bookId: widget.bookId, roomId: widget.roomId,
        suppliedSharedNotes: allNotes,
        targetNoteId: widget.targetNoteId,
        onSharedAction: _action,
        onOpenComments: widget.onOpenComments,
        onSharedRefresh: () { if (mounted) setState(_reload); },
        otherNotes: widget.type == null ? otherNotes : const [],
        noteBuilder: (note) => _recordCard(allNotes.firstWhere((n) => n.id == note.id)),
        myMemos: const [], chapters: vm.readerChapters,
        myNickname: context.read<RidiStore>().nickname,
        aiFriends: const [], selectedAiFriendIds: const {},
        aiNotesByFriend: const {}, aiFriendHighlightColors: const {},
        onGo: widget.onGo,
        onEdit: (_) async {}, onColor: (_) async {}, onDelete: (_) async {},
      );
    }
    if (notes.isEmpty) return const Center(child: Text('저장한 독서노트가 없습니다.'));
    return _NotesScrollbar(
      child: ListView.separated(
        primary: true, padding: const EdgeInsets.only(bottom: 12),
        itemCount: notes.length,
        separatorBuilder: (_,__) => const Divider(height: 1, color: Color(0xFFEDEDED)),
        itemBuilder: (_,i) => _recordCard(notes[i]),
      ),
    );
  }
}

class _Notes extends StatefulWidget {
  const _Notes({
    required this.pageOf,
    required this.bookId,
    required this.order,
    required this.currentPage,
    required this.spoilerReadOrder,
    required this.onGo,
    required this.aiFriends,
    required this.selectedAiFriendIds,
    required this.aiNotesByFriend,
    required this.aiFriendHighlightColors,

    this.targetNoteId,
    this.openInitialComments = false,
    this.roomId,
    this.initialRoomBookmarks,
    this.onRoomNotesLoaded,
  });

  final int? targetNoteId;
  final bool openInitialComments;
  final int? roomId;
  final ValueChanged<List<SharedRoomNote>>? onRoomNotesLoaded;
  final List<SharedRoomNote>? initialRoomBookmarks;
  final int currentPage;
  final int spoilerReadOrder;
  final int bookId;
  final int order;
  final void Function(int order, [int? offset]) onGo;
  final int? Function(int order, int? offset) pageOf;

  final List<AiReadingFriend> aiFriends;
  final Set<int> selectedAiFriendIds;
  final Map<int, List<AiReadingNote>> aiNotesByFriend;
  final Map<int, String> aiFriendHighlightColors;


  @override
  State<_Notes> createState() => _NotesState();
}

class _NotesState extends State<_Notes> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final Set<int> _deletingIds = <int>{};

  bool _initialTargetHandled = false;
  SharedRoomNote? _commentNote;
  List<SharedRoomNote>? _cachedRoomNotes;
  Object? _roomLoadError;
  bool _loadingRoomNotes = false;
  bool _roomRefreshPending = false;
  bool _pollingRoomNotes = false;
  int _roomEventCursor = 0;
  Timer? _roomNotesTimer;

  ReadingRoomRepository get _roomRepository => ReadingRoomRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken));

  Future<void> _refreshRoomNotes() async {
    if (widget.roomId == null || !mounted) return;
    if (_loadingRoomNotes) { _roomRefreshPending = true; return; }
    _loadingRoomNotes = true;
    try {
      final loaded = await _roomRepository.sharedNotes(widget.roomId!, bookId: widget.bookId);
      if (mounted) {
        setState(() { _cachedRoomNotes = loaded; _roomLoadError = null; });
        widget.onRoomNotesLoaded?.call(loaded);
        if (!_initialTargetHandled && widget.targetNoteId != null) {
          _initialTargetHandled = true;
          final matches = loaded.where((n) => n.id == widget.targetNoteId && n.type == 'MEMO');
          if (matches.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제되었거나 더 이상 볼 수 없는 메모입니다.')));
          } else if (widget.openInitialComments && !matches.first.isSpoilerLocked) {
            setState(() => _commentNote = matches.first);
          }
        }
      }
    } catch(e) {
      if (mounted) setState(() => _roomLoadError = e);
    } finally {
      _loadingRoomNotes = false;
      if (_roomRefreshPending && mounted) {
        _roomRefreshPending = false;
        unawaited(_refreshRoomNotes());
      }
    }
  }

  Future<void> _pollRoomNoteEvents() async {
    if (!mounted || widget.roomId == null || _pollingRoomNotes) return;
    _pollingRoomNotes = true;
    try {
      final ids = await _roomRepository.syncEventIds(widget.roomId!, _roomEventCursor);
      if (!mounted || ids.isEmpty) return;
      final cursor = ids.reduce((a,b) => a > b ? a : b);
      if (_loadingRoomNotes) return;
      await _refreshRoomNotes();
      if (_roomLoadError == null) _roomEventCursor = cursor;
    } catch(e) {
      debugPrint('독서노트 변경 확인 실패: $e');
    } finally { _pollingRoomNotes = false; }
  }

  @override
  void initState() {
    super.initState();
    if (widget.roomId != null) {
      unawaited(_refreshRoomNotes());
      _roomNotesTimer = Timer.periodic(const Duration(seconds: 5),
              (_) => unawaited(_pollRoomNoteEvents()));
    }
    _tabs.addListener(() {
      if (mounted && !_tabs.indexIsChanging) setState(() {});
    });
  }

  Future<void> _changeNoteColor(ReadingNote note) async {
    const colors = <String, String>{
      '#FFF59D': '노랑', '#F8BBD0': '분홍', '#A5D6A7': '초록',
      '#90CAF9': '파랑', '#CE93D8': '보라', '#FFCC80': '주황',
      '#EF9A9A': '빨강', '#80CBC4': '민트', '#B3E5FC': '하늘', '#BDBDBD': '회색',
    };
    // Older highlights used peach; represent it with the orange palette slot.
    final savedColor = note.highlightColor?.trim().toUpperCase();
    final selectedColor = switch (savedColor) {
      'PEACH' || '#FFCCBC' => '#FFCC80',
      '#FFEB3B' => '#FFF59D',
      '#FF4081' => '#F8BBD0',
      '#69F0AE' => '#A5D6A7',
      '#40C4FF' => '#90CAF9',
      '#E040FB' => '#CE93D8',
      '#FFAB40' => '#FFCC80',
      _ => savedColor,
    };
    final chosen = await showDialog<String>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => AlertDialog(
        title: const Text('색상 변경'),
        content: SizedBox(width: 300, child: Wrap(
          spacing: 12, runSpacing: 16,
          children: colors.entries.map((entry) => InkWell(
            onTap: () => Navigator.pop(dialogContext, entry.key),
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: 48, child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Color(0xFF000000 | int.parse(entry.key.substring(1), radix: 16)),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black26),
                  ),
                  child: _highlightColor(selectedColor) == _highlightColor(entry.key)
                      ? const Icon(Icons.check, size: 22) : null,
                ),
                const SizedBox(height: 4),

              ],
            )),
          )).toList(),
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'))],
      ),
    );
    if (!mounted || chosen == null) return;
    try {
      await context.read<BookViewModel>().updateNote(widget.bookId, note.id, color: chosen);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('색상 변경 실패: $e')));
    }
  }

  @override
  void dispose() {
    _roomNotesTimer?.cancel();
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
      width: double.infinity,
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
      child: Stack(fit: StackFit.expand, children: [
        Offstage(
          offstage: _commentNote != null,
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
                    if (widget.roomId != null) {
                      // Own bookmarks can render immediately from the reader cache.
                      // Never seed memo tabs with the body's unmasked spoiler data.
                      final roomNotes = _cachedRoomNotes ??
                          (index == 3 ? widget.initialRoomBookmarks : null);
                      if (roomNotes == null) {
                        if (_roomLoadError != null) return Center(child: TextButton(
                          onPressed: () => unawaited(_refreshRoomNotes()),
                          child: const Text('독서노트를 불러오지 못했습니다. 다시 시도'),
                        ));
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _SharedRoomNotesTab(
                        targetNoteId: widget.targetNoteId,
                        cachedNotes: roomNotes,
                        onRefresh: () => unawaited(_refreshRoomNotes()),
                        onOpenComments: (note) => setState(() => _commentNote = note),
                        roomId: widget.roomId!,
                        bookId: widget.bookId,
                        pageOf: widget.pageOf,
                        currentPage: widget.currentPage,
                        type: switch (index) {
                          1 => 'HIGHLIGHT',
                          2 => 'MEMO',
                          3 => 'BOOKMARK',
                          _ => null,
                        },
                        onGo: (order, [offset]) {
                          Navigator.of(context).pop();
                          widget.onGo(order, offset);
                        },
                      );
                    }
                    // 메모 탭: 사람별 거르기 + 메모 카드 (사용자 첨부 이미지, 수정2-1쪽 "메모 선택시")
                    if (index == 0 || index == 2) {
                      return _MemoTab(
                        allNotesMode: index == 0,
                        currentPage: widget.currentPage,
                        spoilerReadOrder: widget.spoilerReadOrder,
                        pageOf: widget.pageOf,
                        otherNotes: index == 0
                            ? vm.readingNotes.where(
                              (n) => n.type != ReaderNoteType.memo &&
                              (n.type != ReaderNoteType.highlight ||
                                  !vm.readingNotes.any((memo) =>
                                  memo.type == ReaderNoteType.memo &&
                                      (memo.linkedHighlightId == n.id ||
                                          _memoCoversHighlight(
                                            n.paragraphOrder, n.startOffset, n.endOffset,
                                            memo.paragraphOrder, memo.startOffset,
                                            memo.endOffset, memo.ranges,
                                          )))),
                        ).toList()
                            : const <ReadingNote>[],
                        noteBuilder: (note) => _noteCard(
                          note,
                          note.type == ReaderNoteType.bookmark ? 3 : 1,
                          vm,
                        ),
                        bookId: widget.bookId,
                        roomId: widget.roomId,
                        myMemos: vm.readingNotes
                            .where((n) => n.type == ReaderNoteType.memo)
                            .toList(),
                        chapters: vm.readerChapters,
                        myNickname: context.read<RidiStore>().nickname,

                        aiFriends: widget.aiFriends,
                        selectedAiFriendIds: widget.selectedAiFriendIds,
                        aiNotesByFriend: widget.aiNotesByFriend,
                        aiFriendHighlightColors: widget.aiFriendHighlightColors,

                        onGo: (order, [offset]) {
                          Navigator.of(context).pop();
                          widget.onGo(order, offset);
                        },
                        onEdit: _edit,
                        onColor: _changeNoteColor,
                        onDelete: _delete,
                      );
                    }
                    // A room reader must never expose notes saved in the
                    // personal reader.  Shared room memos have their dedicated
                    // tab above; other private-note tabs intentionally stay
                    // empty in this context until their shared counterparts are
                    // created through the room API.
                    final notes =
                    (filters[index] == null
                        ? vm.readingNotes
                        : vm.readingNotes
                        .where((note) => note.type == filters[index])
                        .where((note) => note.type != ReaderNoteType.highlight ||
                        !vm.readingNotes.any((memo) =>
                        memo.type == ReaderNoteType.memo &&
                            (memo.linkedHighlightId == note.id ||
                                _memoCoversHighlight(
                                  note.paragraphOrder, note.startOffset,
                                  note.endOffset, memo.paragraphOrder,
                                  memo.startOffset, memo.endOffset,
                                  memo.ranges,
                                ))))
                        .toList())
                      ..sort((a, b) {
                        final order =
                        a.paragraphOrder.compareTo(b.paragraphOrder);

                        if (order != 0) return order;

                        return (a.startOffset ?? 0)
                            .compareTo(b.startOffset ?? 0);
                      });
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
                    return _NotesScrollbar(
                      child: ListView.separated(
                        primary: true,
                        itemCount: notes.length,
                        separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFFEDEDED)),
                        itemBuilder: (_, i) => _noteCard(
                          notes[i], index, vm,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              // 아래 버튼 줄(현재 위치 메모 · 문단 형광펜 · 모두 삭제)은 뺌 (수정 확인 피드백)
            ],
          ),
        ),
        if (_commentNote != null && widget.roomId != null)
          Positioned.fill(child: buildSharedNoteCommentsPanel(
            repository: _roomRepository, roomId: widget.roomId!, note: _commentNote!,
            onClose: () {
              setState(() => _commentNote = null);
              unawaited(_refreshRoomNotes());
            },
          )),
      ]),
    );
  }

  Widget _noteCard(
      ReadingNote note,
      int index,
      BookViewModel vm,
      ) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        widget.onGo(note.paragraphOrder, note.startOffset);
      },
      child: _noteCardContent(note, index, vm),
    );
  }

  Widget _noteCardContent(ReadingNote note, int index, BookViewModel vm) {
    if (index == 1) {
      final d = note.createdAt?.toLocal();
      final date = d == null
          ? ''
          : '${d.year}.'
          '${d.month.toString().padLeft(2, '0')}.'
          '${d.day.toString().padLeft(2, '0')}.';

      final text = note.selectedText?.isNotEmpty == true
          ? note.selectedText!
          : note.preview;

      final page = widget.pageOf(
        note.paragraphOrder,
        note.startOffset,
      );
      final location = page == null
          ? '페이지 확인 불가'
          : '$page 페이지';

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                Navigator.of(context).pop();
                widget.onGo(note.paragraphOrder, note.startOffset);
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _highlightColor(
                          note.highlightColor,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      date.isEmpty
                          ? location
                          : '$location  |  $date',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9E9E),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '형광펜 메뉴',
                    enabled:
                    !_deletingIds.contains(note.id),
                    icon: const Icon(
                      Icons.more_horiz,
                      color: Color(0xFF9E9E9E),
                    ),
                    onSelected: (action) async {
                      if (action == 'color') {
                        await _changeNoteColor(note);
                      } else if (action == 'delete') {
                        await _delete(note);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem<String>(value: 'color', child: Text('색상 변경')),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text(
                          '삭제',
                          style: TextStyle(
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (index == 3) {
      final page = widget.pageOf(note.paragraphOrder, note.startOffset);
      return _BookmarkNoteTile(
        title: _bookmarkChapterTitle(vm.readerChapters, note.paragraphOrder),
        location: page == null ? '페이지 확인 불가' : '$page 페이지',
        date: _bookmarkDate(note.createdAt),
        busy: _deletingIds.contains(note.id),
        onTap: () {
          Navigator.of(context).pop();
          widget.onGo(note.paragraphOrder, note.startOffset);
        },
        onDelete: () => _delete(note),
      );
    }
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
        widget.onGo(note.paragraphOrder, note.startOffset);
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
      final viewModel = context.read<BookViewModel>();

      final linkedHighlightIds =
      note.type == ReaderNoteType.memo &&
          note.startOffset != null &&
          note.endOffset != null
          ? viewModel.readingNotes
          .where(
            (n) =>
        n.type == ReaderNoteType.highlight &&
            n.paragraphOrder == note.paragraphOrder &&
            n.startOffset != null &&
            n.endOffset != null &&
            n.startOffset! <= note.startOffset! &&
            n.endOffset! >= note.endOffset!,
      )
          .map((n) => n.id)
          .toList()
          : <int>[];

      await viewModel.deleteNote(widget.bookId, note.id);

      for (final id in linkedHighlightIds) {
        await viewModel.deleteNote(widget.bookId, id);
      }
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Actual space already excludes Dialog's keyboard and safe insets.
            final availableHeight = constraints.hasBoundedHeight
                ? constraints.maxHeight : 520.0;
            final editorHeight = (availableHeight - 200).clamp(60.0, 300.0).toDouble();
            return SingleChildScrollView(
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
                      height: editorHeight,
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
            );
          },
        ),
      ),
    );
  }
}

/// 보기 설정 (사용자 첨부 이미지 = 리디 보기 설정에서 고른 것만):
/// 바탕색 동그라미 · 글자 크기 [−][+] · 행간 [−][+] · AI 친구 설정 › · 스포일러 켜기/끄기.
/// (밝기·글꼴·문단 간격·문단 너비·문단 정렬·형광펜 색상은 뺌)
/// 스포일러 잠금은 개인 독서의 AI 메모에 장 단위로 적용한다.
class _ViewSettings extends StatefulWidget {
  const _ViewSettings({
    this.showAiFriends = true,
    required this.onChange,
    required this.aiFriends,
    required this.selectedAiFriendIds,
    required this.onAiFriendDone,
    required this.progressVersion,
    required this.progressPercent,
    required this.generatingFriendIds,
    required this.failedFriendIds,
  });

  final bool showAiFriends;
  final ValueChanged<ReaderSettings> onChange;

  // 서버에서 받아온 AI 친구 목록
  final List<AiReadingFriend> aiFriends;

  // 현재 실제로 적용되어 있는 AI 친구들
  final Set<int> selectedAiFriendIds;

  // AI 친구 화면에서 "완료"를 눌렀을 때 호출
  final Future<void> Function(Set<int> selectedIds) onAiFriendDone;
  final ValueNotifier<int> progressVersion;
  final Map<int, int> progressPercent;
  final Set<int> generatingFriendIds;
  final Set<int> failedFriendIds;

  @override
  State<_ViewSettings> createState() => _ViewSettingsState();
}

class _ViewSettingsState extends State<_ViewSettings> {
  final _viewSettingsKey = GlobalKey();
  Size? _viewSettingsSize;

  final _aiScrollController = ScrollController();

  static const _themes = [
    (ReaderPaperTheme.light, Color(0xFFFFFFFF), '기본'),
    (ReaderPaperTheme.sepia, Color(0xFFF4ECD8), '세피아'),
    (ReaderPaperTheme.dark, Color(0xFF2B2B2B), '어둡게'),
  ];

  static const _lineLabels = ['좁게', '보통', '넓게'];

  static final _spoiler = ValueNotifier<bool>(true);
  static String? _spoilerAccount;
  static String _spoilerKey(String account) => 'reader_spoiler_enabled:$account';
  bool _savingSpoiler = false;

  static Future<void> _loadSpoilerPreference(BuildContext context) async {
    final store = context.read<RidiStore>();
    final account = store.loggedIn ? store.username : '';
    if (_spoilerAccount != account) {
      _spoilerAccount = account;
      _spoiler.value = true;
    }
    if (account.isEmpty) return;
    final token = store.accessToken;
    try {
      final response = await ApiClient(tokenProvider: () => token).get<Map<String,dynamic>>(
          '/api/me/spoiler-setting', parse: (json) => json as Map<String,dynamic>);
      if (!store.loggedIn || store.username != account || _spoilerAccount != account) return;
      _spoiler.value = response.data?['enabled'] != false;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_spoilerKey(account), _spoiler.value);
      } catch (_) { /* The server is authoritative. */ }
    } catch (error) {
      if (!store.loggedIn || store.username != account || _spoilerAccount != account) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (store.loggedIn && store.username == account && _spoilerAccount == account) {
          _spoiler.value = prefs.getBool(_spoilerKey(account)) ?? true;
        }
      } catch (_) { /* Keep the protected default if cache access also fails. */ }
      debugPrint('스포일러 설정 조회 실패: ${error.runtimeType}');
    }
  }

  Future<void> _setSpoilerPreference(bool value) async {
    if (_savingSpoiler) return;
    final store = context.read<RidiStore>();
    final account = store.username;
    final token = store.accessToken;
    setState(() => _savingSpoiler = true);
    try {
      final response = await ApiClient(tokenProvider: () => token).patch<Map<String,dynamic>>(
          '/api/me/spoiler-setting', body: {'enabled': value},
          parse: (json) => json as Map<String,dynamic>);
      if (!mounted || !store.loggedIn || store.username != account) return;
      final saved = response.data?['enabled'] != false;
      _spoilerAccount = account;
      _spoiler.value = saved;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_spoilerKey(account), saved);
      } catch (_) { /* A local cache failure must not undo a saved setting. */ }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is ApiException ? error.message : '스포일러 설정을 저장하지 못했습니다.')));
    } finally {
      if (mounted) setState(() => _savingSpoiler = false);
    }
  }

  bool _showAiFriends = false;
  bool _savingAiFriends = false;

  late Set<int> _draftSelectedIds;

  @override
  void initState() {
    super.initState();

    // 아직 완료를 누르지 않은 임시 선택 상태
    _draftSelectedIds = <int>{...widget.selectedAiFriendIds};
  }

  @override
  void dispose() {
    _aiScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showAiFriends) {
      return ValueListenableBuilder<int>(
        valueListenable: widget.progressVersion,
        builder: (context, _, __) => _buildAiFriendSettings(context),
      );
    }

    return SizedBox(key: _viewSettingsKey, child: _buildViewSettings(context));
  }

  Widget _buildViewSettings(BuildContext context) {
    final s = context.watch<BookViewModel>().readerSettings;

    final fontLevel = ((s.fontScale - .8) / .1).round() + 1;

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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
                            : () => widget.onChange(s.copyWith(theme: t.$1)),
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
                              width: s.theme == t.$1 ? 2.5 : 1,
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
                  fontScale: ((s.fontScale - .1) * 10).round() / 10,
                ),
              ),
              onPlus: s.fontScale >= 1.4 - 1e-6
                  ? null
                  : () => widget.onChange(
                s.copyWith(
                  fontScale: ((s.fontScale + .1) * 10).round() / 10,
                ),
              ),
            ),

            divider,

            _StepRow(
              icon: Icons.format_line_spacing,
              label: '행간',
              value: _lineLabels[s.lineHeightStep.clamp(0, 2)],
              onMinus: s.lineHeightStep <= 0
                  ? null
                  : () => widget.onChange(
                s.copyWith(lineHeightStep: s.lineHeightStep - 1),
              ),
              onPlus: s.lineHeightStep >= 2
                  ? null
                  : () => widget.onChange(
                s.copyWith(lineHeightStep: s.lineHeightStep + 1),
              ),
            ),

            divider,

            // Personal AI controls are excluded from room readers.
            if (widget.showAiFriends) ...[
              InkWell(
                onTap: () {
                  final renderBox =
                  _viewSettingsKey.currentContext!.findRenderObject()
                  as RenderBox;

                  setState(() {
                    _viewSettingsSize = renderBox.size;

                    _draftSelectedIds = <int>{...widget.selectedAiFriendIds};

                    _showAiFriends = true;
                  });
                },
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 16, 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.smart_toy_outlined,
                        size: 20,
                        color: Color(0xFF9E9E9E),
                      ),
                      SizedBox(width: 10),
                      Text('AI 친구 설정', style: TextStyle(fontSize: 15)),
                      Spacer(),
                      Icon(Icons.chevron_right, color: Color(0xFFB0B0B0)),
                    ],
                  ),
                ),
              ),

              divider,
            ],

            ValueListenableBuilder<bool>(
              valueListenable: _spoiler,
              builder: (_, on, _) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.visibility_off_outlined,
                      size: 20,
                      color: Color(0xFF9E9E9E),
                    ),
                    const SizedBox(width: 10),
                    const Text('스포일러', style: TextStyle(fontSize: 15)),
                    const Spacer(),
                    Switch(value: on, onChanged: _savingSpoiler ? null : _setSpoilerPreference),
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
      width: _viewSettingsSize!.width,
      height: _viewSettingsSize!.height,
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
                    onPressed: _savingAiFriends ? null : _completeAiFriends,
                    child: const Text(
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
            const Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                  child: Text(
                    '사용할 수 있는 AI 친구가 없습니다.',
                    style: TextStyle(fontSize: 14, color: Color(0xFF8A8A8A)),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Scrollbar(
                controller: _aiScrollController,
                thumbVisibility: false,
                thickness: 4,
                radius: const Radius.circular(8),
                child: ListView.separated(
                  controller: _aiScrollController,
                  padding: EdgeInsets.zero,
                  itemCount: widget.aiFriends.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: Color(0xFFEDEDED),
                  ),
                  itemBuilder: (_, index) {
                    final friend = widget.aiFriends[index];

                    final selected = _draftSelectedIds.contains(friend.id);

                    return InkWell(
                      onTap: _savingAiFriends
                          ? null
                          : () {
                        setState(() {
                          if (selected) {
                            _draftSelectedIds.remove(friend.id);
                          } else {
                            _draftSelectedIds.add(friend.id);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 18, 14),
                        child: Row(
                          children: [
                            _aiFriendAvatar(friend),

                            const SizedBox(width: 12),

                            Expanded(
                              child: Text(
                                friend.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                            if (selected)
                              widget.generatingFriendIds.contains(friend.id)
                                  ? SizedBox(
                                width: 40,
                                height: 40,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      value:
                                      (widget.progressPercent[friend
                                          .id] ??
                                          0) /
                                          100,
                                      strokeWidth: 3,
                                      color: const Color(0xFF1E88E5),
                                      backgroundColor: const Color(
                                        0xFFE5E7EB,
                                      ),
                                    ),
                                    Text(
                                      '${widget.progressPercent[friend.id] ?? 0}%',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                                  : widget.failedFriendIds.contains(friend.id)
                                  ? const Tooltip(
                                message: '메모 작성이 중단되었습니다',
                                child: Icon(
                                  Icons.error_outline,
                                  color: Colors.redAccent,
                                ),
                              )
                                  : const Icon(
                                Icons.check,
                                size: 23,
                                color: Color(0xFF1E88E5),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ), // ListView.separated 끝
              ), // Scrollbar 끝
            ), // Expanded 끝
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
      await widget.onAiFriendDone(Set<int>.from(_draftSelectedIds));
      if (mounted) Navigator.of(context).pop();
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
    this.targetNoteId,
    this.allNotesMode = false,
    this.suppliedSharedNotes,
    this.onSharedAction,
    this.onSharedRefresh,
    this.onOpenComments,
    this.currentPage = 1,
    this.spoilerReadOrder = 1,
    this.otherNotes = const <ReadingNote>[],
    this.noteBuilder,
    required this.pageOf,
    required this.bookId,
    required this.roomId,
    required this.myMemos,
    required this.chapters,
    required this.myNickname,
    required this.aiFriends,
    required this.selectedAiFriendIds,
    required this.aiNotesByFriend,
    required this.aiFriendHighlightColors,
    required this.onGo,
    required this.onEdit,
    required this.onColor,
    required this.onDelete,
  });

  final ValueChanged<SharedRoomNote>? onOpenComments;
  final VoidCallback? onSharedRefresh;
  final List<SharedRoomNote>? suppliedSharedNotes;
  final Future<void> Function(SharedRoomNote note, String action)? onSharedAction;
  final int? targetNoteId;
  final bool allNotesMode;
  final int currentPage;
  final int spoilerReadOrder;
  final List<ReadingNote> otherNotes;
  final Widget Function(ReadingNote)? noteBuilder;
  final int? Function(int order, int? offset) pageOf;
  final int bookId;
  final int? roomId;
  final List<ReadingNote> myMemos;
  final List<ReaderChapter> chapters;
  final String myNickname;

  final List<AiReadingFriend> aiFriends;
  final Set<int> selectedAiFriendIds;
  final Map<int, List<AiReadingNote>> aiNotesByFriend;
  final Map<int, String> aiFriendHighlightColors;

  final void Function(int order, [int? offset]) onGo;
  final Future<void> Function(ReadingNote) onEdit;
  final Future<void> Function(ReadingNote) onColor;
  final Future<void> Function(ReadingNote) onDelete;

  @override
  State<_MemoTab> createState() => _MemoTabState();
}

class _MemoItem {
  _MemoItem({
    required this.author,
    required this.mine,
    required this.order,
    this.startOffset = 0,
    this.quote,
    this.memo,
    this.color,
    this.at,
    this.comments,
    this.shared,
    this.own,
    this.locked = false,
    this.revealKey,
    this.onReveal,
    this.aiFriend,
  });
  final String author;
  final AiReadingFriend? aiFriend;
  final bool mine;
  final int order;
  final int startOffset;
  final String? quote, memo, color;
  final DateTime? at;
  final int? comments;
  final SharedRoomNote? shared;
  final ReadingNote? own;
  final bool locked;
  final String? revealKey;
  final Future<void> Function()? onReveal;

  // Sharing always copies the author's memo; room ids never enter personal CRUD.
  ReadingNote? get shareSource {
    if (!mine || locked) return null;
    if (own != null) return own;
    final note = shared;
    if (note == null || note.type != 'MEMO') return null;
    return ReadingNote(
      id: note.id, type: ReaderNoteType.memo,
      paragraphOrder: note.paragraphOrder,
      memoContent: note.content, selectedText: note.selectedText,
      startOffset: note.startOffset, endOffset: note.endOffset,
      highlightColor: note.highlightColor, ranges: note.ranges,
      preview: note.content ?? '', createdAt: note.createdAt,
    );
  }
}

class _MemoTabState extends State<_MemoTab> {
  final Map<int, SharedRoomNote> _revealedRoomNotes = {};
  final Set<String> _revealedAiNotes = {};
  final Set<int> _revealingRoomNotes = {};
  Future<List<SharedRoomNote>>? _room;
  String _who = '전체';
  bool _shareSelecting = false;
  List<ReadingNote> _shareSources = const [];
  final Set<int> _selectedMemoIds = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toggleShareSelection() {
    setState(() {
      _shareSelecting = !_shareSelecting;
      _selectedMemoIds.clear();
    });
  }

  void _toggleSelectedMemo(int memoId) {
    setState(() {
      if (!_selectedMemoIds.add(memoId)) {
        _selectedMemoIds.remove(memoId);
      }
    });
  }

  Future<void> _showSelectedMemoNotice() async {
    if (_selectedMemoIds.isEmpty) return;

    final token = context.read<RidiStore>().accessToken;
    final repository = ReadingRoomRepository(
      ApiClient(tokenProvider: () => token),
    );

    try {
      final rooms = (await repository.shareTargets(widget.bookId))
          .where((room) => room.id != widget.roomId).toList();

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final selectedRoomIds = <int>{};
          bool selectedPersonal = false;
          bool sharing = false;

          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('공유할 곳 선택'),
                content: SizedBox(
                  width: 400,
                  child: rooms.isEmpty && widget.roomId == null
                      ? const Text(
                    '현재 이 책을 공유할 수 있는 교환독서방이 없습니다.',
                  )
                      : ListView(
                    shrinkWrap: true,
                    children: [
                      if (widget.roomId != null)
                        CheckboxListTile(
                          title: const Text('혼자읽기'),
                          value: selectedPersonal,
                          onChanged: sharing ? null : (checked) => setDialogState(() {
                            selectedPersonal = checked == true;
                          }),
                        ),
                      for (final room in rooms)
                        CheckboxListTile(
                          title: Text(room.name),
                          value: selectedRoomIds.contains(room.id),
                          onChanged: sharing ? null : (checked) {
                            setDialogState(() {
                              if (checked == true) {
                                selectedRoomIds.add(room.id);
                              } else {
                                selectedRoomIds.remove(room.id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: sharing ? null : () => Navigator.pop(dialogContext),
                    child: const Text('취소'),
                  ),
                  FilledButton(
                    onPressed: sharing || (selectedRoomIds.isEmpty && !selectedPersonal)
                        ? null
                        : () async {
                      final messenger =
                      ScaffoldMessenger.of(this.context);

                      final memos = _shareSources
                          .where(
                            (m) => _selectedMemoIds.contains(m.id),
                      )
                          .toList();

                      final roomIds = selectedRoomIds.toList();
                      final copyToPersonal = selectedPersonal;

                      // 요청 중 중복 클릭 방지
                      setDialogState(() {
                        sharing = true;
                      });

                      try {
                        if (copyToPersonal) {
                          final personal = BookRepository(ApiClient(tokenProvider: () => token));
                          final existing = await personal.readingNotes(widget.bookId, type: ReaderNoteType.memo);
                          for (final memo in memos) {
                            final duplicate = existing.any((note) =>
                            note.paragraphOrder == memo.paragraphOrder &&
                                note.startOffset == memo.startOffset &&
                                note.endOffset == memo.endOffset &&
                                note.selectedText == memo.selectedText &&
                                (note.memoContent ?? '') == (memo.memoContent ?? '') &&
                                note.ranges.length == memo.ranges.length &&
                                List.generate(note.ranges.length, (i) =>
                                note.ranges[i].paragraphOrder == memo.ranges[i].paragraphOrder &&
                                    note.ranges[i].startOffset == memo.ranges[i].startOffset &&
                                    note.ranges[i].endOffset == memo.ranges[i].endOffset).every((v) => v));
                            if (duplicate) continue;
                            final created = await personal.addReadingNote(widget.bookId,
                                type: ReaderNoteType.memo, paragraphOrder: memo.paragraphOrder,
                                memoContent: memo.memoContent, selectedText: memo.selectedText,
                                startOffset: memo.startOffset, endOffset: memo.endOffset,
                                ranges: memo.ranges, highlightColor: memo.highlightColor);
                            existing.add(created);
                          }
                          if (mounted) await this.context.read<BookViewModel>().loadReadingNotes(widget.bookId);
                        }
                        for (final roomId in roomIds) {
                          final existingNotes = await repository.sharedNotes(
                            roomId,
                            bookId: widget.bookId,
                          );

                          for (final memo in memos) {
                            final alreadyShared = existingNotes.any(
                                  (note) =>
                              note.mine &&
                                  note.type == 'MEMO' &&
                                  note.paragraphOrder == memo.paragraphOrder &&
                                  note.startOffset == memo.startOffset &&
                                  note.endOffset == memo.endOffset &&
                                  note.selectedText == memo.selectedText &&
                                  (note.content ?? '') == (memo.memoContent ?? ''),
                            );

                            if (alreadyShared) continue;

                            final created = await repository.createSharedNote(
                              roomId,
                              {
                                'bookId': widget.bookId,
                                'type': 'MEMO',
                                'paragraphOrder': memo.paragraphOrder,
                                'startOffset': memo.startOffset,
                                'endOffset': memo.endOffset,
                                'selectedText': memo.selectedText,
                                if (memo.ranges.isNotEmpty) 'ranges': memo.ranges.map((r) => r.toJson()).toList(),
                                'content': memo.memoContent,
                                'highlightColor': memo.highlightColor,
                              },
                            );

                            existingNotes.add(created);
                          }
                        }

                        if (!mounted) return;

                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }

                        setState(() {
                          _shareSelecting = false;
                          _selectedMemoIds.clear();
                        });

                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('공유하였습니다'),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;

                        if (dialogContext.mounted) {
                          setDialogState(() {
                            sharing = false;
                          });
                        }

                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              e is ApiException
                                  ? '공유하지 못했습니다: ${e.message}'
                                  : '공유 중 오류가 발생했습니다.',
                            ),
                          ),
                        );
                      }
                    },
                    child: Text(sharing ? '공유 중' : '공유하기'),
                  ),
                ],
              );
            },
          );
        },
      );
    } on ApiException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('독서방 목록을 불러오지 못했습니다: ${e.message}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('독서방 목록을 불러오는 중 오류가 발생했습니다.'),
        ),
      );
    }
  }

  void _load() {
    if (widget.suppliedSharedNotes != null) return;
    final roomId = widget.roomId;
    if (roomId == null) return;
    final token = context.read<RidiStore>().accessToken;
    _room = ReadingRoomRepository(ApiClient(tokenProvider: () => token))
        .sharedNotes(roomId, bookId: widget.bookId);
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
            startOffset: n.startOffset ?? 0,
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
      for (final original in shared.where((n) => n.type == 'MEMO')) {
        final revealed = _revealedRoomNotes[original.id];
        final n = revealed != null && revealed.version == original.version ? revealed : original;
        items.add(
          _MemoItem(
            author: n.nickname,
            mine: n.mine,
            order: n.paragraphOrder,
            startOffset: n.startOffset ?? 0,
            quote: n.selectedText,
            memo: n.content,
            color: n.highlightColor,
            at: n.createdAt,
            comments: n.commentCount,
            shared: n,
            locked: n.isSpoilerLocked,
            revealKey: 'room:${n.id}',
            onReveal: () async {
              if (!_revealingRoomNotes.add(n.id)) return;
              try {
                final token = context.read<RidiStore>().accessToken;
                final full = await ReadingRoomRepository(ApiClient(tokenProvider: () => token))
                    .revealSharedNote(widget.roomId!, n.id);
                if (mounted) setState(() => _revealedRoomNotes[n.id] = full);
              } catch (error) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error is ApiException ? error.message : '메모를 불러오지 못했습니다. 다시 시도해주세요.')));
              } finally { _revealingRoomNotes.remove(n.id); }
            },
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
        final revealKey = 'ai:${friend.id}:${note.id}';
        final locked = !_revealedAiNotes.contains(revealKey) && widget.roomId == null && _ViewSettingsState._spoiler.value &&
            _isUnreadChapter(note.paragraphOrder, widget.spoilerReadOrder, widget.chapters);
        items.add(
          _MemoItem(
            author: friend.name,
            aiFriend: friend,
            mine: false,
            order: note.paragraphOrder,
            startOffset: note.startOffset,
            revealKey: revealKey,
            onReveal: () async { if (mounted) setState(() => _revealedAiNotes.add(revealKey)); },
            quote: locked ? null : note.selectedText,
            memo: locked ? null : note.content,
            locked: locked,
            color: widget.aiFriendHighlightColors[friend.id] ?? '#FFF59D',
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

  static Color _dot(String? value) {
    final color = value?.trim().toUpperCase() ?? '';
    const namedColors = <String, Color>{
      'YELLOW': Color(0xFFFFF59D),
      'PINK': Color(0xFFF8BBD0),
      'GREEN': Color(0xFFA5D6A7),
      'BLUE': Color(0xFF90CAF9),
      'PURPLE': Color(0xFFCE93D8),
      'ORANGE': Color(0xFFFFCC80),
      'RED': Color(0xFFEF9A9A),
      'MINT': Color(0xFF80CBC4),
      'SKY': Color(0xFFB3E5FC),
      'GRAY': Color(0xFFBDBDBD),
      'PEACH': Color(0xFFFFCCBC),
    };
    final named = namedColors[color];
    if (named != null) return named;
    final hex = color.replaceFirst('#', '');
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null || (hex.length != 6 && hex.length != 8)) {
      return namedColors['YELLOW']!;
    }
    return Color(0xFF000000 | (parsed & 0x00FFFFFF));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.suppliedSharedNotes != null) return _body(_items(widget.suppliedSharedNotes));
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
    _shareSources = all.map((item) => item.shareSource)
        .whereType<ReadingNote>().toList(growable: false);
    if (widget.allNotesMode) {
      final entries = <({int order, int offset, int sequence, int? memoId, Widget card})>[];
      for (final note in widget.otherNotes) {
        entries.add((
        order: note.paragraphOrder,
        offset: note.startOffset ?? 0,
        sequence: entries.length,
        memoId: null,
        card: widget.noteBuilder!(note),
        ));
      }
      for (final memo in all) {
        entries.add((
        order: memo.order,
        offset: memo.startOffset,
        sequence: entries.length,
        memoId: memo.shared?.id,
        card: _card(memo),
        ));
      }
      entries.sort((a, b) {
        final order = a.order.compareTo(b.order);
        if (order != 0) return order;
        final offset = a.offset.compareTo(b.offset);
        return offset != 0 ? offset : a.sequence.compareTo(b.sequence);
      });
      if (entries.isEmpty) {
        return const Center(child: Text('저장한 독서노트가 없습니다.'));
      }
      var target = widget.targetNoteId == null ? -1 : entries.indexWhere((e) => e.memoId == widget.targetNoteId);
      if (target < 0) target = entries.indexWhere((entry) =>
      (widget.pageOf(entry.order, entry.offset) ?? -1) >= widget.currentPage);
      if (target < 0) target = entries.length - 1;
      return _NotesScrollbar(
        child: _InitiallyPositionedNotes(
          targetIndex: target,
          cards: entries.map((entry) => entry.card).toList(),
        ),
      );
    }
    final others = <String>{
      for (final m in all)
        if (!m.mine) m.author,
    }.toList()..sort();
    final showFilters =
        widget.roomId != null || widget.selectedAiFriendIds.isNotEmpty;
    final canShowShare = !showFilters || _who == '나';
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
        if (_shareSelecting)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: _toggleShareSelection,
                  child: const Text('취소'),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    final selectableIds = shown
                        .where((m) => m.shareSource != null)
                        .map((m) => m.shareSource!.id)
                        .toSet();

                    final allSelected = selectableIds.isNotEmpty &&
                        selectableIds.every(_selectedMemoIds.contains);

                    return TextButton(
                      onPressed: selectableIds.isEmpty
                          ? null
                          : () {
                        setState(() {
                          if (allSelected) {
                            _selectedMemoIds.removeAll(selectableIds);
                          } else {
                            _selectedMemoIds.addAll(selectableIds);
                          }
                        });
                      },
                      child: Text(
                        allSelected ? '전체해제' : '전체선택',
                      ),
                    );
                  },
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _selectedMemoIds.isEmpty
                      ? null
                      : _showSelectedMemoNotice,
                  child: Text(
                    '다음 (${_selectedMemoIds.length})',
                  ),
                ),
              ],
            ),
          ),
        if (!_shareSelecting && (showFilters || canShowShare))
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            child: Row(
              children: [
                if (showFilters)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
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
                                color: _who == c
                                    ? Colors.white
                                    : const Color(0xFF333333),
                              ),
                              shape: const StadiumBorder(
                                side: BorderSide(
                                  color: Color(0xFFDDDDDD),
                                ),
                              ),
                              onSelected: (_) =>
                                  setState(() => _who = c),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  const Spacer(),

                if (canShowShare) ...[
                  const SizedBox(width: 8),
                  if (_shareSelecting) ...[
                    TextButton(
                      onPressed: _toggleShareSelection,
                      child: const Text('취소'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _selectedMemoIds.isEmpty
                          ? null
                          : _showSelectedMemoNotice,
                      child: Text(
                        '다음 (${_selectedMemoIds.length})',
                      ),
                    ),
                  ] else
                    TextButton.icon(
                      onPressed: _toggleShareSelection,
                      icon: const Icon(
                        Icons.share_outlined,
                        size: 18,
                      ),
                      label: const Text('공유'),
                    ),
                ],
              ],
            ),
          ),
        if (showFilters) const Divider(height: 1),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text(empty))
              : _NotesScrollbar(
            key: ValueKey('memo-scroll-$_who'),
            child: SingleChildScrollView(
              primary: true,
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(_MemoItem m) {
    const gray = Color(0xFF9E9E9E);
    final page = widget.pageOf(m.order, m.startOffset);
    final d = m.at?.toLocal();

    final date = d == null
        ? ''
        : '${d.year}.'
        '${d.month.toString().padLeft(2, '0')}.'
        '${d.day.toString().padLeft(2, '0')}.';

    final location = page == null
        ? '페이지 확인 불가'
        : '$page 페이지';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_shareSelecting && m.shareSource != null) ...[
                Checkbox(
                  value: _selectedMemoIds.contains(m.shareSource!.id),
                  onChanged: (_) => _toggleSelectedMemo(m.shareSource!.id),
                ),
                const SizedBox(width: 4),
              ],

              if (m.aiFriend != null)
                _aiFriendAvatar(m.aiFriend!, radius: 13)
              else CircleAvatar(
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
              if (m.mine) ...[
                Container(
                  width: 22, height: 22, alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Color(0xFF505761), shape: BoxShape.circle),
                  child: const Text('나', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                m.author,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('아직 읽지 않은 부분의 메모입니다.',
                    style: TextStyle(fontSize: 13, color: gray)),
                TextButton(onPressed: m.onReveal, child: const Text('메모 보기')),
              ]),
            )
          else
            InkWell(
              onTap: () {
                if (_shareSelecting && m.shareSource != null) {
                  _toggleSelectedMemo(m.shareSource!.id);
                } else if (!m.locked) {
                  widget.onGo(m.order, m.startOffset);
                }
              },
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (m.quote?.isNotEmpty == true)
                      Container(
                        margin: const EdgeInsets.only(
                          left: 36,
                          bottom: 6,
                        ),
                        padding: const EdgeInsets.only(left: 10),
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: Color(0xFFDDDDDD),
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          '“${m.quote!.trim().replaceAll(RegExp(r"\r\n?"), "\n").replaceAll(RegExp(r"\n(?:[ \t]*\n)+"), "\n")}”',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B6B6B),
                          ),
                        ),
                      ),
                    if (m.memo?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(left: 36),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                m.memo!,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            if (!_shareSelecting && !m.locked &&
                                (m.mine || m.shared?.canDelete == true) &&
                                (m.own != null || m.shared != null))
                              SizedBox(
                                width: 28,
                                height: 20,
                                child: PopupMenuButton<String>(
                                  tooltip: '메모 메뉴',
                                  iconSize: 20,
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.more_horiz,
                                    color: gray,
                                  ),
                                  onSelected: (action) async {
                                    if (m.shared != null) {
                                      await widget.onSharedAction?.call(m.shared!, action);
                                      return;
                                    }
                                    if (action == 'color') {
                                      await widget.onColor(m.own!);
                                    } else if (action == 'edit') {
                                      await widget.onEdit(m.own!);
                                    } else if (action == 'delete') {
                                      await widget.onDelete(m.own!);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (widget.roomId == null)
                                      const PopupMenuItem<String>(value: 'color', child: Text('색상 변경')),
                                    if (m.mine)
                                      PopupMenuItem<String>(
                                        value: 'edit',
                                        child: Text('수정'),
                                      ),
                                    PopupMenuItem<String>(
                                      value: 'delete',
                                      child: Text(
                                        '삭제',
                                        style: TextStyle(
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 2,
              children: [
                Text(
                  date.isEmpty ? location : '$location  |  $date',
                  style: const TextStyle(fontSize: 12, color: gray),
                ),
                if (!_shareSelecting && m.shared != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 24),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: m.locked ? null : () => _openComments(m.shared!),
                    icon: const Icon(Icons.chat_bubble_outline, size: 14, color: gray),
                    label: Text(
                      (m.comments ?? 0) > 0 ? '댓글 ${m.comments}' : '댓글 쓰기',
                      style: const TextStyle(fontSize: 12, color: gray),
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
    if (widget.onOpenComments != null) {
      widget.onOpenComments!(note);
      return;
    }
    final token = context.read<RidiStore>().accessToken;
    await showSharedNoteComments(
      context,
      ReadingRoomRepository(ApiClient(tokenProvider: () => token)),
      widget.roomId!,
      note,
    );
    if (!mounted) return;
    if (widget.onSharedRefresh != null) widget.onSharedRefresh!();
    else setState(_load);
  }
}

// Render variable-height cards before locating the current page's first note.
class _InitiallyPositionedNotes extends StatefulWidget {
  const _InitiallyPositionedNotes({required this.cards, required this.targetIndex});
  final List<Widget> cards;
  final int targetIndex;
  @override
  State<_InitiallyPositionedNotes> createState() => _InitiallyPositionedNotesState();
}

class _InitiallyPositionedNotesState extends State<_InitiallyPositionedNotes> {
  final _targetKey = GlobalKey();
  bool _positioned = false;
  @override
  Widget build(BuildContext context) {
    if (!_positioned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _positioned) return;
        final targetContext = _targetKey.currentContext;
        if (targetContext == null) return;
        _positioned = true;
        Scrollable.ensureVisible(targetContext, duration: Duration.zero,
            alignment: 0, alignmentPolicy: ScrollPositionAlignmentPolicy.explicit);
      });
    }
    return SingleChildScrollView(
      primary: true,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.cards.length; i++) ...[
            KeyedSubtree(
              key: i == widget.targetIndex ? _targetKey : null,
              child: widget.cards[i],
            ),
            if (i + 1 < widget.cards.length)
              const Divider(height: 1, indent: 20, endIndent: 20,
                  color: Color(0xFFEDEDED)),
          ],
        ],
      ),
    );
  }
}

// Each tab owns a controller so its scrollbar follows only that tab's list.
class _NotesScrollbar extends StatefulWidget {
  const _NotesScrollbar({super.key, required this.child});
  final Widget child;
  @override
  State<_NotesScrollbar> createState() => _NotesScrollbarState();
}

class _NotesScrollbarState extends State<_NotesScrollbar> {
  final _controller = ScrollController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => PrimaryScrollController(
    controller: _controller,
    child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: false,
        trackVisibility: false,
        scrollbarOrientation: ScrollbarOrientation.right,
        thickness: 4,
        radius: const Radius.circular(4),
        notificationPredicate: (notification) =>
        notification.depth == 0 && notification.metrics.axis == Axis.vertical,
        child: widget.child,
      ),
    ),
  );
}

// A popped route stays mounted during its exit transition. Controllers must
// live until its editor subtree is unmounted, rather than showDialog completes.
class _MemoEditorLifetime extends StatefulWidget {
  const _MemoEditorLifetime({required this.controllers, required this.child});
  final List<TextEditingController?> controllers;
  final Widget child;
  @override
  State<_MemoEditorLifetime> createState() => _MemoEditorLifetimeState();
}

class _MemoEditorLifetimeState extends State<_MemoEditorLifetime> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
