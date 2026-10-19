import 'profile_photo_dialog.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/app_config.dart';
import '../../core/room_sync_client.dart';
import '../../model/book.dart';
import '../../model/reading_room.dart';
import '../../model/shared_room_note.dart';
import '../../repository/book_repository.dart';
import '../../repository/reading_room_repository.dart';
import 'advanced_book_reader.dart';
import 'book_catalog.dart' show BookCover;
import 'ridi_store.dart';

class ReadingRoomsScreen extends StatefulWidget {
  const ReadingRoomsScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<ReadingRoomsScreen> createState() => _ReadingRoomsScreenState();
}

class _ReadingRoomsScreenState extends State<ReadingRoomsScreen> {
  late final ReadingRoomRepository _repository;
  late Future<List<ReadingRoom>> _rooms;
  List<ReadingRoom> _roomCache = const [];
  int _roomRevision = 0;
  Map<int, String?> _myRecentCovers = {};
  Map<int, int> _coverBookIds = {};
  Map<int, String> _roomOwnerNames = {};
  static const _sortPreferenceKey = 'reading_rooms_sort_by_name';
  bool _onlyAvailable = false;
  bool _sortChanged = false;

  Future<void> _restoreSort() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted || _sortChanged) return;
    setState(() => _onlyAvailable =
        preferences.getBool(_sortPreferenceKey) ?? false);
  }

  Future<void> _changeSort(bool value) async {
    _sortChanged = true;
    setState(() => _onlyAvailable = value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_sortPreferenceKey, value);
  }

  bool _joinFlowInProgress = false;
  int? _openingRoomId;

  @override
  void initState() {
    super.initState();
    _repository = ReadingRoomRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    _rooms = _loadRooms(++_roomRevision);
    unawaited(_restoreSort());
  }

  void _reload() {
    unawaited(_reloadAsync());
  }

  Future<void> _reloadAsync() async {
    if (!mounted) return;
    final revision = ++_roomRevision;
    final load = _loadRooms(revision);
    setState(() {
      _rooms = load;
    });
    await load;
  }

  Future<List<ReadingRoom>> _loadRooms(int revision) async {
    final rooms = await _repository.myRooms();
    final covers = <int, String?>{};
    final bookIds = <int, int>{};
    final ownerNames = <int, String>{};
    await Future.wait(rooms.map((room) async {
      try {
        final detail = room.books.isEmpty || room.ownerNickname == '알 수 없음'
            ? await _repository.detail(room.id) : room;
        final owner = detail.participants.where((member) =>
        member.userId == detail.ownerId ||
            member.role.toUpperCase() == 'OWNER' ||
            member.role.toUpperCase() == 'HOST').firstOrNull;
        final name = owner?.nickname.trim();
        ownerNames[room.id] = name != null && name.isNotEmpty && name != '알 수 없음'
            ? name : detail.ownerNickname;
        final fallbackId = detail.coverBook?.id ?? detail.book?.id ??
            detail.bookId ?? detail.books.firstOrNull?.book.id;
        if (fallbackId != null) bookIds[room.id] = fallbackId;
        DateTime? latest;
        for (final result in await Future.wait(detail.books.map((item) async {
          final records = await _repository.participantProgress(room.id, item.book.id);
          final mine = records.where((record) => record.currentUser).firstOrNull;
          return (item.book.coverImageUrl, mine?.updatedAt, item.book.id);
        }))) {
          final time = result.$2;
          if (time != null && (latest == null || time.isAfter(latest))) {
            latest = time;
            covers[room.id] = result.$1;
            bookIds[room.id] = result.$3;
          }
        }
      } catch (_) {
        // Keep the existing room cover if reading history is unavailable.
      }
    }));
    if (mounted && revision == _roomRevision) {
      _roomCache = List.unmodifiable(rooms);
      _myRecentCovers = covers;
      _coverBookIds = bookIds;
      _roomOwnerNames = ownerNames;
    }
    return rooms;
  }

  /// Mutations render their authoritative response immediately. A following
  /// reconciliation is deliberately revision-gated so an older GET cannot
  /// restore a just deleted room or hide a just created one.
  void _putRoom(ReadingRoom room) {
    final next = List<ReadingRoom>.unmodifiable([
      room,
      ..._roomCache.where((candidate) => candidate.id != room.id),
    ]);
    final revision = ++_roomRevision;
    setState(() {
      _roomCache = next;
      _rooms = Future.value(next);
    });
    unawaited(_reconcileRooms(revision));
  }

  void _removeRoom(int roomId) {
    final next = List<ReadingRoom>.unmodifiable(
      _roomCache.where((room) => room.id != roomId),
    );
    final revision = ++_roomRevision;
    setState(() {
      _roomCache = next;
      _rooms = Future.value(next);
    });
    unawaited(_reconcileRooms(revision));
  }

  Future<void> _reconcileRooms(int revision) async {
    try {
      final rooms = await _repository.myRooms();
      if (mounted && revision == _roomRevision) {
        setState(() {
          _roomCache = List.unmodifiable(rooms);
          _rooms = Future.value(_roomCache);
        });
      }
    } catch (_) {
      // The authoritative create/join/delete result is already visible. A
      // later pull-to-refresh exposes a transient reconciliation failure.
    }
  }

  Future<void> _readCoverBook(ReadingRoom room, int bookId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdvancedBookReaderScreen(
        bookId: bookId,
        readerContext: ReaderContext.readingRoom(room.id),
      )),
    );
    if (mounted) _reload();
  }

  Future<void> _open(ReadingRoom room) async {
    if (_openingRoomId == room.id) return;
    _openingRoomId = room.id;
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              ReadingRoomDetailScreen(repository: _repository, roomId: room.id),
        ),
      );
      // A detail route can update its books without navigating away.  Always
      // reconcile the grid when it closes so its cover/current-book metadata
      // never remains stale after an add, remove, or reorder.
      if (mounted) _reload();
    } finally {
      _openingRoomId = null;
    }
  }

  Future<void> _create() async {
    final room = await Navigator.of(context).push<ReadingRoom>(
      MaterialPageRoute(builder: (_) => const CreateReadingRoomScreen()),
    );
    if (!mounted || room == null) return;
    // The create route owns only its controllers and request.  This still
    // mounted parent owns list refresh and the next navigation exactly once.
    _putRoom(room);
    await _open(room);
  }

  Future<void> _join() async {
    if (_joinFlowInProgress) return;
    _joinFlowInProgress = true;
    try {
      final pending = await showDialog<_PendingRoomJoin>(
        context: context,
        builder: (_) => _JoinRoomByCodeDialog(repository: _repository),
      );
      if (!mounted || pending == null) return;
      // Validation does not create a membership. Only the completed profile does.
      final room = await Navigator.of(context).push<ReadingRoom>(
        MaterialPageRoute(builder: (_) => _JoinRoomProfileScreen(
          repository: _repository, pending: pending,
        )),
      );
      if (!mounted || room == null) return;
      _putRoom(room);
      await _open(room);
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      _joinFlowInProgress = false;
    }
  }

  Future<void> _deleteRoomFromList(ReadingRoom room) async {
    final confirmed = await _confirm(
      context,
      '독서방을 전체 삭제할까요?',
      '참여자와 공유 메모, 형광펜, 댓글을 포함한 이 독서방의 데이터가 삭제되며 되돌릴 수 없습니다.',
    );
    if (!confirmed || !mounted) return;
    try {
      await _repository.delete(room.id);
      if (mounted) _removeRoom(room.id);
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('교환독서'),
      actions: [
        PopupMenuButton<bool>(
          tooltip: '필터',
          onSelected: (value) => unawaited(_changeSort(value)),
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: false,
              checked: !_onlyAvailable,
              child: const Text('최신순'),
            ),
            CheckedPopupMenuItem(
              value: true,
              checked: _onlyAvailable,
              child: const Text('이름순'),
            ),
          ],
        ),
        // 위 열쇠(코드로 입장) 아이콘은 뺌 — 오른쪽 아래 [코드 참여] 버튼으로 (수정 확인 피드백)
      ],
    ),
    // 오른쪽 아래는 [코드 참여] 하나만. 방 만들기는 목록 끝 점선 [+] 칸 (방이 없을 때는 가운데 안내의 버튼)
    floatingActionButton: FloatingActionButton.extended(
      heroTag: 'room-join',
      onPressed: _join,
      icon: const Icon(Icons.key_outlined),
      label: const Text('코드 참여'),
    ),
    body: FutureBuilder<List<ReadingRoom>>(
      future: _rooms,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          // 목록을 못 불러와도 점선 [+ 방 만들기] 칸은 보이게, 위에 작은 오류 안내 + 다시 시도
          return _roomGrid(
            const [],
            notice: _ErrorNotice(error: snapshot.error, onRetry: _reload),
          );
        }
        // 필터: 최신순 전체(서버 순서 그대로) / 이름순 (필기 수정2-43)
        final rooms = [...(snapshot.data ?? const <ReadingRoom>[])];
        if (_onlyAvailable) {
          rooms.sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        }
        // 방이 없어도 점선 [+ 방 만들기] 칸 하나가 보인다
        return _roomGrid(rooms);
      },
    ),
  );

  /// 내 독서방 격자: 방 카드들 + 맨 끝 점선 [+] 칸 = 방 만들기 (필기 수정2-42).
  /// notice = 목록을 못 불러왔을 때 위에 보이는 작은 안내.
  Widget _roomGrid(
      List<ReadingRoom> rooms, {
        Widget? notice,
      }) => RefreshIndicator(
    onRefresh: _reloadAsync,
    child: CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Text('내 독서방', style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        if (notice != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            sliver: SliverToBoxAdapter(child: notice),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 160),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              mainAxisExtent: 350,
            ),
            itemCount: rooms.length + 1,
            itemBuilder: (context, index) {
              if (index == rooms.length) return _AddRoomTile(onTap: _create);
              final room = rooms[index];
              return _RoomTile(
                room: room,
                recentCoverUrl: _myRecentCovers[room.id],
                ownerName: _roomOwnerNames[room.id],
                onRead: _coverBookIds[room.id] == null ? null
                    : () => _readCoverBook(room, _coverBookIds[room.id]!),
                onTap: () => _open(room),
                onDelete: room.isOwner ? () => _deleteRoomFromList(room) : null,
              );
            },
          ),
        ),
      ],
    ),
  );
}

/// 독서방 표지와 정보를 위아래로 나누어 표시한다.
class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.onTap, this.onDelete, this.recentCoverUrl, this.onRead, this.ownerName});
  final String? recentCoverUrl;
  final String? ownerName;
  final VoidCallback? onRead;
  final ReadingRoom room;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFE3E6EE)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ColoredBox(
              color: const Color(0xFFF1F3F8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTap,
                      child: _RoomCoverImage(room: room, fit: BoxFit.contain, overrideUrl: recentCoverUrl),
                    ),
                  ),

                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Text(room.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800, color: Colors.black),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${ownerName ?? room.ownerNickname} · ${room.members}/${room.maxMembers}명',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF777777)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: onRead,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('이어읽기 >'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _RoomCoverImage extends StatelessWidget {
  const _RoomCoverImage({required this.room, this.fit = BoxFit.cover, this.overrideUrl});
  final String? overrideUrl;
  final ReadingRoom room;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final book = room.coverBook ?? room.book;
    final rawUrl = overrideUrl?.trim().isNotEmpty == true
        ? overrideUrl!.trim()
        : room.coverImageUrl?.trim().isNotEmpty == true
        ? room.coverImageUrl!.trim()
        : book?.coverImageUrl?.trim();
    Widget fallback = const ColoredBox(
      color: Color(0xFFF1F3F8),
      child: Center(
        child: Icon(
          Icons.menu_book_rounded,
          size: 48,
          color: Color(0xFF9AA3B5),
        ),
      ),
    );
    if (rawUrl == null || rawUrl.isEmpty) return fallback;
    final url = rawUrl.startsWith('http')
        ? rawUrl
        : '${AppConfig.baseUrl}${rawUrl.startsWith('/') ? '' : '/'}$rawUrl';
    return Semantics(
      image: true,
      label: '${room.name} 방 커버',
      child: Image.network(
        url,
        fit: fit,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, loading) => loading == null
            ? child
            : Stack(
          fit: StackFit.expand,
          children: [
            fallback,
            const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

/// 점선 [+] 칸 — 누르면 방 만들기
class _AddRoomTile extends StatelessWidget {
  const _AddRoomTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: CustomPaint(
      painter: _DashedRRect(),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 40, color: Color(0xFF9AA3B5)),
            SizedBox(height: 6),
            Text('방 만들기', style: TextStyle(color: Color(0xFF8A8A8A))),
          ],
        ),
      ),
    ),
  );
}

