import 'dart:async';

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
import 'ridi_store.dart';

String _aiFriendLabel(String type) => switch (type) {
  'HAYU' => '하루 · 공감형',
  'DOHYUN' => '도현 · 분석형',
  'MINA' => '미나 · 질문형',
  _ => type,
};

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
    setState(() => _rooms = load);
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
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ReadingRoomDetailScreen(repository: _repository, roomId: room.id),
      ),
    );
    if (changed == true && mounted) _reload();
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
    final room = await showDialog<ReadingRoom>(
      context: context,
      builder: (_) => _JoinRoomByCodeDialog(repository: _repository),
    );
    if (!mounted || room == null) return;
    _putRoom(room);
    await _open(room);
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
              child: const Text('참여 가능만'),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.key_outlined),
          tooltip: '코드로 입장',
          onPressed: _join,
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('방 만들기'),
    ),
    body: FutureBuilder<List<ReadingRoom>>(
      future: _rooms,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState(error: snapshot.error, onRetry: _reload);
        }
        final rooms = (snapshot.data ?? const [])
            .where((room) => !_onlyAvailable || room.members < room.maxMembers)
            .toList();
        if (rooms.isEmpty) return _EmptyRooms(onCreate: _create, onJoin: _join);
        return RefreshIndicator(
          onRefresh: _reloadAsync,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: rooms.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(
                  '내 독서방',
                  style: Theme.of(context).textTheme.titleLarge,
                );
              }
              final room = rooms[index - 1];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Icon(
                    room.isPublic ? Icons.public : Icons.lock_outline,
                  ),
                  title: Text(room.name),
                  subtitle: Text(
                    '${room.description?.isNotEmpty == true ? room.description : '함께 읽는 방'}\n${room.ownerNickname} · ${room.members}/${room.maxMembers}명${room.bookId == null ? '' : ' · 대표 도서'}',
                  ),
                  isThreeLine: true,
                  trailing: room.isOwner
                      ? IconButton(
                          tooltip: '독서방 전체 삭제',
                          icon: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () => _deleteRoomFromList(room),
                        )
                      : Icon(
                          room.bookId == null
                              ? Icons.chevron_right
                              : Icons.menu_book_outlined,
                        ),
                  onTap: () => _open(room),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

/// A route, rather than a dialog over the room list, deliberately owns the
/// room-create form lifecycle.  No parent Provider is re-provided or disposed.
class CreateReadingRoomScreen extends StatefulWidget {
  const CreateReadingRoomScreen({super.key});

  @override
  State<CreateReadingRoomScreen> createState() =>
      _CreateReadingRoomScreenState();
}

