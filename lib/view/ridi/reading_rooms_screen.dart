import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
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
  bool _onlyAvailable = false;
  bool _joinFlowInProgress = false;
  int? _openingRoomId;

  @override
  void initState() {
    super.initState();
    _repository = ReadingRoomRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    _rooms = _loadRooms(++_roomRevision);
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
    if (mounted && revision == _roomRevision) {
      _roomCache = List.unmodifiable(rooms);
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

  Future<void> _open(ReadingRoom room) async {
    if (_openingRoomId == room.id) return;
    _openingRoomId = room.id;
    try {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              ReadingRoomDetailScreen(repository: _repository, roomId: room.id),
        ),
      );
      if (changed == true && mounted) _reload();
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
    final result = await showDialog<ReadingRoomJoinResult>(
      context: context,
      builder: (_) => _JoinRoomByCodeDialog(repository: _repository),
    );
    if (!mounted || result == null || _joinFlowInProgress) return;
    _joinFlowInProgress = true;
    try {
      // The join response is rendered only after /my confirms the committed
      // membership. This avoids navigating to a stale detail route after a
      // proxy retry or an eventual DB read.
      await _reloadAsync();
      if (!mounted) return;
      ReadingRoom? room;
      for (final candidate in _roomCache) {
        if (candidate.id == result.room.id) {
          room = candidate;
          break;
        }
      }
      if (room == null) {
        throw ApiException('Joined room is missing from the refreshed list.');
      }
      if (result.alreadyJoined && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미 참여 중인 독서방입니다. 방을 열었습니다.')),
        );
      }
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
          onSelected: (value) => setState(() => _onlyAvailable = value),
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: false,
              checked: !_onlyAvailable,
              child: const Text('최신순 전체'),
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
              childAspectRatio: 1,
            ),
            itemCount: rooms.length + 1,
            itemBuilder: (context, index) {
              if (index == rooms.length) return _AddRoomTile(onTap: _create);
              final room = rooms[index];
              return _RoomTile(
                room: room,
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

/// 내 독서방 한 칸 — 큰 카드: 공개/비공개 아이콘 · 이름 · 소개 · 방장 · 인원 (방장은 오른쪽 위 삭제)
class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.onTap, this.onDelete});
  final ReadingRoom room;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF1F3F8),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  room.isPublic ? Icons.public : Icons.lock_outline,
                  size: 22,
                  color: const Color(0xFF6B7488),
                ),
                const Spacer(),
                if (onDelete != null)
                  IconButton(
                    tooltip: '독서방 전체 삭제',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: onDelete,
                  ),
              ],
            ),
            const Spacer(),
            Text(
              room.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              room.description?.isNotEmpty == true
                  ? room.description!
                  : '함께 읽는 방',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B6B6B)),
            ),
            const SizedBox(height: 10),
            Text(
              '${room.ownerNickname} · ${room.members}/${room.maxMembers}명${room.bookId == null ? '' : ' · 대표 도서'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A)),
            ),
          ],
        ),
      ),
    ),
  );
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
  final _password = TextEditingController();
  late final ReadingRoomRepository _repository;
  late Future<List<Book>> _books;
  final List<Book> _picked = [];
  int _maxMembers = 6;
  bool _passwordOn = false;
  Uint8List? _imageBytes;
  String? _imageName;
  String? _imageType;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
    _password.dispose();
    super.dispose();
  }

  void _toggleBook(Book b) => setState(() {
    final i = _picked.indexWhere((x) => x.id == b.id);
    if (i >= 0) {
      _picked.removeAt(i);
    } else {
      _picked
        ..clear()
        ..add(b);
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
        : _picked.length != 1
        ? '함께 읽을 책을 골라주세요.'
        : _passwordOn && !RegExp(r'^\d{4}$').hasMatch(_password.text)
        ? '비밀번호는 숫자 4자리로 적어주세요.'
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
      final room = await _repository.create({
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'bookId': _picked.first.id,
        'maxMembers': _maxMembers,
        'isPublic': true,
        'spoilerLockEnabled': false,
        'selectedAiFriendType': null,
        'roomNickname': _nickname.text.trim(),
        if (_passwordOn) 'password': _password.text,
      });
      if (_imageBytes != null) {
        try {
          await _repository.uploadMyRoomProfileImage(
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
                      backgroundImage: _imageBytes == null
                          ? null
                          : MemoryImage(_imageBytes!),
                      child: _imageBytes == null
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
                  decoration: _box(context.read<RidiStore>().nickname),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _title('참여 인원', '$_minMembers~$_maxMembersLimit명 · AI 친구는 세지 않아요'),
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
        const SizedBox(height: 20),
        _title('비밀번호 설정', '켜면 코드와 비밀번호를 알아야 들어와요'),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    _passwordOn ? '비밀번호 사용' : '사용 안 함',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const Spacer(),
                  Switch(
                    value: _passwordOn,
                    onChanged: _submitting
                        ? null
                        : (v) => setState(() => _passwordOn = v),
                  ),
                ],
              ),
              if (_passwordOn) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _password,
                  enabled: !_submitting,
                  maxLength: 4,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _box('숫자 4자리'),
                ),
              ],
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
  Widget _bookPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(
        '함께 읽을 책',
        _picked.isEmpty ? '표지를 눌러 골라 주세요 · 여러 권 가능' : '${_picked.length}권 선택',
      ),
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
            final books = snap.data ?? const <Book>[];
            if (books.isEmpty) {
              return const SizedBox(
                height: 212,
                child: Center(child: Text('함께 읽을 수 있는 책이 없어요', style: _hint)),
              );
            }
            return SizedBox(
              height: 212,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: books.length,
                separatorBuilder: (_, _) => const SizedBox(width: 18),
                itemBuilder: (_, i) => _BookPickCover(
                  book: books[i],
                  selected: _picked.any((x) => x.id == books[i].id),
                  onTap: _submitting ? null : () => _toggleBook(books[i]),
                ),
              ),
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
      width: 116,
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
                    width: 110,
                    height: 158,
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
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? _blue : const Color(0xFF222222),
            ),
          ),
          Text(
            book.author ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
          ),
        ],
      ),
    ),
  );
}