class _DashedRRect extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB8BFCC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      );
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 12) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A route, rather than a dialog over the room list, deliberately owns the
/// room-create form lifecycle.  No parent Provider is re-provided or disposed.
/// 독서방 만들기 (사용자 그림, 2026-10-06):
/// - 위: 제목 "독서방 만들기" + 오른쪽 [만들기]
/// - 왼쪽: 방 이름 · 방 소개 · 함께 읽을 책(목록에서 여러 권 고르기)
/// - 오른쪽: 프로필 설정(이 방 사진 · 별명) · 참여 인원 [−][+] 2~50 · 비밀번호 설정(숫자 4자리)
/// - 아래: 함께 읽을 책 — 고른 책 표지
/// 입장 방식 · 스포일러 잠금 · AI 독서 친구는 뺐다 (기본값: 공개, 잠금 끔, AI 없음).
/// ※ 서버 연결 메모(백엔드 팀이 이어서): 지금 서버는 책 1권(bookId)·인원 2~10·비밀번호 없음.
///   화면은 bookIds(여러 권)·password 도 함께 보내고, bookId 에는 첫 권을 넣는다.
class CreateReadingRoomScreen extends StatefulWidget {
  const CreateReadingRoomScreen({super.key});

  @override
  State<CreateReadingRoomScreen> createState() =>
      _CreateReadingRoomScreenState();
}

class _CreateReadingRoomScreenState extends State<CreateReadingRoomScreen> {
  static const _minMembers = 2;
  static const _maxMembersLimit = 50;

  final _name = TextEditingController();
  final _description = TextEditingController();
  final _nickname = TextEditingController();
  final _bookSearch = TextEditingController();
  String _bookQuery = "";
  late final ReadingRoomRepository _repository;
  late Future<List<Book>> _books;
  final List<Book> _picked = [];
  int _maxMembers = 6;
  Uint8List? _imageBytes;
  String? _imageName;
  String? _imageType;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final nickname = context.read<RidiStore>().nickname;
    _nickname.value = TextEditingValue(
      text: nickname,
      selection: TextSelection.collapsed(offset: nickname.length),
    );
    _repository = ReadingRoomRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    _loadBooks();
  }

  void _loadBooks() {
    _books = BookRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    ).books();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _nickname.dispose();
    _bookSearch.dispose();
    super.dispose();
  }

  void _toggleBook(Book b) => setState(() {
    final i = _picked.indexWhere((x) => x.id == b.id);
    if (i >= 0) {
      _picked.removeAt(i);
    } else {
      _picked.add(b);
    }
    _error = null;
  });

  Future<void> _pickImage() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (image == null) return;
      final ext = image.name.split('.').last.toLowerCase();
      final bytes = await image.readAsBytes();
      if (!RegExp(r'^(jpe?g|png|webp)$').hasMatch(ext) ||
          bytes.length > 5 * 1024 * 1024) {
        if (mounted)
          setState(() => _error = 'JPG, PNG, WEBP 형식의 5MB 이하 이미지만 선택할 수 있습니다.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageName = image.name;
        _imageType =
            image.mimeType ??
                switch (ext) {
                  'png' => 'image/png',
                  'webp' => 'image/webp',
                  _ => 'image/jpeg',
                };
      });
    } catch (_) {
      if (mounted) setState(() => _error = '사진을 불러오지 못했습니다.');
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final err = _name.text.trim().isEmpty
        ? '방 이름을 입력해주세요.'
        : _picked.isEmpty
        ? '함께 읽을 책을 골라주세요.'
        : null;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      var room = await _repository.create({
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'bookId': _picked.first.id,
        'bookIds': _picked.map((book) => book.id).toList(),
        'maxMembers': _maxMembers,
        'isPublic': true,
        'spoilerLockEnabled': false,
        'selectedAiFriendType': null,
        'roomNickname': _nickname.text.trim(),
      });
      if (_imageBytes != null) {
        try {
          room = await _repository.uploadMyRoomProfileImage(
            room.id,
            bytes: _imageBytes!,
            filename: _imageName ?? 'profile.jpg',
            contentType: _imageType ?? 'image/jpeg',
          );
        } catch (_) {
          // 사진은 방 상세의 "방 프로필 사진 변경"에서 다시 올릴 수 있다
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(room);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = _roomErrorMessage(error));
    } catch (_) {
      if (mounted) {
        setState(() => _error = '방을 만드는 중 문제가 발생했습니다. 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------- 모양 ----------
  static const _label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Color(0xFF222222),
  );
  static const _hint = TextStyle(fontSize: 12, color: Color(0xFF9E9E9E));

  Widget _title(String t, [String? sub]) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(t, style: _label),
        if (sub != null) ...[const SizedBox(width: 8), Text(sub, style: _hint)],
      ],
    ),
  );

  InputDecoration _box(String hint) => InputDecoration(
    hintText: hint,
    counterText: '',
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
    ),
  );

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFE6E6E6)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );

  /// 왼쪽: 방 이름 · 방 소개. wide 면 방 소개 칸이 오른쪽 칸 높이만큼 늘어난다(IntrinsicHeight).
  Widget _left({required bool fill}) {
    final description = TextField(
      controller: _description,
      enabled: !_submitting,
      maxLength: 500,
      expands: fill,
      minLines: fill ? null : 4,
      maxLines: fill ? null : 6,
      textAlignVertical: TextAlignVertical.top,
      decoration: _box('이 방을 한두 줄로 소개해 주세요'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('방 이름'),
        TextField(
          controller: _name,
          enabled: !_submitting,
          maxLength: 100,
          onChanged: (_) => setState(() => _error = null),
          style: const TextStyle(fontSize: 16),
          decoration: _box('예: 목요일 밤 독서회'),
        ),
        const SizedBox(height: 20),
        _title('방 소개', '선택'),
        if (fill) Expanded(child: description) else description,
      ],
    );
  }

  Widget _right() {
    final defaultPhoto = context.read<RidiStore>().profileImageUrl;
    final hasDefaultPhoto = defaultPhoto?.trim().isNotEmpty == true;
    final initial =
        (_nickname.text.trim().isNotEmpty
            ? _nickname.text.trim()
            : context.read<RidiStore>().nickname)
            .characters
            .firstOrNull ??
            '?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('프로필 설정', '이 방에서 보일 사진 · 이름'),
        _panel(
          Row(
            children: [
              InkWell(
                onTap: _submitting ? null : _pickImage,
                customBorder: const CircleBorder(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFFEFF1F5),
                      backgroundImage: _imageBytes != null
                          ? MemoryImage(_imageBytes!)
                          : hasDefaultPhoto ? NetworkImage(_repository.absoluteUrl(defaultPhoto!)) : null,
                      child: _imageBytes == null && !hasDefaultPhoto
                          ? Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF555555),
                        ),
                      )
                          : null,
                    ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFDDDDDD)),
                        ),
                        child: const Icon(
                          Icons.edit,
                          size: 12,
                          color: Color(0xFF555555),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _nickname,
                  enabled: !_submitting,
                  maxLength: 40,
                  onChanged: (_) => setState(() {}),
                  decoration: _box('이 방에서 사용할 이름'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _title('참여 인원', '$_minMembers~$_maxMembersLimit명'),
        _panel(
          Row(
            children: [
              const Text('최대', style: TextStyle(fontSize: 14)),
              const Spacer(),
              _stepBtn(
                Icons.remove,
                _maxMembers > _minMembers
                    ? () => setState(() => _maxMembers--)
                    : null,
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '$_maxMembers명',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _stepBtn(
                Icons.add,
                _maxMembers < _maxMembersLimit
                    ? () => setState(() => _maxMembers++)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) => InkWell(
    onTap: _submitting ? null : onTap,
    customBorder: const CircleBorder(),
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: onTap == null
              ? const Color(0xFFE0E0E0)
              : const Color(0xFFBBBBBB),
        ),
      ),
      child: Icon(
        icon,
        size: 18,
        color: onTap == null
            ? const Color(0xFFCCCCCC)
            : const Color(0xFF333333),
      ),
    ),
  );

  /// 아래: 함께 읽을 수 있는 책 표지를 가로로 — 눌러서 체크(여러 권)
  Widget _bookPickerHeader() => LayoutBuilder(
    builder: (context, constraints) {
      final title = _title(
        '함께 읽을 책',
        _picked.isEmpty ? null : '${_picked.length}권 선택',
      );
      final search = SizedBox(
        height: 44,
        child: TextField(
          controller: _bookSearch,
          enabled: !_submitting,
          onChanged: (value) => setState(() => _bookQuery = value),
          style: const TextStyle(fontSize: 14),
          decoration: _box('책 제목 또는 저자 검색').copyWith(
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _bookQuery.isEmpty
                ? null
                : IconButton(
              tooltip: '검색 초기화',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                _bookSearch.clear();
                setState(() => _bookQuery = '');
              },
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      );
      if (constraints.maxWidth < 560) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [title, search, const SizedBox(height: 12)],
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 16),
            SizedBox(width: 300, child: search),
          ],
        ),
      );
    },
  );

  Widget _bookPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _bookPickerHeader(),
      _panel(
        FutureBuilder<List<Book>>(
          future: _books,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 212,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return SizedBox(
                height: 212,
                child: Center(
                  child: TextButton(
                    onPressed: () => setState(_loadBooks),
                    child: const Text('책 목록을 불러오지 못했습니다. 다시 시도'),
                  ),
                ),
              );
            }
            final allBooks = snap.data ?? const <Book>[];
            final query = _bookQuery.trim().toLowerCase();
            final books = allBooks.where((book) {
              return query.isEmpty ||
                  book.title.toLowerCase().contains(query) ||
                  (book.author ?? '').toLowerCase().contains(query);
            }).toList();
            if (books.isEmpty) {
              return SizedBox(
                height: 212,
                child: Center(
                  child: Text(
                    allBooks.isEmpty
                        ? '함께 읽을 수 있는 책이 없어요'
                        : '검색 결과가 없어요',
                    style: _hint,
                  ),
                ),
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 190).floor().clamp(
                  1,
                  5,
                );
                return GridView.builder(
                  key: const PageStorageKey('reading-room-book-picker'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 24,
                    crossAxisSpacing: 24,
                    mainAxisExtent: 290,
                  ),
                  itemCount: books.length,
                  itemBuilder: (_, i) => Align(
                    alignment: Alignment.topCenter,
                    child: _BookPickCover(
                      book: books[i],
                      selected: _picked.any((x) => x.id == books[i].id),
                      onTap: _submitting ? null : () => _toggleBook(books[i]),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('독서방 만들기'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _submitting
                ? const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
                : TextButton(
              onPressed: _submit,
              child: const Text(
                '만들기',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 900;
            final error = _error == null
                ? const SizedBox.shrink()
                : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                error,
                if (wide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 11, child: _left(fill: true)),
                        const SizedBox(width: 32),
                        Expanded(flex: 9, child: _right()),
                      ],
                    ),
                  )
                else ...[
                  _left(fill: false),
                  const SizedBox(height: 24),
                  _right(),
                ],
                const SizedBox(height: 24),
                _bookPicker(),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// 함께 읽을 책 표지 한 칸 — 누르면 체크(파란 테두리 + 오른쪽 위 체크), 아래 제목 · 저자
class _BookPickCover extends StatelessWidget {
  const _BookPickCover({
    required this.book,
    required this.selected,
    this.onTap,
  });
  final Book book;
  final bool selected;
  final VoidCallback? onTap;
  static const _blue = Color(0xFF1E88E5);
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: 166,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected ? _blue : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: Opacity(
                  opacity: selected ? 1 : .92,
                  child: BookCover(
                    url: book.coverImageUrl,
                    width: 160,
                    height: 230,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? _blue
                        : Colors.white.withValues(alpha: .9),
                    border: Border.all(
                      color: selected ? _blue : const Color(0xFFBBBBBB),
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 17, color: Colors.white)
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: selected ? _blue : const Color(0xFF222222),
            ),
          ),
          Text(
            book.author ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
          ),
        ],
      ),
    ),
  );
}

/// 코드 입력과 요청 중 상태는 이 다이얼로그가 소유한다. 취소는 null을 반환하는
/// 정상 흐름이며, API 성공일 때만 방 정보를 부모 화면으로 돌려준다.
class _PendingRoomJoin {
  const _PendingRoomJoin({required this.validation, required this.code, required this.password});
  final InviteCodeValidation validation;
  final String code;
  final String password;
}

class _JoinRoomByCodeDialog extends StatefulWidget {
  const _JoinRoomByCodeDialog({required this.repository});

  final ReadingRoomRepository repository;

  @override
  State<_JoinRoomByCodeDialog> createState() => _JoinRoomByCodeDialogState();
}

class _JoinRoomByCodeDialogState extends State<_JoinRoomByCodeDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _joining = false;
  String? _error;
  InviteCodeValidation? _validated;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = ReadingRoomRepository.normalizeInviteCode(_code.text);
    if (code.isEmpty) {
      setState(() => _error = '입장 코드를 입력해주세요.');
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final validation =
          _validated ?? await widget.repository.validateInviteCode(code);
      if (!mounted) return;
      if (validation.alreadyJoined) {
        setState(() => _error = '이미 참여 중인 방입니다.');
        return;
      }
      if (validation.currentMemberCount >= validation.capacity) {
        setState(() => _error = '방 정원이 가득 찼습니다.');
        return;
      }
      if (validation.passwordRequired && _password.text.isEmpty) {
        setState(() => _validated = validation);
        return;
      }
      Navigator.of(context).pop(_PendingRoomJoin(
        validation: validation,
        code: code,
        password: _password.text,
      ));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = _roomJoinErrorMessage(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = '방 입장 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
      });
    } finally {
      if (mounted && _joining) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_joining,
    child: AlertDialog(
      title: const Text('코드로 방 입장'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('방장에게 받은 입장 코드를 입력하세요.'),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autofocus: true,
            enabled: !_joining,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _joining ? null : _submit(),
            onChanged: (_) => setState(() { _validated = null; _error = null; }),
            decoration: const InputDecoration(hintText: '입장 코드 입력'),
          ),
          if (_validated?.passwordRequired == true) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              autofocus: true,
              enabled: !_joining,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _joining ? null : _submit(),
              decoration: const InputDecoration(hintText: '방 비밀번호 입력'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _joining ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _joining ? null : _submit,
          child: _joining
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Text('입장'),
        ),
      ],
    ),
  );
}