class _CreateReadingRoomScreenState extends State<CreateReadingRoomScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _nickname = TextEditingController();
  late final ReadingRoomRepository _repository;
  Book? _book;
  int _maxMembers = 6;
  bool _isPublic = true;
  bool _spoilerLock = false;
  String? _aiFriend;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = ReadingRoomRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _pickBook() async {
    final selected = await Navigator.of(context)
        .push<Book>(MaterialPageRoute(builder: (_) => _RoomBookPicker()));
    if (!mounted || selected == null) return;
    setState(() => _book = selected);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_name.text.trim().isEmpty || _book == null) {
      setState(
        () => _error = _book == null ? '함께 읽을 도서를 선택해주세요.' : '방 이름을 입력해주세요.',
      );
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
        'bookId': _book!.id,
        'maxMembers': _maxMembers,
        'isPublic': _isPublic,
        'spoilerLockEnabled': _spoilerLock,
        'selectedAiFriendType': _aiFriend,
        'roomNickname': _nickname.text.trim(),
      });
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: Scaffold(
      appBar: AppBar(title: const Text('방 만들기')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            TextField(
              controller: _name,
              enabled: !_submitting,
              maxLength: 100,
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(labelText: '방 이름'),
            ),
            TextField(
              controller: _description,
              enabled: !_submitting,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '방 설명 (선택)'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: !_submitting,
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(_book?.title ?? '함께 읽을 책 선택'),
              subtitle: _book == null
                  ? const Text('서버의 전체 도서 목록에서 선택합니다.')
                  : Text(
                      [_book!.author, _book!.category]
                          .whereType<String>()
                          .where((value) => value.isNotEmpty)
                          .join(' · '),
                    ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _submitting ? null : _pickBook,
            ),
            Row(
              children: [
                const Text('최대 인원'),
                const Spacer(),
                IconButton(
                  onPressed: _submitting || _maxMembers <= 2
                      ? null
                      : () => setState(() => _maxMembers--),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_maxMembers명'),
                IconButton(
                  onPressed: _submitting || _maxMembers >= 10
                      ? null
                      : () => setState(() => _maxMembers++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('공개 방'),
              subtitle: Text(_isPublic ? '공개 목록에 표시됩니다.' : '입장 코드가 필요합니다.'),
              value: _isPublic,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _isPublic = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('스포일러 잠금'),
              value: _spoilerLock,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _spoilerLock = value),
            ),
            DropdownButtonFormField<String?>(
              value: _aiFriend,
              decoration: const InputDecoration(labelText: 'AI 독서친구'),
              items: const [
                DropdownMenuItem(value: null, child: Text('선택 안 함')),
                DropdownMenuItem(value: 'HAYU', child: Text('하루 · 공감형')),
                DropdownMenuItem(value: 'DOHYUN', child: Text('도현 · 분석형')),
                DropdownMenuItem(value: 'MINA', child: Text('미나 · 질문형')),
              ],
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _aiFriend = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nickname,
              enabled: !_submitting,
              maxLength: 40,
              decoration: const InputDecoration(labelText: '방에서 사용할 별명 (선택)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('방 만들기'),
            ),
            TextButton(
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
          ],
        ),
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
  bool _joining = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
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
      final result = await widget.repository.join(code);
      if (!mounted) return;
      if (result.alreadyJoined) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미 참여 중인 독서방입니다. 방을 열었습니다.')),
        );
      }
      Navigator.of(context).pop(result.room);
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
              onTap: () => Navigator.pop(
                sheetContext,
                _RoomProfileImageAction.gallery,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('방 프로필 사진 삭제'),
              textColor: Colors.red,
              iconColor: Colors.red,
              onTap: () => Navigator.pop(
                sheetContext,
                _RoomProfileImageAction.remove,
              ),
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
        final contentType = image.mimeType ?? switch (extension) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('방 프로필 사진을 변경하지 못했습니다.')),
        );
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('방 상세')),
    body: FutureBuilder<ReadingRoom>(
      future: _room,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return _ErrorState(error: snapshot.error, onRetry: _reload);
        final room = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Row(
              children: [
                Icon(room.isPublic ? Icons.public : Icons.lock_outline),
                const SizedBox(width: 8),
                Text(room.isPublic ? '공개 방' : '비공개 방'),
              ],
            ),
            const SizedBox(height: 16),
            Text(room.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  label: Text(
                    room.spoilerLockEnabled ? '스포일러 잠금' : '스포일러 잠금 해제',
                  ),
                ),
                if (room.selectedAiFriendType != null)
                  Chip(
                    avatar: const Icon(Icons.smart_toy_outlined, size: 18),
                    label: Text(_aiFriendLabel(room.selectedAiFriendType!)),
                  ),
              ],
            ),
            if (room.description?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(room.description!),
            ],
            const SizedBox(height: 12),
            Text(
              '방장 ${room.ownerNickname} · ${room.members}/${room.maxMembers}명',
            ),
            if (room.isOwner && room.joinCode != null) ...[
              const Divider(height: 36),
              const Text('입장 코드'),
              const SizedBox(height: 6),
              Row(
                children: [
                  SelectableText(
                    room.joinCode!,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    tooltip: '초대 코드 복사',
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () async {
                      try {
                        await Clipboard.setData(
                          ClipboardData(text: room.joinCode!),
                        );
                      } catch (_) {
                        if (mounted) {
                          _showError(
                            context,
                            ApiException('초대 코드를 복사하지 못했습니다.'),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () async {
                      if (!await _confirm(
                            context,
                            '초대 코드를 재발급할까요?',
                            '기존 코드는 더 이상 사용할 수 없습니다.',
                          ) ||
                          !mounted)
                        return;
                      try {
                        await widget.repository.regenerateInviteCode(room.id);
                        _reload();
                      } on ApiException catch (error) {
                        if (mounted) _showError(context, error);
                      }
                    },
                    child: const Text('재발급'),
                  ),
                ],
              ),
            ],
            const Divider(height: 36),
            if (room.bookId == null)
              const ListTile(
                leading: Icon(Icons.menu_book_outlined),
                title: Text('대표 도서가 없습니다.'),
              )
            else
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('대표 도서 보기'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdvancedBookReaderScreen(
                      bookId: room.bookId!,
                      readerContext: ReaderContext.readingRoom(room.id),
                    ),
                  ),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: const Text('공유 독서노트'),
              subtitle: const Text('참여자와 공유한 메모와 형광펜을 확인하세요.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SharedRoomNotesScreen(
                    repository: widget.repository,
                    roomId: room.id,
                  ),
                ),
              ),
            ),
            const Divider(height: 36),
            Text(
              '참여자 ${room.participants.length}명',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final member in room.participants)
              ListTile(
                leading: CircleAvatar(
                  foregroundImage: member.roomProfileImageUrl?.isNotEmpty == true
                      ? NetworkImage(widget.repository.absoluteUrl(member.roomProfileImageUrl!))
                      : null,
                  child: Text(
                    member.nickname.isEmpty
                        ? '?'
                        : member.nickname.substring(0, 1),
                  ),
                ),
                title: Text(member.nickname),
                subtitle: Text(member.role == 'OWNER' ? '방장' : '참여자'),
                trailing: room.isOwner && member.role != 'OWNER'
                    ? TextButton(
                        onPressed: () async {
                          if (!await _confirm(
                            context,
                            '${member.nickname}님을 내보낼까요?',
                            '이 작업은 되돌릴 수 없습니다.',
                          ))
                            return;
                          try {
                            await widget.repository.kick(
                              room.id,
                              member.userId,
                            );
                            _reload();
                          } on ApiException catch (error) {
                            if (mounted) _showError(context, error);
                          }
                        },
                        child: const Text('내보내기'),
                      )
                    : null,
              ),
            const SizedBox(height: 24),
            if (room.joined)
              OutlinedButton.icon(
                onPressed: _updatingProfileImage ? null : _editMyRoomProfileImage,
                icon: _updatingProfileImage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.account_circle_outlined),
                label: const Text('방 프로필 사진 변경'),
              ),
            if (room.joined) const SizedBox(height: 8),
            if (room.isOwner) ...[
              OutlinedButton.icon(
                onPressed: () => _edit(room),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('방 정보 수정'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _deleting ? null : () => _delete(room),
                icon: const Icon(Icons.delete_outline),
                label: const Text('방 삭제'),
              ),
            ] else if (room.joined)
              OutlinedButton.icon(
                onPressed: () => _leave(room),
                icon: const Icon(Icons.exit_to_app),
                label: const Text('방 나가기'),
              )
            else if (room.isPublic)
              FilledButton.icon(
                onPressed: () async {
                  try {
                    await widget.repository.joinPublic(room.id);
                    _reload();
                  } on ApiException catch (error) {
                    if (mounted) _showError(context, error);
                  }
                },
                icon: const Icon(Icons.login),
                label: const Text('방 참여하기'),
              ),
          ],
        );
      },
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

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms({required this.onCreate, required this.onJoin});
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.groups_outlined, size: 48),
        const SizedBox(height: 12),
        const Text('참여할 공개 방이 없습니다.'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('방 만들기'),
        ),
        TextButton(onPressed: onJoin, child: const Text('코드로 방 입장')),
      ],
    ),
  );
}

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
                    title: const Text('스포일러 방지'),
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