/// 코드 입력과 요청 중 상태는 이 다이얼로그가 소유한다. 취소는 null을 반환하는
/// 정상 흐름이며, API 성공일 때만 방 정보를 부모 화면으로 돌려준다.
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
      final result = await widget.repository.join(
        code,
        password: _password.text,
      );
      if (!mounted) return;
      if (result.alreadyJoined) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미 참여 중인 독서방입니다. 방을 열었습니다.')),
        );
      }
      Navigator.of(context).pop(result);
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
  bool _deleting = false;
  bool _updatingProfileImage = false;
  final ImagePicker _imagePicker = ImagePicker();
  @override
  void initState() {
    super.initState();
    _room = widget.repository.detail(widget.roomId);
  }

  void _reload() =>
      setState(() => _room = widget.repository.detail(widget.roomId));

  Future<void> _editMyRoomProfileImage() async {
    if (_updatingProfileImage) return;
    final action = await showModalBottomSheet<_RoomProfileImageAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('갤러리에서 선택'),
              onTap: () =>
                  Navigator.pop(sheetContext, _RoomProfileImageAction.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('방 프로필 사진 삭제'),
              textColor: Colors.red,
              iconColor: Colors.red,
              onTap: () =>
                  Navigator.pop(sheetContext, _RoomProfileImageAction.remove),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('취소'),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() => _updatingProfileImage = true);
    try {
      if (action == _RoomProfileImageAction.remove) {
        await widget.repository.deleteMyRoomProfileImage(widget.roomId);
      } else {
        final image = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1280,
          imageQuality: 85,
        );
        if (image == null) return;
        final validExtension = RegExp(
          r'\.(jpe?g|png|webp)$',
          caseSensitive: false,
        ).hasMatch(image.name);
        final bytes = await image.readAsBytes();
        if (!validExtension || bytes.length > 5 * 1024 * 1024) {
          throw ApiException('JPG, PNG, WEBP 형식의 5MB 이하 이미지만 선택할 수 있습니다.');
        }
        final extension = image.name.split('.').last.toLowerCase();
        final contentType =
            image.mimeType ??
            switch (extension) {
              'png' => 'image/png',
              'webp' => 'image/webp',
              _ => 'image/jpeg',
            };
        await widget.repository.uploadMyRoomProfileImage(
          widget.roomId,
          bytes: bytes,
          filename: image.name,
          contentType: contentType,
        );
      }
      if (mounted) _reload();
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('방 프로필 사진을 변경하지 못했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _updatingProfileImage = false);
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

  Future<void> _edit(ReadingRoom room) async {
    final body = await showRoomEditor(context, room: room);
    if (body == null || !mounted) return;
    try {
      await widget.repository.update(room.id, body);
      _reload();
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  // ---------------- 방 상세 (사용자 그림, 2026-10-06) ----------------
  // 위: ‹ 방 이름 ✎(방장) · 톱니(방장만: 방 정보 수정·코드 재발급·방 삭제) · [방 나가기]
  // 왼쪽: 방 소개(✎ 방장만) + 방 코드 복사 / 멤버 N명 (방장은 다른 멤버 [내보내기], 내 줄을 누르면 이 방 프로필 사진)
  // 오른쪽: 함께 읽는 책 N권 [+ 책 추가] — 책 카드(표지 · 제목 · 저자 · 함께 읽는 중 진행 막대 · [책 보기 ›])
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
    if (!await _confirm(context, '초대 코드를 재발급할까요?', '기존 코드는 더 이상 사용할 수 없습니다.') ||
        !mounted)
      return;
    try {
      await widget.repository.regenerateInviteCode(room.id);
      _reload();
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
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

  void _openBook(ReadingRoom room) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AdvancedBookReaderScreen(
        bookId: room.bookId!,
        readerContext: ReaderContext.readingRoom(room.id),
      ),
    ),
  );

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
                  onPressed: () => _edit(room),
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
              const Text(
                '이 코드를 친구에게 알려주면 바로 들어와요.',
                style: TextStyle(fontSize: 12, color: _gray),
              ),
            ],
          ),
        ],
      ],
    ),
  );

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
                '${members.length}명',
                style: const TextStyle(fontSize: 14, color: _gray),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final m in members)
            SizedBox(
              width: double.infinity, // 줄을 카드 끝까지 → [내보내기]가 오른쪽 끝에 붙는다
              child: InkWell(
                // 내 줄을 누르면 이 방 프로필 사진 바꾸기 ("이 방에서의 내 프로필" 칸 대신)
                onTap: room.joined && m.nickname == me && !_updatingProfileImage
                    ? _editMyRoomProfileImage
                    : null,
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
        room.participants.where((m) => m.nickname == me).firstOrNull ??
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
                onTap: _updatingProfileImage ? null : _editMyRoomProfileImage,
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('방 이름(닉네임) 변경은 서버 기능이 생기면 연결됩니다.')),
    );
  }

  Widget _booksCard(ReadingRoom room) {
    final hasBook = room.bookId != null;
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
                '${hasBook ? 1 : 0}권',
                style: const TextStyle(fontSize: 14, color: _gray),
              ),
              const Spacer(),
              if (room.isOwner)
                OutlinedButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('책 추가는 서버 기능이 생기면 연결됩니다.')),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('책 추가'),
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
            _RoomBookCard(room: room, onOpen: () => _openBook(room)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ReadingRoom>(
    future: _room,
    builder: (context, snapshot) {
      final room = snapshot.data;
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
                        onPressed: () => _edit(room),
                      ),
                  ],
                ),
          actions: [
            if (room != null && room.isOwner)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  tooltip: '방 설정 (방장)',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => _ownerMenu(room),
                ),
              ),
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
                      await widget.repository.joinPublic(room.id);
                      _reload();
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
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
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