String _roomJoinErrorMessage(ApiException error) {
  switch (error.errorCode) {
    case 'INVALID_INVITE_CODE':
    case 'ROOM_NOT_FOUND':
    case 'ROOM_CODE_REQUIRED':
      return '입장 코드를 확인해주세요.';
    case 'ROOM_NOT_JOINABLE':
    case 'ROOM_ACCESS_DENIED':
    case 'PRIVATE_ROOM_CODE_REQUIRED':
      return '참여할 수 없는 독서방입니다.';
    case 'ALREADY_ROOM_MEMBER':
    case 'ALREADY_JOINED':
      return '이미 참여 중인 독서방입니다.';
    case 'ROOM_CAPACITY_REACHED':
    case 'ROOM_FULL':
      return '독서방 정원이 가득 찼습니다.';
    case 'ROOM_PASSWORD_REQUIRED':
    case 'ROOM_PASSWORD_INCORRECT':
      return '방 비밀번호가 올바르지 않습니다.';
  }
  if (error.statusCode == 401) return '로그인이 만료되었습니다. 다시 로그인해주세요.';
  if (error.statusCode == 403) return '이 독서방에 입장할 권한이 없습니다.';
  if (error.statusCode == null) return '네트워크 연결을 확인한 뒤 다시 시도해주세요.';
  return '방 입장 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
}

class ReadingRoomDetailScreen extends StatefulWidget {
  const ReadingRoomDetailScreen({
    super.key,
    required this.repository,
    required this.roomId,
  });
  final ReadingRoomRepository repository;
  final int roomId;
  @override
  State<ReadingRoomDetailScreen> createState() =>
      _ReadingRoomDetailScreenState();
}

class _ReadingRoomDetailScreenState extends State<ReadingRoomDetailScreen> {
  late Future<ReadingRoom> _room;
  late Future<List<ReadingRoomBookItem>> _recentBooks;
  ReadingRoom? _visibleRoom;
  int _readerReturnRevision = 0;
  RoomSyncClient? _roomSync;
  bool _deleting = false;
  bool _bookMutationInFlight = false;
  bool _updatingProfileImage = false;
  bool _updatingCoverImage = false;
  bool _regeneratingCode = false;
  bool _updatingMemberLimit = false;
  bool _savingMemberColor = false;
  final ImagePicker _imagePicker = ImagePicker();
  @override
  void initState() {
    super.initState();
    _loadRoom(rebuild: false);
    _roomSync = RoomSyncClient(
      repository: widget.repository,
      baseUrl: AppConfig.baseUrl,
      token: context.read<RidiStore>().accessToken,
      roomId: widget.roomId,
      onChanged: _reload,
    )..start();
  }

  @override
  void dispose() {
    _roomSync?.dispose();
    super.dispose();
  }

  static const _memoColors = ['#FFF59D','#F8BBD0','#A5D6A7','#90CAF9','#CE93D8',
    '#FFCC80','#EF9A9A','#80CBC4','#B3E5FC','#BDBDBD'];

  Color _memberMemoColor(String value) {
    final hex = value.replaceFirst('#', '');
    return Color(0xFF000000 | (int.tryParse(hex, radix: 16) ?? 0xFFF59D));
  }

  Future<void> _chooseMyMemoColor(ReadingRoom room, ReadingRoomMember member) async {
    if (!member.currentUser || _savingMemberColor) return;
    final color = await showDialog<String>(context: context,
        barrierColor: Colors.transparent,
        builder: (dialogContext) => AlertDialog(
          title: const Text('메모 색상'),
          content: SizedBox(width: 300, child: Wrap(spacing: 12, runSpacing: 16,
            children: _memoColors.map((value) => InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => Navigator.pop(dialogContext, value),
              child: Container(width: 44,height: 44,
                decoration: BoxDecoration(color: _memberMemoColor(value),shape: BoxShape.circle,
                    border: Border.all(color: Colors.black26)),
                child: value == member.memoHighlightColor.toUpperCase()
                    ? const Icon(Icons.check,size: 22) : null,
              ),
            )).toList(),
          )),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),child: const Text('취소'))],
        ));
    if (color == null || !mounted) return;
    setState(() => _savingMemberColor = true);
    try {
      await widget.repository.updateMyMemoColor(room.id, color);
      if (mounted) _reload();
    } on ApiException catch (error) {
      if (mounted) _showError(context,error);
    } finally {
      if (mounted) setState(() => _savingMemberColor = false);
    }
  }

  void _reload() {
    _loadRoom();
  }

  void _loadRoom({bool rebuild = true}) {
    final future = widget.repository.detail(widget.roomId);
    _recentBooks = future.then(_sortBooksByMyReading);
    if (rebuild && mounted) {
      setState(() => _room = future);
    } else {
      _room = future;
    }
    unawaited(
      future.then((room) {
        if (mounted && identical(_room, future)) {
          setState(() => _visibleRoom = room);
        }
      }).catchError((Object _) {}),
    );
  }

  // Book-management endpoints return the fully updated room.  Keep that
  // response as the visible state immediately instead of waiting for a second
  // network request to finish, so add/remove/current-book changes cannot look
  // stale on the detail screen.
  void _applyRoom(ReadingRoom room) {
    if (!mounted) return;
    setState(() {
      _visibleRoom = room;
      _room = Future<ReadingRoom>.value(room);
      _recentBooks = _sortBooksByMyReading(room);
    });
  }

  /// A profile write can affect every room surface (member list, progress and
  /// note author labels).  Paint the successful mutation immediately, then
  /// fetch the canonical room once so no stale response/cache can remain on
  /// this screen.  A failed refresh must not hide an already successful edit.
  Future<void> _applyAndRefreshProfileRoom(ReadingRoom updated) async {
    _applyRoom(updated);
    try {
      final canonical = await widget.repository.detail(widget.roomId);
      if (mounted) _applyRoom(canonical);
    } on ApiException {
      // The mutation response is still authoritative when a follow-up read
      // temporarily fails (for example while a connection is changing).
    }
  }

  Future<void> _editMyRoomProfileImage(ReadingRoomMember mine) async {
    if (_updatingProfileImage) return;
    setState(() => _updatingProfileImage = true);
    try {
      await showProfilePhotoDialog(context, name: mine.nickname,
          imageUrl: mine.roomProfileImageUrl?.isNotEmpty == true
              ? widget.repository.absoluteUrl(mine.roomProfileImageUrl!) : null,
          onSave: (selection) async {
            final updated = selection.remove
                ? await widget.repository.deleteMyRoomProfileImage(widget.roomId)
                : await widget.repository.uploadMyRoomProfileImage(widget.roomId,
                bytes: selection.bytes!, filename: selection.filename!,
                contentType: selection.contentType!);
            await _applyAndRefreshProfileRoom(updated);
          });
    } finally { if (mounted) setState(() => _updatingProfileImage = false); }
  }

  Future<void> _editCoverImage() async {
    if (_updatingCoverImage) return;
    final action = await showModalBottomSheet<_RoomCoverImageAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('방 커버 이미지 선택'),
              onTap: () =>
                  Navigator.pop(sheetContext, _RoomCoverImageAction.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('방 커버 이미지 삭제'),
              textColor: Colors.red,
              iconColor: Colors.red,
              onTap: () =>
                  Navigator.pop(sheetContext, _RoomCoverImageAction.remove),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() => _updatingCoverImage = true);
    try {
      if (action == _RoomCoverImageAction.remove) {
        await widget.repository.deleteCoverImage(widget.roomId);
      } else {
        final image = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          imageQuality: 85,
        );
        if (image == null) return;
        final extension = image.name.split('.').last.toLowerCase();
        final bytes = await image.readAsBytes();
        if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension) ||
            bytes.length > 5 * 1024 * 1024) {
          throw ApiException('JPG, PNG, WEBP 형식의 5MB 이하 이미지만 선택할 수 있습니다.');
        }
        final updated = await widget.repository.uploadCoverImage(
          widget.roomId,
          bytes: bytes,
          filename: image.name,
          contentType:
          image.mimeType ??
              (extension == 'png'
                  ? 'image/png'
                  : extension == 'webp'
                  ? 'image/webp'
                  : 'image/jpeg'),
        );
        if (mounted) _applyRoom(updated);
        return;
      }
      if (mounted) _reload();
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _updatingCoverImage = false);
    }
  }

  Future<void> _leave(ReadingRoom room) async {
    final confirmed = await _confirm(
      context,
      '방을 나갈까요?',
      room.isOwner
          ? '방장이라면 가장 먼저 참여한 멤버에게 방장이 위임됩니다. 혼자라면 방이 삭제됩니다.'
          : '나가도 입장 코드가 있으면 다시 참여할 수 있습니다.',
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.repository.leave(room.id);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _delete(ReadingRoom room) async {
    if (_deleting ||
        !await _confirm(
          context,
          '독서방을 삭제할까요?',
          '방을 삭제하면 참여자, 공유 메모, 공유 형광펜, 댓글 등 이 방과 관련된 데이터는 더 이상 사용할 수 없습니다. 이 작업은 되돌릴 수 없습니다.',
        ) ||
        !mounted)
      return;
    setState(() => _deleting = true);
    try {
      await widget.repository.delete(room.id);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _editRoomName(ReadingRoom room) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RoomNameDialog(initial: room.name),
    );
    if (name == null || name.isEmpty || name == room.name || !mounted) return;
    try {
      final updated = await widget.repository.update(room.id, {
        'name': name,
        'description': room.description,
        'bookId': room.bookId,
        'maxMembers': room.maxMembers,
        'isPublic': room.isPublic,
        'spoilerLockEnabled': room.spoilerLockEnabled,
        'selectedAiFriendType': room.selectedAiFriendType,
      });
      if (mounted) _applyRoom(updated);
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _editRoomDescription(ReadingRoom room) async {
    final description = await showDialog<String>(
      context: context,
      builder: (_) => _RoomDescriptionDialog(initial: room.description ?? ''),
    );
    if (description == null || description == (room.description ?? '') || !mounted) return;
    try {
      final updated = await widget.repository.update(room.id, {
        'name': room.name,
        'description': description,
        'bookId': room.bookId,
        'maxMembers': room.maxMembers,
        'isPublic': room.isPublic,
        'spoilerLockEnabled': room.spoilerLockEnabled,
        'selectedAiFriendType': room.selectedAiFriendType,
      });
      if (mounted) _applyRoom(updated);
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _edit(ReadingRoom room) async {
    final body = await showRoomEditor(context, room: room);
    if (body == null || !mounted) return;
    try {
      final updated = await widget.repository.update(room.id, body);
      if (mounted) _applyRoom(updated);
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  // ---------------- 방 상세 (사용자 그림, 2026-10-06) ----------------
  // 위: ‹ 방 이름 ✎(방장) · 톱니(방장만: 방 정보 수정·코드 재발급·방 삭제) · [방 나가기]
  // 왼쪽: 방 소개(✎ 방장만) + 방 코드 복사 / 멤버 N명 (방장은 다른 멤버 [내보내기], 내 줄을 누르면 이 방 프로필 사진)
  // 오른쪽: 함께 읽는 책 N권 [+ 책 추가] — 책 카드(표지 · 제목 · 저자 · 함께 읽는 중 진행 막대 · [이어읽기 ›])
  // 왼쪽 아래: 이 방에서의 내 프로필(사진 · 방 닉네임 ✎). 멤버 "관리" 버튼은 뺐다.
  // ※ 서버 연결 메모(백엔드 팀이 이어서): 방 책은 지금 1권(bookId), 멤버별 읽은 위치 API 가 없어
  //   진행 막대에는 내 위치만 표시한다. [+ 책 추가]는 서버 기능이 생기면 연결.

  static const _ink = Color(0xFF222222);
  static const _gray = Color(0xFF9E9E9E);

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFECECEC)),
    ),
    child: child,
  );

  Widget _avatar(ReadingRoomMember m, {double r = 20}) => CircleAvatar(
    radius: r,
    backgroundColor: const Color(0xFFE9EEF5),
    foregroundImage: m.roomProfileImageUrl?.isNotEmpty == true
        ? NetworkImage(widget.repository.absoluteUrl(m.roomProfileImageUrl!))
        : null,
    child: Text(
      m.nickname.isEmpty ? '?' : m.nickname.characters.first,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: Color(0xFF4A5568),
      ),
    ),
  );

  Future<void> _copyCode(String code) async {
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('방 코드를 복사했어요.')));
      }
    } catch (_) {
      if (mounted) _showError(context, ApiException('초대 코드를 복사하지 못했습니다.'));
    }
  }

  Future<void> _regenerate(ReadingRoom room) async {
    if (_regeneratingCode || !room.isOwner) return;
    setState(() => _regeneratingCode = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('방 코드를 재발급하시겠습니까?'),
          content: const Text('재발급하면 기존 방 코드는 더 이상 사용할 수 없습니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('재발급'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final updated = await widget.repository.regenerateInviteCode(room.id);
      if (!mounted) return;
      _applyRoom(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('방 코드를 재발급했습니다.')),
      );
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _regeneratingCode = false);
    }
  }

  /// 톱니(방장만) — 방 정보 수정(이름·소개·인원 등) · 초대 코드 재발급 · 방 삭제
  Future<void> _ownerMenu(ReadingRoom room) async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('방 설정 (이름 · 소개 · 인원 · 비밀번호)'),
              onTap: () => Navigator.pop(sheet, 'edit'),
            ),
            if (room.joinCode != null)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('초대 코드 재발급'),
                onTap: () => Navigator.pop(sheet, 'code'),
              ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('방 커버 이미지 변경'),
              onTap: () => Navigator.pop(sheet, 'cover'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('방 삭제', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (pick) {
      case 'edit':
        await _edit(room);
      case 'code':
        await _regenerate(room);
      case 'cover':
        await _editCoverImage();
      case 'delete':
        await _delete(room);
    }
  }

  Future<void> _kick(ReadingRoom room, ReadingRoomMember member) async {
    if (!await _confirm(
      context,
      '${member.nickname}님을 내보낼까요?',
      '이 작업은 되돌릴 수 없습니다.',
    ))
      return;
    try {
      await widget.repository.kick(room.id, member.userId);
      _reload();
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _openBook(ReadingRoom room, int bookId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdvancedBookReaderScreen(
          bookId: bookId,
          readerContext: ReaderContext.readingRoom(room.id),
        ),
      ),
    );
    if (!mounted) return;
    // The card owns a separate participant-progress future. Invalidate it on
    // every reader return, even while the room-detail request is still loading.
    setState(() => _readerReturnRevision++);
    _reload();
  }

  Future<List<ReadingRoomBookItem>> _sortBooksByMyReading(ReadingRoom room) async {
    final items = [...room.books];
    if (!room.joined || items.length < 2) return items;
    final lastRead = <int, DateTime?>{};
    try {
      await Future.wait(items.map((item) async {
        final records = await widget.repository.participantProgress(room.id, item.book.id);
        for (final record in records) {
          if (record.currentUser) {
            lastRead[item.book.id] = record.updatedAt;
            break;
          }
        }
      }));
    } catch (_) {
      return items;
    }
    final originalOrder = <int, int>{
      for (var i = 0; i < items.length; i++) items[i].book.id: i,
    };
    items.sort((a, b) {
      final aTime = lastRead[a.book.id];
      final bTime = lastRead[b.book.id];
      if (aTime != null && bTime != null) {
        final comparison = bTime.compareTo(aTime);
        if (comparison != 0) return comparison;
      } else if (aTime != null) {
        return -1;
      } else if (bTime != null) {
        return 1;
      }
      return originalOrder[a.book.id]!.compareTo(originalOrder[b.book.id]!);
    });
    return items;
  }

  Widget _introCard(ReadingRoom room) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '방 소개',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F7F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  room.description?.isNotEmpty == true
                      ? room.description!
                      : '아직 방 소개가 없어요.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: room.description?.isNotEmpty == true
                        ? const Color(0xFF555555)
                        : _gray,
                  ),
                ),
              ),
              if (room.isOwner)
                IconButton(
                  tooltip: '방 소개 수정',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: Color(0xFF666666),
                  ),
                  onPressed: () => _editRoomDescription(room),
                ),
            ],
          ),
        ),
        if (room.joinCode != null) ...[
          const SizedBox(height: 14),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              const Text('방 코드', style: TextStyle(fontSize: 13, color: _gray)),
              InkWell(
                onTap: () => _copyCode(room.joinCode!),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        room.joinCode!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.copy_outlined,
                        size: 15,
                        color: Color(0xFF666666),
                      ),
                    ],
                  ),
                ),
              ),
              if (room.isOwner)
                IconButton(
                  tooltip: '방 코드 재발급',
                  visualDensity: VisualDensity.compact,
                  onPressed: _regeneratingCode ? null : () => _regenerate(room),
                  icon: _regeneratingCode
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.refresh, size: 20, color: _gray),
                ),
            ],
          ),
        ],
      ],
    ),
  );

  Future<void> _editMemberLimit(ReadingRoom room) async {
    if (!room.isOwner || _updatingMemberLimit) return;
    setState(() => _updatingMemberLimit = true);
    try {
      final minimum = room.participants.length.clamp(2, 50).toInt();
      var maximum = room.maxMembers.clamp(minimum, 50).toInt();
      final selected = await showDialog<int>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('참여 인원 설정'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('현재 멤버 ${room.participants.length}명 · 최대 50명'),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '인원 줄이기',
                      onPressed: maximum > minimum
                          ? () => setDialogState(() => maximum--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(
                        '$maximum명',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: '인원 늘리기',
                      onPressed: maximum < 50
                          ? () => setDialogState(() => maximum++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('현재 멤버 수보다 적게 설정할 수 없습니다.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, maximum),
                child: const Text('저장'),
              ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;
      final latest = await widget.repository.detail(room.id);
      if (!mounted) return;
      if (!latest.isOwner) {
        _applyRoom(latest);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('방장만 참여 인원을 설정할 수 있습니다.')),
        );
        return;
      }
      if (selected < latest.participants.length) {
        _applyRoom(latest);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('멤버 수가 변경되었습니다. 현재 멤버 수 이상으로 설정해주세요.')),
        );
        return;
      }
      final updated = await widget.repository.update(room.id, {
        'name': latest.name,
        'description': latest.description,
        'bookId': latest.bookId,
        'maxMembers': selected,
        'isPublic': latest.isPublic,
        'spoilerLockEnabled': latest.spoilerLockEnabled,
        'selectedAiFriendType': latest.selectedAiFriendType,
      });
      if (mounted) _applyRoom(updated);
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _updatingMemberLimit = false);
    }
  }

  Widget _membersCard(ReadingRoom room) {
    final me = context.read<RidiStore>().nickname;
    final members = room.participants;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '멤버',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${members.length} / ${room.maxMembers}명',
                style: const TextStyle(fontSize: 14, color: _gray),
              ),
              const Spacer(),
              if (room.isOwner)
                TextButton(
                  onPressed: _updatingMemberLimit ? null : () => _editMemberLimit(room),
                  child: const Text('인원 설정'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final m in members)
            SizedBox(
              width: double.infinity, // 줄을 카드 끝까지 → [내보내기]가 오른쪽 끝에 붙는다
              child: InkWell(
                onTap: null,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      _avatar(m),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          children: [
                            if (m.currentUser) ...[
                              Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF505761),
                                  shape: BoxShape.circle,
                                ),
                                child: const Text('나', style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                )),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                m.nickname,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (m.role == 'OWNER') ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF1D6),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  '방장',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFB7791F),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (room.isOwner && m.role != 'OWNER')
                        TextButton(
                          onPressed: () => _kick(room, m),
                          child: const Text('내보내기'),
                        ),
                      Tooltip(
                        message: m.currentUser ? '내 메모 색상 변경' : '${m.nickname}님의 메모 색상',
                        child: InkWell(
                          onTap: m.currentUser && !_savingMemberColor
                              ? () => _chooseMyMemoColor(room,m) : null,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(padding: const EdgeInsets.all(10),
                            child: Container(width: 20,height: 20,
                                decoration: BoxDecoration(color: _memberMemoColor(m.memoHighlightColor),
                                    shape: BoxShape.circle,border: Border.all(color: Colors.black26))),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 이 방에서의 내 프로필 — 큰 사진(누르면 사진 바꾸기) · 방 닉네임 ✎ · 안내 한 줄
  // ※ 서버 연결 메모: 방 닉네임 바꾸기 API 가 아직 없다 → ✎ 는 입력창까지만, 저장은 백엔드 팀이 연결.
  Widget _myProfileCard(ReadingRoom room) {
    final me = context.read<RidiStore>().nickname;
    final mine =
        room.participants.where((m) => m.currentUser).firstOrNull ??
            ReadingRoomMember(
              userId: 0,
              nickname: me,
              role: room.myRole ?? 'MEMBER',
            );
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '이 방에서의 내 프로필',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              InkWell(
                onTap: _updatingProfileImage ? null : () => _editMyRoomProfileImage(mine),
                customBorder: const CircleBorder(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _avatar(mine, r: 32),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFDDDDDD)),
                        ),
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          size: 13,
                          color: Color(0xFF555555),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            mine.nickname,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '이 방에서 쓸 이름 바꾸기',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: Color(0xFF666666),
                          ),
                          onPressed: () =>
                              _editRoomNickname(room, mine.nickname),
                        ),
                      ],
                    ),
                    const Text(
                      '이 방에서만 사용하는 프로필이에요.',
                      style: TextStyle(fontSize: 13, color: _gray),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editRoomNickname(ReadingRoom room, String current) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RoomNicknameDialog(initial: current),
    );
    if (name == null || name.isEmpty || name == current || !mounted) return;
    try {
      final updated = await widget.repository.updateMyRoomNickname(
        room.id,
        name,
      );
      if (!mounted) return;
      await _applyAndRefreshProfileRoom(updated);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('방에서 사용할 이름을 변경했습니다.')));
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _addBook(ReadingRoom room) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _RoomBookPicker(
          excludedBookIds: room.books.map((item) => item.book.id).toSet(),
          onAdd: (book) async {
            final updated = await widget.repository.addBook(room.id, book.id);
            if (mounted) _applyRoom(updated);
          },
        ),
      ),
    );
  }

  Future<ReadingRoom?> _changeBooks(
      Future<ReadingRoom> Function() operation,
      ) async {
    if (_bookMutationInFlight) return null;
    setState(() => _bookMutationInFlight = true);
    try {
      final updated = await operation();
      if (mounted) _applyRoom(updated);
      return updated;
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
      return null;
    } finally {
      if (mounted) setState(() => _bookMutationInFlight = false);
    }
  }

  Future<void> _manageBooks(ReadingRoom room) async {
    await showDialog<void>(
      context: context,
      builder: (sheetContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SizedBox(
          width: 600,
          height: (room.books.length * 76.0 + 72)
              .clamp(0.0, MediaQuery.sizeOf(sheetContext).height * .7)
              .toDouble(),
          child: Column(
            children: [
              ListTile(
                trailing: IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close),
                ),
                title: const Text(
                  '책 관리',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: room.books.length,
                  itemBuilder: (_, index) {
                    final item = room.books[index];
                    final book = item.book;
                    return ListTile(
                      leading: BookCover(
                        url: book.coverImageUrl,
                        width: 36,
                        height: 52,
                      ),
                      title: Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(book.author),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '책 삭제',
                            onPressed: () async {
                              if (room.books.length <= 1) {
                                await showDialog<void>(
                                  context: sheetContext,
                                  builder: (noticeContext) => AlertDialog(
                                    title: const Text('도서를 삭제할 수 없습니다.'),
                                    content: const Text(
                                      '함께 읽는 책은 최소 1권이 필요합니다.\n다른 도서를 추가한 후 삭제해 주세요.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(noticeContext),
                                        child: const Text('확인'),
                                      ),
                                    ],
                                  ),
                                );
                                return;
                              }
                              try {
                                final notes = await widget.repository.sharedNotes(
                                  room.id, bookId: book.id,
                                );
                                if (!mounted || !sheetContext.mounted) return;
                                if (notes.any((note) => note.type == 'MEMO')) {
                                  await showDialog<void>(
                                    context: sheetContext,
                                    builder: (noticeContext) => AlertDialog(
                                      title: const Text('도서를 삭제할 수 없습니다.'),
                                      content: const Text(
                                        '이 방에서 나 또는 친구가 남긴 메모가 있습니다.\n메모가 없는 도서만 삭제할 수 있습니다.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(noticeContext),
                                          child: const Text('확인'),
                                        ),
                                      ],
                                    ),
                                  );
                                  return;
                                }
                              } catch (_) {
                                if (!mounted || !sheetContext.mounted) return;
                                await showDialog<void>(
                                  context: sheetContext,
                                  builder: (noticeContext) => AlertDialog(
                                    title: const Text('메모를 확인할 수 없습니다.'),
                                    content: const Text('잠시 후 다시 시도해 주세요.'),
                                    actions: [TextButton(
                                      onPressed: () => Navigator.pop(noticeContext),
                                      child: const Text('확인'),
                                    )],
                                  ),
                                );
                                return;
                              }
                              final confirmed = await showDialog<bool>(
                                context: sheetContext,
                                builder: (confirmContext) => AlertDialog(
                                  title: const Text('삭제하시겠습니까?'),
                                  content: Text('「${book.title}」을(를) 방에서 삭제합니다.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(confirmContext, false),
                                      child: const Text('취소'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(confirmContext, true),
                                      child: const Text('삭제'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true || !mounted || !sheetContext.mounted) return;
                              final updated = await _changeBooks(
                                    () => widget.repository.removeBook(
                                  room.id,
                                  book.id,
                                ),
                              );
                              if (updated != null &&
                                  sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _booksCard(ReadingRoom room) => FutureBuilder<List<ReadingRoomBookItem>>(
    future: _recentBooks,
    builder: (context, snapshot) {
      final available = room.books.map((item) => item.book.id).toSet();
      final sorted = snapshot.data;
      final current = sorted != null &&
          sorted.length == room.books.length &&
          sorted.every((item) => available.contains(item.book.id));
      final order = current
          ? <int, int>{for (var i = 0; i < sorted!.length; i++) sorted[i].book.id: i}
          : <int, int>{};
      final items = [...room.books];
      if (current) {
        items.sort((a, b) => order[a.book.id]!.compareTo(order[b.book.id]!));
      }
      return _booksCardContent(room, items);
    },
  );

  Widget _booksCardContent(ReadingRoom room, List<ReadingRoomBookItem> sortedBooks) {
    final hasBook = room.books.isNotEmpty || room.bookId != null;
    final bookCount = room.books.isNotEmpty
        ? room.books.length
        : (hasBook ? 1 : 0);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '함께 읽는 책',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$bookCount권',
                style: const TextStyle(fontSize: 14, color: _gray),
              ),
              const Spacer(),
              if (room.isOwner)
                TextButton(
                  onPressed: () => _manageBooks(room),
                  child: const Text('관리'),
                ),
              if (room.isOwner)
                OutlinedButton.icon(
                  onPressed: () => _addBook(room),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('도서 추가'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasBook)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('함께 읽는 책이 없어요.', style: TextStyle(color: _gray)),
              ),
            )
          else
            Column(
              children: [
                for (final item in sortedBooks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RoomBookCard(
                      key: ValueKey('room-book-${room.id}-${item.book.id}'),
                      room: room,
                      book: item.book,
                      isCurrent: item.current,
                      progressRevision: _readerReturnRevision,
                      onOpen: () => _openBook(room, item.book.id),
                    ),
                  ),
                if (room.books.isEmpty && room.book != null)
                  _RoomBookCard(
                    key: ValueKey('room-book-${room.id}-${room.book!.id}'),
                    room: room,
                    book: room.book!,
                    isCurrent: true,
                    progressRevision: _readerReturnRevision,
                    onOpen: () => _openBook(room, room.bookId!),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _coverHeader(ReadingRoom room) {
    final book = room.coverBook ?? room.book;
    return Semantics(
      label: '${room.name} 대표 도서 ${book?.title ?? '미지정'}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _RoomCoverImage(room: room),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x22000000), Color(0xDD000000)],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (book != null)
                        Text(
                          '${book.title} · ${book.author}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF555555),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ReadingRoom>(
    future: _room,
    builder: (context, snapshot) {
      // Do not depend solely on FutureBuilder's next microtask to paint a
      // successful profile mutation.  _visibleRoom changes synchronously.
      final room = _visibleRoom ?? snapshot.data;
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF7F8FA),
          centerTitle: false,
          title: room == null
              ? const Text('독서방')
              : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  room.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (room.isOwner)
                IconButton(
                  tooltip: '방 이름 수정',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _editRoomName(room),
                ),
            ],
          ),
          actions: [
            if (room != null && room.joined)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: OutlinedButton.icon(
                  onPressed: () => _leave(room),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE5484D),
                    backgroundColor: const Color(0xFFFFF2F2),
                    side: const BorderSide(color: Color(0xFFFFD6D6)),
                  ),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('방 나가기'),
                ),
              )
            else if (room != null && room.isPublic)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  onPressed: () async {
                    try {
                      final updated = await widget.repository.joinPublic(
                        room.id,
                      );
                      if (mounted) _applyRoom(updated);
                    } on ApiException catch (error) {
                      if (mounted) _showError(context, error);
                    }
                  },
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('방 참여하기'),
                ),
              ),
          ],
        ),
        body: () {
          if (room == null && snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (room == null && snapshot.hasError)
            return _ErrorState(error: snapshot.error, onRetry: _reload);
          final r = room!;
          return LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 900;
              final left = Column(
                children: [
                  _introCard(r),
                  const SizedBox(height: 16),
                  _membersCard(r),
                  if (r.joined) ...[
                    const SizedBox(height: 16),
                    _myProfileCard(r),
                  ],
                ],
              );
              final right = _booksCard(r);
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 9, child: left),
                        const SizedBox(width: 20),
                        Expanded(flex: 11, child: right),
                      ],
                    )
                  else ...[
                    left,
                    const SizedBox(height: 16),
                    right,
                  ],
                ],
              );
            },
          );
        }(),
      );
    },
  );
}