/// 함께 읽는 책 카드 — 표지 · 제목 · 저자 · "함께 읽는 중" 진행 막대(내 위치 표시) · [책 보기 ›]
class _RoomBookCard extends StatefulWidget {
  const _RoomBookCard({required this.room, required this.onOpen});
  final ReadingRoom room;
  final VoidCallback onOpen;
  @override
  State<_RoomBookCard> createState() => _RoomBookCardState();
}

class _RoomBookCardState extends State<_RoomBookCard> {
  late final Future<ReadingProgress?> _progress;

  @override
  void initState() {
    super.initState();
    final token = context.read<RidiStore>().accessToken;
    _progress = BookRepository(ApiClient(tokenProvider: () => token))
        .readingProgress(widget.room.bookId!)
        .then<ReadingProgress?>((p) => p)
        .catchError((Object _) => null);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.room.book;
    final me = context.read<RidiStore>().nickname;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFEFEFEF)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCover(url: b?.coverImageUrl, width: 84, height: 122),
          const SizedBox(width: 16),
          Expanded(
            child: FutureBuilder<ReadingProgress?>(
              future: _progress,
              builder: (context, snap) {
                final pct = (snap.data?.progressPercent ?? 0).clamp(0, 100);
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
                          child: const Text('책 보기 ›'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '함께 읽는 중  ·  내 진행 $pct%',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF22B573),
                      ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, c) {
                        final x = (c.maxWidth - 24) * pct / 100;
                        return SizedBox(
                          height: 44,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 0,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: pct / 100,
                                    minHeight: 8,
                                    color: const Color(0xFF22B573),
                                    backgroundColor: const Color(0xFFEDEDED),
                                  ),
                                ),
                              ),
                              // 내 위치 표시 (멤버별 위치는 서버 기능이 생기면 함께)
                              Positioned(
                                left: x,
                                top: 12,
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.arrow_drop_up,
                                      size: 16,
                                      color: Color(0xFFE0A030),
                                    ),
                                    Container(
                                      width: 24,
                                      height: 18,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF1D6),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Text(
                                        me.isEmpty ? '나' : me.characters.first,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFB7791F),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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
  ReadingRoom? room,
}) async {
  final name = TextEditingController(text: room?.name ?? '');
  final description = TextEditingController(text: room?.description ?? '');
  final nickname = TextEditingController();
  int? bookId = room?.bookId;
  var maxMembers = room?.maxMembers ?? 6;
  var isPublic = room?.isPublic ?? true;
  var spoilerLock = room?.spoilerLockEnabled ?? false;
  String? aiFriend = room?.selectedAiFriendType;
  try {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(room == null ? '독서방 만들기' : '방 정보 수정'),
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
                  TextField(
                    controller: nickname,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: '방에서 사용할 별명 (선택)',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      bookId == null ? '함께 읽을 책을 선택하세요' : '대표 도서가 선택되었습니다',
                    ),
                    trailing: const Icon(Icons.menu_book_outlined),
                    onTap: () async {
                      final selected = await Navigator.of(context).push<Book>(
                        MaterialPageRoute(builder: (_) => _RoomBookPicker()),
                      );
                      if (selected != null && context.mounted)
                        setDialogState(() => bookId = selected.id);
                    },
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('스포일러 잠금'),
                    subtitle: const Text('내 읽기 위치 이후의 공유 노트를 숨깁니다.'),
                    value: spoilerLock,
                    onChanged: (value) =>
                        setDialogState(() => spoilerLock = value),
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
                      'roomNickname': nickname.text.trim(),
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
    nickname.dispose();
  }
}