/// 이 방에서 쓸 이름 입력 창 — 입력 칸 controller 는 창이 완전히 닫힐 때 dispose (닫히는 애니메이션 중 오류 방지)
/// 방 이름만 수정하는 입력 창.
class _RoomDescriptionDialog extends StatefulWidget {
  const _RoomDescriptionDialog({required this.initial});
  final String initial;
  @override
  State<_RoomDescriptionDialog> createState() => _RoomDescriptionDialogState();
}

class _RoomDescriptionDialogState extends State<_RoomDescriptionDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: 560,
        height: constraints.maxHeight.clamp(0.0, 420.0).toDouble(),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('방 소개', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              Expanded(
                child: TextField(
                  controller: _c,
                  autofocus: true,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  maxLength: 500,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                  decoration: InputDecoration(
                    hintText: '이 방을 소개해 주세요',
                    counterText: '',
                    contentPadding: const EdgeInsets.all(16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _c,
                builder: (context, value, _) => Text(
                  '${value.text.characters.length} / 500',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _c.text.trim()),
                    child: const Text('저장'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RoomNameDialog extends StatefulWidget {
  const _RoomNameDialog({required this.initial});
  final String initial;
  @override
  State<_RoomNameDialog> createState() => _RoomNameDialogState();
}

class _RoomNameDialogState extends State<_RoomNameDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('방 이름'),
    content: TextField(
      controller: _c,
      autofocus: true,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) {
        if (_c.text.trim().isNotEmpty) {
          Navigator.pop(context, _c.text.trim());
        }
      },
      maxLength: 100,
      decoration: const InputDecoration(hintText: '방 이름을 입력해주세요'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _c.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _c.text.trim()),
        child: const Text('저장'),
      ),
    ],
  );
}

class _RoomNicknameDialog extends StatefulWidget {
  const _RoomNicknameDialog({required this.initial});
  final String initial;
  @override
  State<_RoomNicknameDialog> createState() => _RoomNicknameDialogState();
}

class _RoomNicknameDialogState extends State<_RoomNicknameDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('이 방에서 쓸 이름'),
    content: TextField(
      controller: _c,
      autofocus: true,
      maxLength: 12,
      decoration: const InputDecoration(hintText: '2~12자'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _c.text.trim()),
        child: const Text('저장'),
      ),
    ],
  );
}

/// 함께 읽는 책 카드 — 표지 · 제목 · 저자 · "함께 읽는 중" 진행 막대(내 위치 표시) · [이어읽기 ›]
class _RoomBookCard extends StatefulWidget {
  const _RoomBookCard({
    super.key,
    required this.room,
    required this.book,
    required this.isCurrent,
    required this.progressRevision,
    required this.onOpen,
  });
  final ReadingRoom room;
  final ReadingRoomBook book;
  final bool isCurrent;
  final int progressRevision;
  final VoidCallback onOpen;
  @override
  State<_RoomBookCard> createState() => _RoomBookCardState();
}

class _RoomBookCardState extends State<_RoomBookCard> {
  late Future<List<RoomParticipantProgress>> _participants;
  late final ReadingRoomRepository _repository;
  Timer? _progressTimer;
  int _progressRequest = 0;
  bool _refreshingProgress = false;

  @override
  void initState() {
    super.initState();
    _repository = ReadingRoomRepository(ApiClient(
      tokenProvider: () => context.read<RidiStore>().accessToken,
    ));
    _loadParticipants();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_refreshParticipants());
      }
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _progressRequest++;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _RoomBookCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id ||
        oldWidget.book.id != widget.book.id ||
        oldWidget.progressRevision != widget.progressRevision ||
        oldWidget.room != widget.room) {
      _loadParticipants();
    }
  }

  void _loadParticipants() {
    _progressRequest++;
    _participants = _repository
        .participantProgress(widget.room.id, widget.book.id)
        .catchError((Object _) => <RoomParticipantProgress>[]);
  }

  Future<void> _refreshParticipants() async {
    if (_refreshingProgress) return;
    _refreshingProgress = true;
    final request = ++_progressRequest;
    try {
      final participants = await _repository.participantProgress(
        widget.room.id, widget.book.id,
      );
      if (!mounted || request != _progressRequest) return;
      setState(() {
        _participants = Future.value(participants);
      });
    } catch (_) {
      // Keep the last visible progress when a background refresh fails.
    } finally {
      _refreshingProgress = false;
    }
  }

  Future<void> _showMemberProgress() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _MemberProgressDialog(
        repository: _repository,
        roomId: widget.room.id,
        book: widget.book,
      ),
    );
    if (mounted) unawaited(_refreshParticipants());
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.book;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFEFEFEF)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCover(url: b.coverImageUrl, width: 84, height: 122),
          const SizedBox(width: 16),
          Expanded(
            child: FutureBuilder<List<RoomParticipantProgress>>(
              future: _participants,
              builder: (context, snap) {
                final participants =
                    snap.data ?? const <RoomParticipantProgress>[];
                final mine = participants
                    .where((item) => item.currentUser)
                    .firstOrNull;
                final pct = (mine?.progressPercent ?? 0).clamp(0, 100);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b?.title ?? '대표 도서',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                b?.author ?? '',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF9E9E9E),
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton(
                          onPressed: widget.onOpen,
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('이어읽기 ›'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '내 진행 $pct%',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF22B573),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct / 100,
                        minHeight: 8,
                        color: const Color(0xFF22B573),
                        backgroundColor: const Color(0xFFEDEDED),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: widget.room.joined ? _showMemberProgress : null,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                        ),
                        child: const Text('멤버 진행률 보기 ›'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// The participant endpoint returns the same room nickname and photo as the
// member list, including members who have not started this book (0%).
class _MemberProgressDialog extends StatefulWidget {
  const _MemberProgressDialog({
    required this.repository,
    required this.roomId,
    required this.book,
  });
  final ReadingRoomRepository repository;
  final int roomId;
  final ReadingRoomBook book;

  @override
  State<_MemberProgressDialog> createState() => _MemberProgressDialogState();
}

class _MemberProgressDialogState extends State<_MemberProgressDialog>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  late Future<List<RoomParticipantProgress>> _progress;
  List<RoomParticipantProgress>? _lastProgress;
  Timer? _refreshTimer;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _progress = _fetch();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _reloadProgress();
      }
    });
  }

  Future<List<RoomParticipantProgress>> _fetch() async {
    _fetching = true;
    try {
      final rows = await widget.repository.participantProgress(widget.roomId, widget.book.id);
      if (mounted) _lastProgress = rows;
      return rows;
    } finally {
      _fetching = false;
    }
  }

  void _reloadProgress() {
    if (!mounted || _fetching) return;
    setState(() => _progress = _fetch());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reloadProgress();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  Widget _memberRow(RoomParticipantProgress member) {
    final name = member.nickname.trim().isEmpty ? '참여자' : member.nickname;
    final photo = member.profileImageUrl?.trim();
    final hasPhoto = photo != null && photo.isNotEmpty;
    final percent = member.progressPercent.clamp(0, 100).toInt();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFE9EEF5),
            foregroundImage: hasPhoto
                ? NetworkImage(widget.repository.absoluteUrl(photo!)) : null,
            onForegroundImageError: hasPhoto ? (_, __) {} : null,
            child: Text(name.characters.first,
                style: const TextStyle(fontWeight: FontWeight.w700,
                    color: Color(0xFF4A5568))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    if (member.currentUser) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: const Color(0xFF505761),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Text('나', style: TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(child: Text(name, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                    const SizedBox(width: 12),
                    Text('$percent%', style: const TextStyle(
                        color: Color(0xFF22B573), fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: percent / 100,
                      minHeight: 7, color: const Color(0xFF22B573),
                      backgroundColor: const Color(0xFFEDEDED)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: SizedBox(
      width: 440,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(child: Text('멤버 진행률', style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800))),
              IconButton(tooltip: '진행률 새로고침', onPressed: _reloadProgress,
                  icon: const Icon(Icons.refresh, color: Color(0xFF777777))),
              IconButton(tooltip: '닫기', onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Color(0xFF777777))),
            ]),
            Text(widget.book.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Color(0xFF888888))),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<List<RoomParticipantProgress>>(
                future: _progress,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done &&
                      snapshot.data == null && _lastProgress == null) {
                    return const SizedBox(height: 120,
                        child: Center(child: CircularProgressIndicator()));
                  }
                  if (snapshot.hasError && _lastProgress == null) {
                    final error = snapshot.error;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(error is ApiException ? error.message : '진행률을 불러오지 못했습니다.',
                            textAlign: TextAlign.center),
                        TextButton(onPressed: _reloadProgress, child: const Text('다시 시도')),
                      ]),
                    );
                  }
                  final members = [...(snapshot.data ?? _lastProgress ?? const <RoomParticipantProgress>[])];
                  // Keep join order for everyone else; show the current user first.
                  final ordered = [
                    ...members.where((member) => member.currentUser),
                    ...members.where((member) => !member.currentUser),
                  ];
                  if (ordered.isEmpty) {
                    return const Padding(padding: EdgeInsets.all(20),
                        child: Center(child: Text('참여 중인 멤버가 없습니다.')));
                  }
                  final list = Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: false,
                    child: ListView.builder(
                      controller: _scrollController,
                      shrinkWrap: true,
                      itemCount: ordered.length,
                      itemBuilder: (_, index) => _memberRow(ordered[index]),
                    ),
                  );
                  if (snapshot.hasError) {
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('갱신하지 못해 마지막 조회 결과를 표시합니다.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
                      Flexible(child: list),
                    ]);
                  }
                  return list;
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<Map<String, dynamic>?> showRoomEditorLegacy(
    BuildContext context, {
      ReadingRoom? room,
    }) async {
  final name = TextEditingController(text: room?.name ?? '');
  final description = TextEditingController(text: room?.description ?? '');
  final roomNickname = TextEditingController();
  int maxMembers = room?.maxMembers ?? 6;
  bool isPublic = room?.isPublic ?? true;
  bool spoilerLockEnabled = room?.spoilerLockEnabled ?? false;
  String? aiFriendType = room?.selectedAiFriendType;
  int? bookId = room?.bookId;
  try {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(room == null ? '방 만들기' : '방 정보 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  onChanged: (_) => setState(() {}),
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: '방 이름'),
                ),
                TextField(
                  controller: description,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: '방 설명 (선택)'),
                ),
                DropdownButtonFormField<int?>(
                  value: bookId,
                  decoration: const InputDecoration(labelText: '대표 도서 (선택)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('주제형 방')),
                    if (bookId != null)
                      DropdownMenuItem(
                        value: bookId,
                        child: const Text('선택된 대표 도서'),
                      ),
                    const DropdownMenuItem(
                      value: -1,
                      child: Text('도서 목록에서 선택'),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == -1) {
                      final selected = await Navigator.of(context).push<Book>(
                        MaterialPageRoute(builder: (_) => _RoomBookPicker()),
                      );
                      if (selected != null)
                        setState(() => bookId = selected.id);
                    } else {
                      setState(() => bookId = value);
                    }
                  },
                ),
                DropdownButtonFormField<int>(
                  value: maxMembers,
                  decoration: const InputDecoration(labelText: '최대 인원'),
                  items: [
                    for (var i = 2; i <= 10; i++)
                      DropdownMenuItem(value: i, child: Text('$i명')),
                  ],
                  onChanged: (value) => setState(() => maxMembers = value!),
                ),
                SwitchListTile(
                  title: const Text('공개 방'),
                  subtitle: Text(isPublic ? '공개 목록에 표시됩니다.' : '입장 코드가 필요합니다.'),
                  value: isPublic,
                  onChanged: (value) => setState(() => isPublic = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: name.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, {
                'name': name.text.trim(),
                'description': description.text.trim(),
                'bookId': bookId,
                'maxMembers': maxMembers,
                'isPublic': isPublic,
              }),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  } finally {
    name.dispose();
    description.dispose();
    roomNickname.dispose();
  }
}

Future<Map<String, dynamic>?> showRoomEditor(
    BuildContext context, {
      required ReadingRoom room,
    }) async {
  final name = TextEditingController(text: room.name);
  final description = TextEditingController(text: room.description ?? '');
  final bookId = room.currentBookId ?? room.bookId;
  var maxMembers = room.maxMembers;
  var isPublic = room.isPublic;
  var spoilerLock = room.spoilerLockEnabled;
  String? aiFriend = room.selectedAiFriendType;
  try {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('방 정보 수정'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    onChanged: (_) => setDialogState(() {}),
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: '방 이름',
                      hintText: '예: 매일 한 장 독서!',
                    ),
                  ),
                  TextField(
                    controller: description,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: '방 설명 (선택)'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('함께 읽는 책'),
                    subtitle: const Text('책 추가·삭제·현재 책 지정은 방 책 관리에서 하세요.'),
                    trailing: const Icon(Icons.menu_book_outlined),
                    onTap: null,
                  ),
                  Row(
                    children: [
                      const Text('최대 인원'),
                      const Spacer(),
                      IconButton(
                        onPressed: maxMembers <= 2
                            ? null
                            : () => setDialogState(() => maxMembers--),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$maxMembers명'),
                      IconButton(
                        onPressed: maxMembers >= 10
                            ? null
                            : () => setDialogState(() => maxMembers++),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('공개방'),
                    subtitle: Text(
                      isPublic ? '탐색 목록에 노출됩니다.' : '입장 코드가 필요합니다.',
                    ),
                    value: isPublic,
                    onChanged: (value) =>
                        setDialogState(() => isPublic = value),
                  ),
                  DropdownButtonFormField<String?>(
                    value: aiFriend,
                    decoration: const InputDecoration(labelText: 'AI 독서친구'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('선택 안 함')),
                      DropdownMenuItem(value: 'HAYU', child: Text('하루 · 공감형')),
                      DropdownMenuItem(
                        value: 'DOHYUN',
                        child: Text('도현 · 분석형'),
                      ),
                      DropdownMenuItem(value: 'MINA', child: Text('미나 · 질문형')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => aiFriend = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: name.text.trim().isEmpty || bookId == null
                  ? null
                  : () => Navigator.of(dialogContext).pop({
                'name': name.text.trim(),
                'description': description.text.trim(),
                'bookId': bookId,
                'maxMembers': maxMembers,
                'isPublic': isPublic,
                'spoilerLockEnabled': spoilerLock,
                'selectedAiFriendType': aiFriend,
              }),
              child: const Text('만들기'),
            ),
          ],
        ),
      ),
    );
  } finally {
    name.dispose();
    description.dispose();
  }
}

class _RoomBookPicker extends StatefulWidget {
  const _RoomBookPicker({
    this.excludedBookIds = const <int>{},
    this.onAdd,
  });
  final Set<int> excludedBookIds;
  final Future<void> Function(Book book)? onAdd;

  @override
  State<_RoomBookPicker> createState() => _RoomBookPickerState();
}

class _RoomBookPickerState extends State<_RoomBookPicker> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(Book book) {
    final query = _query.trim().toLowerCase();
    return query.isEmpty || book.title.toLowerCase().contains(query) ||
        (book.author ?? '').toLowerCase().contains(query);
  }

  late Future<List<Book>> _books;
  final Set<int> _added = <int>{};
  int? _pendingBookId;

  Future<void> _add(Book book) async {
    if (_pendingBookId != null || _added.contains(book.id)) return;
    if (widget.onAdd == null) {
      Navigator.of(context).pop(book);
      return;
    }
    setState(() => _pendingBookId = book.id);
    try {
      await widget.onAdd!(book);
      if (mounted) setState(() => _added.add(book.id));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is ApiException
              ? error.message
              : '도서 추가에 실패했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingBookId = null);
    }
  }
  @override
  void initState() {
    super.initState();
    _books = BookRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    ).books();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.onAdd == null ? '대표 도서 선택' : '도서 추가')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: '책 제목 또는 저자 검색',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty ? null : IconButton(
                tooltip: '검색어 지우기',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Expanded(child: FutureBuilder<List<Book>>(
          future: _books,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(
                error: snapshot.error,
                onRetry: () => setState(() {
                  _books = BookRepository(
                    ApiClient(
                      tokenProvider: () => context.read<RidiStore>().accessToken,
                    ),
                  ).books();
                }),
              );
            }
            final books = (snapshot.data ?? const <Book>[])
                .where((book) => !widget.excludedBookIds.contains(book.id) && !_added.contains(book.id) && _matchesSearch(book))
                .toList();
            if (books.isEmpty) {
              return Center(child: Text(_query.trim().isNotEmpty
                  ? '검색 결과가 없습니다.'
                  : '추가할 수 있는 도서가 없습니다.'));
            }
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                mainAxisSpacing: 20,
                crossAxisSpacing: 18,
                childAspectRatio: .5,
              ),
              itemCount: books.length,
              itemBuilder: (context, index) {
                final book = books[index];
                final pending = _pendingBookId == book.id;
                return _RoomBookAddTile(
                  book: book,
                  onTap: _pendingBookId != null ? null : () => _add(book),
                  overlay: pending
                      ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Material(
                    color: Colors.white70,
                    shape: CircleBorder(),
                    child: Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(Icons.add),
                    ),
                  ),
                );
              },
            );
          },
        )),
      ],
    ),
  );
}

class _RoomBookAddTile extends StatelessWidget {
  const _RoomBookAddTile({required this.book, this.onTap, this.overlay});
  final Book book;
  final VoidCallback? onTap;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => Stack(
              children: [
                BookCover(
                  url: book.coverImageUrl,
                  width: c.maxWidth,
                  height: c.maxHeight,
                ),
                if (overlay != null)
                  Positioned(top: 6, right: 6, child: overlay!),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        Text(
          book.author ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A)),
        ),
      ],
    ),
  );
}


enum _RoomProfileImageAction { gallery, remove }

enum _RoomCoverImageAction { gallery, remove }

class SharedRoomNotesScreen extends StatefulWidget {
  const SharedRoomNotesScreen({
    super.key,
    required this.repository,
    required this.roomId,
  });
  final ReadingRoomRepository repository;
  final int roomId;
  @override
  State<SharedRoomNotesScreen> createState() => _SharedRoomNotesScreenState();
}

class _SharedRoomNotesScreenState extends State<SharedRoomNotesScreen> {
  late Future<List<SharedRoomNote>> _notes;
  late final RoomSyncClient _sync;
  bool _roomOwner = false;
  @override
  void initState() {
    super.initState();
    _notes = widget.repository.sharedNotes(widget.roomId);
    unawaited(_loadOwnerPermission());
    _sync = RoomSyncClient(
      repository: widget.repository,
      baseUrl: ApiClient().baseUrl,
      token: context.read<RidiStore>().accessToken,
      roomId: widget.roomId,
      onChanged: () {
        if (mounted) _reload();
      },
    )..start();
  }

  @override
  void dispose() {
    _sync.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _notes = widget.repository.sharedNotes(widget.roomId);
    });
  }

  Future<void> _loadOwnerPermission() async {
    try {
      final room = await widget.repository.detail(widget.roomId);
      if (mounted) setState(() => _roomOwner = room.isOwner);
    } on ApiException {
      // The server checks owner authority again when deletion is requested.
    }
  }

  Future<void> _reveal(SharedRoomNote locked) async {
    try {
      final revealed = await widget.repository.revealSharedNote(
        widget.roomId,
        locked.id,
      );
      if (!mounted) return;
      setState(
            () => _notes = _notes.then(
              (items) => [
            for (final item in items)
              if (item.id == revealed.id) revealed else item,
          ],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('공유 독서노트'),
      actions: [
        ValueListenableBuilder<RoomSyncState>(
          valueListenable: _sync.state,
          builder: (_, state, _) => Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              state == RoomSyncState.live
                  ? Icons.sync
                  : state == RoomSyncState.fallback
                  ? Icons.cloud_sync_outlined
                  : Icons.sync_problem_outlined,
              semanticLabel: state == RoomSyncState.live
                  ? '실시간 동기화 중'
                  : '자동 새로고침 중',
            ),
          ),
        ),
      ],
    ),
    body: FutureBuilder<List<SharedRoomNote>>(
      future: _notes,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return _ErrorState(error: snapshot.error, onRetry: _reload);
        final notes = snapshot.data ?? const <SharedRoomNote>[];
        if (notes.isEmpty)
          return const Center(child: Text('아직 공유된 독서노트가 없습니다.'));
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final note = notes[index];
              if (note.isSpoilerLocked)
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('스포일러 잠김'),
                    trailing: TextButton(
                      onPressed: () => _reveal(note),
                      child: const Text('내용 보기'),
                    ),
                    subtitle: const Text(
                      '이 메모는 현재 읽은 위치 이후에 있어요.\n더 읽으면 확인할 수 있어요.',
                    ),
                  ),
                );
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    foregroundImage: note.profileImageUrl?.isNotEmpty == true
                        ? NetworkImage(note.profileImageUrl!)
                        : null,
                    child: note.profileImageUrl?.isNotEmpty == true
                        ? null
                        : Icon(
                      note.type == 'HIGHLIGHT'
                          ? Icons.format_paint_outlined
                          : Icons.sticky_note_2_outlined,
                    ),
                  ),
                  title: Text('${note.nickname} · 문단 ${note.paragraphOrder}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (note.selectedText?.isNotEmpty == true)
                        Text(
                          note.selectedText!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (note.content?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(note.content!),
                        ),
                      if (note.type == 'MEMO')
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('댓글 ${note.commentCount}개'),
                        ),
                    ],
                  ),
                  isThreeLine: true,
                  onTap: note.type == 'MEMO' ? () => _comments(note) : null,
                  trailing: !note.isSpoilerLocked && (note.mine || _roomOwner)
                      ? PopupMenuButton<_SharedNoteAction>(
                    onSelected: (action) => _manageNote(note, action),
                    itemBuilder: (_) => [
                      if (note.mine && note.type == 'MEMO')
                        const PopupMenuItem(
                          value: _SharedNoteAction.edit,
                          child: Text('메모 수정'),
                        ),
                      const PopupMenuItem(
                        value: _SharedNoteAction.delete,
                        child: Text('삭제'),
                      ),
                    ],
                  )
                      : null,
                ),
              );
            },
          ),
        );
      },
    ),
  );
  Future<void> _comments(SharedRoomNote note) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SharedNoteComments(
        repository: widget.repository,
        roomId: widget.roomId,
        note: note,
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _manageNote(
      SharedRoomNote note,
      _SharedNoteAction action,
      ) async {
    try {
      if (action == _SharedNoteAction.delete) {
        final confirmed = await _confirm(
          context,
          '공유 노트 삭제',
          '이 공유 노트를 삭제할까요?',
        );
        if (!confirmed) return;
        await widget.repository.deleteSharedNote(widget.roomId, note.id);
      } else {
        final controller = TextEditingController(text: note.content ?? '');
        final value = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('메모 수정'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 4000,
              minLines: 2,
              maxLines: 8,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, controller.text),
                child: const Text('저장'),
              ),
            ],
          ),
        );
        controller.dispose();
        if (value == null || value.trim().isEmpty) return;
        await widget.repository.updateSharedNote(widget.roomId, note.id, {
          'content': value.trim(),
        });
      }
      if (mounted) _reload();
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    }
  }
}