class _RoomBookPicker extends StatefulWidget {
  @override
  State<_RoomBookPicker> createState() => _RoomBookPickerState();
}

class _RoomBookPickerState extends State<_RoomBookPicker> {
  late Future<List<Book>> _books;
  @override
  void initState() {
    super.initState();
    _books = BookRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    ).books();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('대표 도서 선택')),
    body: FutureBuilder<List<Book>>(
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
        final books = snapshot.data ?? const <Book>[];
        if (books.isEmpty) {
          return const Center(child: Text('선택할 수 있는 도서가 없습니다.'));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
          ),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final book = books[index];
            return ListTile(
              leading: SizedBox(
                width: 42,
                child: book.coverImageUrl?.isNotEmpty == true
                    ? Image.network(
                        book.coverImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.menu_book_outlined),
                      )
                    : const Icon(Icons.menu_book_outlined),
              ),
              title: Text(book.title),
              subtitle: Text(
                [
                  if (book.author?.isNotEmpty == true) book.author!,
                  if (book.category?.isNotEmpty == true) book.category!,
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pop(book),
            );
          },
        );
      },
    ),
  );
}

enum _RoomProfileImageAction { gallery, remove }

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
  @override
  void initState() {
    super.initState();
    _notes = widget.repository.sharedNotes(widget.roomId);
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

  void _reload() =>
      setState(() => _notes = widget.repository.sharedNotes(widget.roomId));

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
}

class _SharedNoteComments extends StatefulWidget {
  const _SharedNoteComments({
    required this.repository,
    required this.roomId,
    required this.note,
  });
  final ReadingRoomRepository repository;
  final int roomId;
  final SharedRoomNote note;
  @override
  State<_SharedNoteComments> createState() => _SharedNoteCommentsState();
}

class _SharedNoteCommentsState extends State<_SharedNoteComments> {
  final _text = TextEditingController();
  late Future<List<SharedRoomNoteComment>> _comments;
  bool _sending = false;
  @override
  void initState() {
    super.initState();
    _comments = widget.repository.sharedNoteComments(
      widget.roomId,
      widget.note.id,
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _reload() => setState(
    () => _comments = widget.repository.sharedNoteComments(
      widget.roomId,
      widget.note.id,
    ),
  );
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
        widget.note.id,
        text,
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

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Column(
        children: [
          ListTile(
            title: Text(widget.note.nickname),
            subtitle: Text(
              widget.note.content ?? widget.note.selectedText ?? '',
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<SharedRoomNoteComment>>(
              future: _comments,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done)
                  return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError)
                  return const Center(child: Text('댓글을 불러오지 못했습니다.'));
                return ListView(
                  children: [
                    for (final comment
                        in snapshot.data ?? const <SharedRoomNoteComment>[])
                      ListTile(
                        title: Text(comment.nickname),
                        subtitle: Text(comment.content),
                        trailing: comment.mine
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(comment.id),
                              )
                            : null,
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      hintText: '댓글을 입력하세요',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _sending ? null : _send(),
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _delete(int commentId) async {
    try {
      await widget.repository.deleteSharedNoteComment(
        widget.roomId,
        widget.note.id,
        commentId,
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
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) =>
      _SharedNoteComments(repository: repository, roomId: roomId, note: note),
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