enum _SharedNoteAction { edit, delete }

class _SharedNoteComments extends StatefulWidget {
  const _SharedNoteComments({
    super.key,
    required this.repository,
    required this.roomId,
    required this.note,
    this.embedded = false,
    this.bodyMemoStyle = false,
    this.bodyAccess = false,
    this.navigation,
    this.onClose,
  });
  final ReadingRoomRepository repository;
  final int roomId;
  final SharedRoomNote note;
  final bool embedded;
  final bool bodyMemoStyle;
  final bool bodyAccess;
  final Widget? navigation;
  final VoidCallback? onClose;
  @override
  State<_SharedNoteComments> createState() => _SharedNoteCommentsState();
}

class _SharedNoteCommentsState extends State<_SharedNoteComments> {
  final _commentsScrollController = ScrollController();
  final _text = TextEditingController();
  final _memoFocus = FocusNode();
  late final TextEditingController _memoEditor;
  bool _savingMemo = false;
  bool _editingMemo = false;
  String? _memoError;
  late Future<List<SharedRoomNoteComment>> _comments;
  bool _sending = false;
  late SharedRoomNote _note;
  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _memoEditor = TextEditingController(text: _note.content ?? '');
    _comments = widget.repository.sharedNoteComments(
      widget.roomId,
      _note.id,
      revealed: widget.bodyAccess || _note.explicitlyRevealed,
    );
  }

  @override
  void dispose() {
    _commentsScrollController.dispose();
    _text.dispose();
    _memoEditor.dispose();
    _memoFocus.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _comments = widget.repository.sharedNoteComments(
        widget.roomId,
        _note.id,
        revealed: widget.bodyAccess || _note.explicitlyRevealed,
      );
    });
  }
  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('댓글 내용을 입력해주세요.')));
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.repository.addSharedNoteComment(
        widget.roomId,
        _note.id,
        text,
        revealed: widget.bodyAccess || _note.explicitlyRevealed,
      );
      if (!mounted) return;
      _text.clear();
      _reload();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_sharedNoteMessage(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _parentNoteAction(String action) async {
    if (_note.isSpoilerLocked) return;
    if (action == 'delete' ? !_note.canDelete : !_note.mine) return;
    if (action == 'delete') {
      final ok = await _confirm(context, '메모 삭제', '이 메모를 삭제하시겠습니까?');
      if (!ok || !mounted) return;
      try {
        await widget.repository.deleteSharedNote(widget.roomId, _note.id);
        if (!mounted) return;
        if (widget.onClose != null) widget.onClose!();
        else Navigator.pop(context);
      } on ApiException catch(e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_sharedNoteMessage(e))));
      }
      return;
    }
    final editor = TextEditingController(text: _note.content ?? '');
    bool saving = false;
    String? error;
    try {
      await showDialog<void>(context: context, barrierDismissible: false, barrierColor: Colors.transparent,
          builder: (dc) => StatefulBuilder(builder: (_,update) => AlertDialog(
            title: const Text('메모 수정'),
            content: SizedBox(width: 400,child: TextField(controller: editor,enabled: !saving,
                minLines: 4,maxLines: 8,maxLength: 4000,
                decoration: InputDecoration(errorText: error,border: const OutlineInputBorder()))),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(dc),child: const Text('취소')),
              FilledButton(onPressed: saving ? null : () async {
                final text = editor.text.trim();
                if (text.isEmpty) { update(() => error = '메모 내용을 입력해 주세요.'); return; }
                update(() { saving = true; error = null; });
                try {
                  final note = await widget.repository.updateSharedNote(widget.roomId,_note.id,{'content':text});
                  if (mounted) setState(() => _note = note);
                  if (dc.mounted) Navigator.pop(dc);
                } catch(e) {
                  if (dc.mounted) update(() { saving = false; error = '메모 저장 실패: $e'; });
                }
              },child: Text(saving ? '저장 중' : '저장')),
            ],
          )));
    } finally { editor.dispose(); }
  }

  Future<void> _editComment(SharedRoomNoteComment comment) async {
    if (!comment.mine) return;
    final editor = TextEditingController(text: comment.content);
    bool saving = false;
    String? error;
    try {
      await showDialog<void>(context: context, barrierDismissible: false, barrierColor: Colors.transparent,
          builder: (dc) => StatefulBuilder(builder: (_,update) => AlertDialog(
            title: const Text('댓글 수정'),
            content: SizedBox(width: 400,child: TextField(controller: editor,enabled: !saving,
                minLines: 4,maxLines: 8,maxLength: 1000,
                decoration: InputDecoration(errorText: error,border: const OutlineInputBorder()))),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(dc),child: const Text('취소')),
              FilledButton(onPressed: saving ? null : () async {
                final text = editor.text.trim();
                if (text.isEmpty) { update(() => error = '댓글 내용을 입력해 주세요.'); return; }
                update(() { saving = true; error = null; });
                try {
                  await widget.repository.updateSharedNoteComment(widget.roomId, _note.id, comment.id, text, revealed: widget.bodyAccess || _note.explicitlyRevealed);
                  if (mounted) _reload();
                  if (dc.mounted) Navigator.pop(dc);
                } catch(e) {
                  if (dc.mounted) update(() { saving = false; error = '댓글 저장 실패: $e'; });
                }
              },child: Text(saving ? '저장 중' : '저장')),
            ],
          )));
    } finally { editor.dispose(); }
  }

  Future<void> _saveBodyMemo() async {
    if (_savingMemo || _sending) return;
    if (!_editingMemo || !_note.mine || _memoEditor.text.trim() == (_note.content ?? '').trim()) {
      (widget.onClose ?? () => Navigator.pop(context))(); return;
    }
    final text = _memoEditor.text.trim();
    if (text.isEmpty || text.length > 3000) {
      setState(() => _memoError = '메모는 1~3,000자로 입력해주세요.'); return;
    }
    setState(() { _savingMemo = true; _memoError = null; });
    try {
      await widget.repository.updateSharedNote(widget.roomId, _note.id, {'content': text});
      if (mounted) (widget.onClose ?? () => Navigator.pop(context))();
    } catch (_) {
      if (mounted) setState(() { _savingMemo = false; _memoError = '메모를 저장하지 못했어요. 다시 시도해주세요.'; });
    }
  }

  Widget _bodyMemoCard() {
    final hex = (_note.highlightColor ?? '#FFF59D').replaceFirst('#', '');
    final color = Color(int.tryParse('FF$hex', radix: 16) ?? 0xFFFFF59D);
    return Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ConstrainedBox(constraints: const BoxConstraints(maxHeight: 70),
              child: SingleChildScrollView(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 16, height: 16, margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(child: Text(_note.selectedText ?? '',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF555555), height: 1.5))),
              ]))),
          const SizedBox(height: 10),
          Row(children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: const Color(0xFFEFF1F5),
              foregroundImage: _note.profileImageUrl?.isNotEmpty == true
                  ? NetworkImage(widget.repository.absoluteUrl(_note.profileImageUrl!)) : null,
              onForegroundImageError: _note.profileImageUrl?.isNotEmpty == true ? (_, __) {} : null,
              child: Text(_note.nickname.isEmpty ? '?' : _note.nickname.characters.first,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF555555))),
            ),
            const SizedBox(width: 8),
            if (_note.mine) ...[
              Container(width: 22, height: 22, alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Color(0xFF505761), shape: BoxShape.circle),
                  child: const Text('나', style: TextStyle(color: Colors.white,
                      fontSize: 12, fontWeight: FontWeight.w700))),
              const SizedBox(width: 6),
            ],
            Expanded(child: Text(_note.nickname,
                style: const TextStyle(fontSize: 13, color: Color(0xFF555555), fontWeight: FontWeight.w600))),
            if (_note.mine || _note.canDelete) SizedBox(width: 28, height: 24, child: PopupMenuButton<String>(
              tooltip: '메모 메뉴', padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_horiz, size: 20, color: Colors.grey),
              onSelected: (action) {
                if (action == 'edit' && _note.mine) {
                  setState(() { _editingMemo = true; _memoError = null; });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _memoFocus.requestFocus();
                    _memoEditor.selection = TextSelection.collapsed(offset: _memoEditor.text.length);
                  });
                } else {
                  _parentNoteAction(action);
                }
              },
              itemBuilder: (_) => [
                if (_note.mine) const PopupMenuItem(value: 'edit', child: Text('수정')),
                const PopupMenuItem(value: 'delete',
                    child: Text('삭제', style: TextStyle(color: Colors.red))),
              ],
            )),
          ]),
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(10)),
            child: _note.mine && _editingMemo
                ? TextField(controller: _memoEditor, focusNode: _memoFocus, enabled: !_savingMemo,
                minLines: 2, maxLines: 3, maxLength: 3000,
                decoration: const InputDecoration(border: InputBorder.none,
                    isDense: true, contentPadding: EdgeInsets.zero, counterText: ''),
                style: const TextStyle(fontSize: 15, height: 1.7))
                : ConstrainedBox(constraints: const BoxConstraints(maxHeight: 90),
                child: SingleChildScrollView(child: Text(_note.content ?? '',
                    style: const TextStyle(fontSize: 15, height: 1.7)))),
          ),
          if (_memoError != null) Text(_memoError!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 10),
          const Text('댓글', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]));
  }

  String _timeAgo(DateTime? value) {
    if (value == null) return '';
    final elapsed = DateTime.now().difference(value);
    if (elapsed.inMinutes < 1) return '방금 전';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}분 전';
    if (elapsed.inDays < 1) return '${elapsed.inHours}시간 전';
    return '${elapsed.inDays}일 전';
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Dialog (or the containing notes dialog) has already removed the keyboard
      // from the available constraints. Never impose a minimum dialog height.
      final preferredHeight = widget.bodyMemoStyle ? 600.0 : 560.0;
      final availableHeight = constraints.hasBoundedHeight
          ? constraints.maxHeight : preferredHeight;
      final height = widget.embedded ? availableHeight
          : availableHeight.clamp(0.0, preferredHeight).toDouble();
      final compact = height < 420;
      // Reserve space for the title, comment composer and optional navigation.
      final memoHeight = (height * (compact ? .38 : .48))
          .clamp(0.0, (height - 180).clamp(0.0, 300.0)).toDouble();
      return SizedBox(
        width: widget.bodyMemoStyle ? 560 : 500,
        height: height,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 52, child: Stack(alignment: Alignment.center, children: [
            Text(widget.bodyMemoStyle ? '메모' : '댓글', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Positioned(left: widget.bodyMemoStyle ? 8 : null, right: widget.bodyMemoStyle ? null : 8, child: TextButton(
              onPressed: _savingMemo || _sending ? null : widget.onClose ?? () => Navigator.pop(context),
              child: const Text('닫기', style: TextStyle(color: Colors.grey)),
            )),
            if (widget.bodyMemoStyle) Positioned(right: 8, child: TextButton(
              onPressed: _savingMemo || _sending ? null : _saveBodyMemo,
              child: Text(_editingMemo && _note.mine ? (_savingMemo ? '저장 중' : '저장') : '완료',
                  style: const TextStyle(color: Color(0xFF1E88E5), fontWeight: FontWeight.bold)),
            )),
          ])),
          const Divider(height: 1, color: Color(0xFFEDEDED)),
          if (widget.bodyMemoStyle)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: memoHeight),
              child: SingleChildScrollView(child: _bodyMemoCard()),
            )
          else Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 130),
              child: SingleChildScrollView(child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,children: [
                CircleAvatar(radius: 17,backgroundColor: const Color(0xFFEFF1F5),
                    child: Text(_note.nickname.isEmpty ? '?' : _note.nickname.characters.first,
                        style: const TextStyle(fontSize: 13,color: Color(0xFF555555)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,children: [
                  Wrap(spacing: 8,crossAxisAlignment: WrapCrossAlignment.center,children: [

                    if (_note.mine)
                      Container(
                        width: 22, height: 22, alignment: Alignment.center,
                        decoration: const BoxDecoration(color: Color(0xFF505761), shape: BoxShape.circle),
                        child: const Text('나', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    Text(_note.nickname,style: const TextStyle(fontSize: 13,fontWeight: FontWeight.w700)),
                    Text(_timeAgo(_note.createdAt),style: const TextStyle(fontSize: 11,color: Color(0xFF999999))),
                  ]),
                  if (_note.selectedText?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Container(padding: const EdgeInsets.only(left: 8),
                        decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFFDDDDDD),width: 2))),
                        child: Text('“${_note.selectedText}”',style: const TextStyle(fontSize: 12,color: Color(0xFF888888),height: 1.4))),
                  ],
                  const SizedBox(height: 6),
                  Text(_note.content ?? '',style: const TextStyle(fontSize: 14,height: 1.5)),
                ])),
                if (!_note.isSpoilerLocked && _note.canDelete) SizedBox(width: 28,height: 24,child: PopupMenuButton<String>(
                  tooltip: '메모 메뉴',padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_horiz,size: 20,color: Colors.grey),
                  onSelected: _parentNoteAction,
                  itemBuilder: (_) => [
                    if (_note.mine) const PopupMenuItem(value:'edit',child: Text('수정')),
                    const PopupMenuItem(value:'delete',child: Text('삭제',style:TextStyle(color:Colors.red))),
                  ],
                )),
              ],
              )),
            ),
          ),
          Expanded(child: FutureBuilder<List<SharedRoomNoteComment>>(
            future: _comments,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done)
                return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError) return Center(child: TextButton(
                  onPressed: _reload, child: const Text('댓글을 불러오지 못했습니다. 다시 시도')));
              final comments = snapshot.data ?? const <SharedRoomNoteComment>[];
              if (comments.isEmpty) return const Center(child: Text('첫 댓글을 남겨보세요.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF999999))));
              return Scrollbar(
                controller: _commentsScrollController,
                thumbVisibility: false,
                trackVisibility: false,
                thickness: 4,
                radius: const Radius.circular(4),
                scrollbarOrientation: ScrollbarOrientation.right,
                notificationPredicate: (notification) =>
                notification.depth == 0 && notification.metrics.axis == Axis.vertical,
                child: ListView.separated(
                  controller: _commentsScrollController,
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(33, 0, 16, 12),
                  itemCount: comments.length,
                  separatorBuilder: (_,__) => const SizedBox.shrink(),
                  itemBuilder: (_,i) {
                    final comment = comments[i];
                    return Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 0, 10),
                      decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFFE0E0E0)))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CircleAvatar(radius: 14, backgroundColor: const Color(0xFFEFF1F5),
                            child: Text(comment.nickname.isEmpty ? '?' : comment.nickname.characters.first,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF555555)))),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Wrap(spacing: 6,crossAxisAlignment: WrapCrossAlignment.center,children: [

                            if (comment.mine) ...[
                              Container(
                                width: 22, height: 22, alignment: Alignment.center,
                                decoration: const BoxDecoration(color: Color(0xFF505761), shape: BoxShape.circle),
                                child: const Text('나', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                              ),
                            ],
                            Text(comment.nickname, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            Text(_timeAgo(comment.createdAt),style: const TextStyle(fontSize: 11,color: Color(0xFF999999))),
                          ]),
                          const SizedBox(height: 5),
                          Text(comment.content, style: const TextStyle(fontSize: 14,height: 1.4)),
                        ])),
                        if (comment.mine || comment.canDelete) SizedBox(width: 28,height: 24,child: PopupMenuButton<String>(
                          tooltip: '댓글 메뉴',padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_horiz,size:20,color: Colors.grey),
                          onSelected: (action) {
                            if (action == 'edit') _editComment(comment);
                            else if (action == 'delete') _delete(comment.id);
                          },
                          itemBuilder: (_) => [
                            if (comment.mine) const PopupMenuItem(value:'edit',child: Text('수정')),
                            const PopupMenuItem(value:'delete',child: Text('삭제',style:TextStyle(color:Colors.red))),
                          ],
                        )),
                      ]),
                    );
                  },
                ),
              );
            },
          )),
          if (widget.navigation != null) AbsorbPointer(absorbing: _sending || _savingMemo, child: widget.navigation!),
          const Divider(height: 1,color: Color(0xFFEDEDED)),
          Padding(padding: const EdgeInsets.fromLTRB(12,10,12,12),child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,children: [
            Expanded(child: TextField(
              controller: _text, enabled: !_sending, minLines: 1,
              maxLines: compact ? 1 : 3, maxLength: 1000,
              decoration: InputDecoration(
                hintText: '댓글을 입력하세요', counterText: '', isDense: true,
                filled: true,fillColor: const Color(0xFFF5F5F5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12,vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),borderSide: BorderSide.none),
              ),
            )),
            const SizedBox(width: 8),
            SizedBox(width: 42,height:42,child: IconButton.filled(
              tooltip: '댓글 등록',onPressed: _sending ? null : _send,
              icon: _sending ? const SizedBox(width:18,height:18,child: CircularProgressIndicator(strokeWidth:2))
                  : const Icon(Icons.arrow_upward,size:22),
            )),
          ],
          )),
        ]),
      );
    },
  );

  Future<void> _delete(int commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFE7E9EF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('댓글 삭제'),
        content: const Text('삭제하시겠습니까?'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF2196F3)),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteSharedNoteComment(
        widget.roomId,
        _note.id,
        commentId,
        revealed: widget.bodyAccess || _note.explicitlyRevealed,
      );
      if (mounted) _reload();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_sharedNoteMessage(e))));
      }
    }
  }
}

String _sharedNoteMessage(ApiException error) => switch (error.errorCode) {
  'SPOILER_LOCKED' => '현재 읽은 위치 이후의 메모는 확인할 수 없습니다.',
  'ROOM_MEMBER_REQUIRED' => '독서방 참여자만 이용할 수 있습니다.',
  'COMMENTS_ONLY_FOR_MEMO' => '메모에만 댓글을 작성할 수 있습니다.',
  'COMMENT_EDIT_FORBIDDEN' ||
  'COMMENT_DELETE_FORBIDDEN' => '본인이 작성한 댓글만 수정하거나 삭제할 수 있습니다.',
  _ when error.isUnauthorized => '로그인이 만료되었습니다. 다시 로그인해주세요.',
  _ => '요청을 처리하지 못했습니다. 잠시 후 다시 시도해주세요.',
};

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 40),
        const SizedBox(height: 12),
        Text(_roomListErrorMessage(error)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    ),
  );
}

String _roomListErrorMessage(Object? error) {
  if (error is! ApiException) {
    return '독서방 목록을 불러오는 중 문제가 발생했습니다. 다시 시도해주세요.';
  }
  if (error.statusCode == 401) return '로그인이 만료되었습니다. 다시 로그인해주세요.';
  if (error.statusCode == 403) return '독서방 목록을 볼 권한이 없습니다.';
  if (error.statusCode == null) return '네트워크 연결을 확인해주세요.';
  return '독서방 목록을 불러오는 중 문제가 발생했습니다. 다시 시도해주세요.';
}

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('확인'),
          ),
        ],
      ),
    ) ??
        false;
void _showError(BuildContext context, ApiException error) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_roomErrorMessage(error))));

String _roomErrorMessage(ApiException error) => switch (error.errorCode) {
  'INVALID_REQUEST' || 'ROOM_BOOK_REQUIRED' => '함께 읽을 도서를 선택해주세요.',
  'BOOK_NOT_FOUND' => '선택한 도서를 찾을 수 없습니다.',
  'UNAUTHORIZED' => '로그인이 만료되었습니다. 다시 로그인해주세요.',
  _ when error.statusCode == 400 => '입력한 방 정보를 확인해주세요.',
  _ when error.statusCode == 409 => '같은 이름의 방이 이미 있거나 방 상태가 변경되었습니다.',
  _ when error.statusCode != null && error.statusCode! >= 500 =>
  '방을 만드는 중 서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
  _ => '요청을 처리하지 못했습니다. 잠시 후 다시 시도해주세요.',
};

/// 공유 메모 댓글 창 — 방 뷰어의 독서노트(메모 탭)에서도 같은 창을 연다
Future<void> showSharedNoteComments(
    BuildContext context,
    ReadingRoomRepository repository,
    int roomId,
    SharedRoomNote note,
    ) => showDialog<void>(
  context: context,
  barrierColor: Colors.transparent,
  builder: (_) => Dialog(
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    clipBehavior: Clip.antiAlias,
    child: _SharedNoteComments(repository: repository, roomId: roomId, note: note, bodyMemoStyle: true),
  ),
);

/// 내 독서방 목록을 못 불러왔을 때 격자 위에 뜨는 작은 안내 (점선 [+] 칸은 그대로 보임)
class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4F4),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.cloud_off_outlined,
          size: 18,
          color: Color(0xFFB85C5C),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _roomListErrorMessage(error),
            style: const TextStyle(fontSize: 13, color: Color(0xFF8A4A4A)),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    ),
  );
}

class _JoinRoomProfileScreen extends StatefulWidget {
  const _JoinRoomProfileScreen({required this.repository, required this.pending});
  final ReadingRoomRepository repository;
  final _PendingRoomJoin pending;
  @override
  State<_JoinRoomProfileScreen> createState() => _JoinRoomProfileScreenState();
}

class _JoinRoomProfileScreenState extends State<_JoinRoomProfileScreen> {
  late final TextEditingController _name;
  Uint8List? _photo;
  String? _photoName;
  String? _defaultPhotoUrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final nickname = context.read<RidiStore>().nickname;
    _defaultPhotoUrl = context.read<RidiStore>().profileImageUrl;
    _name = TextEditingController(text: nickname);
    _name.selection = TextSelection.collapsed(offset: nickname.length);
  }

  @override
  void dispose() { _name.dispose(); super.dispose(); }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery,
        maxWidth: 1200, maxHeight: 1200, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() { _photo = bytes; _photoName = file.name; });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) { setState(() => _error = '이름을 입력해주세요.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      final result = await widget.repository.joinWithProfile(
        code: widget.pending.code,
        password: widget.pending.password,
        roomNickname: name,
        bytes: _photo,
        filename: _photoName,
        contentType: (_photoName ?? '').toLowerCase().endsWith('.png')
            ? 'image/png'
            : (_photoName ?? '').toLowerCase().endsWith('.webp')
            ? 'image/webp' : 'image/jpeg',
      );
      if (mounted) Navigator.of(context).pop(result.room);
    } on ApiException catch (error) {
      if (!mounted) return;
      final message = _roomJoinErrorMessage(error);
      final detail = error.message == message ? message : '$message\n${error.message}';
      setState(() => _error = error.requestId == null
          ? detail : '$detail\n오류 확인 번호: ${error.requestId}');
    } catch (error, stackTrace) {
      debugPrint('Room profile/join failed: $error\n$stackTrace');
      if (mounted) setState(() => _error = '입장 처리 결과를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('방 프로필 설정')),
      bottomNavigationBar: SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(onPressed: _saving ? null : _save,
            child: Text(_saving ? '저장 중…' : '완료하고 방 입장')),
      )),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text(widget.pending.validation.roomName, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text('이 방에서 사용할 사진과 이름을 설정해주세요.'),
        const SizedBox(height: 28),
        Center(child: InkWell(onTap: _saving ? null : _pickPhoto,
          borderRadius: BorderRadius.circular(60),
          child: CircleAvatar(radius: 56,
              backgroundImage: _photo != null ? MemoryImage(_photo!)
                  : _defaultPhotoUrl?.trim().isNotEmpty == true
                  ? NetworkImage(widget.repository.absoluteUrl(_defaultPhotoUrl!)) : null,
              child: _photo == null && _defaultPhotoUrl?.trim().isNotEmpty != true
                  ? const Icon(Icons.add_a_photo_outlined, size: 32) : null),
        )),
        const SizedBox(height: 24),
        TextField(controller: _name, enabled: !_saving, maxLength: 40,
            decoration: const InputDecoration(labelText: '이 방에서 사용할 이름')),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]),
    ),
  );
}

/// Embedded comments view for the reader's existing notes window.
Widget buildSharedNoteCommentsPanel({
  required ReadingRoomRepository repository,
  required int roomId,
  required SharedRoomNote note,
  required VoidCallback onClose,
}) => _SharedNoteComments(
  repository: repository, roomId: roomId, note: note,
  embedded: true, bodyMemoStyle: true, onClose: onClose,
);

Future<void> showSharedMemoWithComments(BuildContext context,
    ReadingRoomRepository repository, int roomId, List<SharedRoomNote> notes) async {
  if (notes.isEmpty) return;
  int index = 0;
  await showDialog<void>(context: context, builder: (dc) => StatefulBuilder(
    builder: (_, update) => Dialog(
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: _SharedNoteComments(key: ValueKey(notes[index].id),
        repository: repository, roomId: roomId, note: notes[index], bodyMemoStyle: true, bodyAccess: true,
        navigation: notes.length <= 1 ? null : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(tooltip: '이전 메모', icon: const Icon(Icons.chevron_left),
              onPressed: index == 0 ? null : () { FocusScope.of(dc).unfocus(); update(() => index--); }),
          Text('${index + 1} / ${notes.length}', style: const TextStyle(fontSize: 13)),
          IconButton(tooltip: '다음 메모', icon: const Icon(Icons.chevron_right),
              onPressed: index == notes.length - 1 ? null : () { FocusScope.of(dc).unfocus(); update(() => index++); }),
        ]),
      ),
    ),
  ));
}
