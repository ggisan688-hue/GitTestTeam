import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../model/app_notification.dart';
import '../../repository/notification_repository.dart';
import '../../repository/reading_room_repository.dart';
import 'reading_rooms_screen.dart';
import 'advanced_book_reader.dart';
import 'ridi_store.dart';

class ServerNotificationsScreen extends StatefulWidget {
  const ServerNotificationsScreen({super.key});
  @override
  State<ServerNotificationsScreen> createState() =>
      _ServerNotificationsScreenState();
}

// The list and bottom-navigation dot render this same inbox instance.
final _notificationInbox = _NotificationInbox();

class _NotificationInbox extends ChangeNotifier {
  String account = '';
  String? _token;
  List<AppNotification> items = const [];
  Object? error;
  bool loading = false;
  bool saving = false;
  int _session = 0;
  int _request = 0;
  int _revision = 0;
  final Set<int> _pendingReadIds = {};
  Future<void>? _activeWrite;

  int get unreadCount => items.where((item) => !item.read).length;
  NotificationRepository get repository => NotificationRepository(
      ApiClient(tokenProvider: () => _token));

  void bind(String username, String? token) {
    final changed = username != account || token != _token;
    if (!changed) return;
    account = username;
    _token = token;
    _session++;
    _request++;
    _revision++;
    items = const [];
    error = null;
    loading = false;
    saving = false;
    _pendingReadIds.clear();
    _activeWrite = null;
    notifyListeners();
    if (account.isNotEmpty) unawaited(load());
  }

  Future<void> load() async {
    if (account.isEmpty) return;
    final session = _session;
    final request = ++_request;
    final revision = _revision;
    final api = repository;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final loaded = await api.list();
      if (session != _session || request != _request || revision != _revision) return;
      items = loaded.map((n) => _pendingReadIds.contains(n.id) ? _asRead(n) : n).toList();
    } catch (failure) {
      if (session == _session && request == _request && revision == _revision) error = failure;
    } finally {
      if (session == _session && request == _request) {
        loading = false;
        notifyListeners();
      }
    }
  }

  static AppNotification _asRead(AppNotification n) => AppNotification(
    id: n.id, type: n.type, title: n.title, body: n.body, read: true,
    createdAt: n.createdAt, relatedRoomId: n.relatedRoomId,
    relatedUserId: n.relatedUserId, relatedBookId: n.relatedBookId,
    relatedNoteId: n.relatedNoteId,
  );

  Future<void> markRead(int id) => _write(id);
  Future<void> markAllRead() => _write(null);

  Future<void> _write(int? id) async {
    final session = _session;
    // Serialize writes so failure rollback cannot overwrite another read action.
    if (_activeWrite != null) {
      try { await _activeWrite; } catch (_) {}
      if (session != _session) return;
      return _write(id);
    }
    final before = <int,AppNotification>{
      for (final n in items)
        if (!n.read && (id == null || n.id == id)) n.id: n,
    };
    if (before.isEmpty) return;
    final api = repository;
    _revision++;
    _pendingReadIds.addAll(before.keys);
    items = items.map((n) => before.containsKey(n.id) ? _asRead(n) : n).toList();
    saving = true;
    notifyListeners(); // Blue dots and bottom red dot change in this frame.
    final operation = id == null ? api.markAllRead() : api.markRead(id);
    _activeWrite = operation;
    try {
      await operation;
    } catch (_) {
      if (session == _session) {
        items = items.map((n) => before[n.id] ?? n).toList();
      }
      rethrow;
    } finally {
      if (session == _session) {
        _revision++;
        _pendingReadIds.removeAll(before.keys);
        _activeWrite = null;
        saving = false;
        notifyListeners();
      }
    }
  }
}

class UnreadNotificationBadge extends StatefulWidget {
  const UnreadNotificationBadge({super.key, required this.child});
  final Widget child;
  @override
  State<UnreadNotificationBadge> createState() => _UnreadNotificationBadgeState();
}

class _UnreadNotificationBadgeState extends State<UnreadNotificationBadge>
    with WidgetsBindingObserver {
  RidiStore? _store;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      if (!mounted) return;
      _store = context.read<RidiStore>();
      _store!.addListener(_bind);
      _bind();
    });
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          !_notificationInbox.loading) unawaited(_notificationInbox.load());
    });
  }
  void _bind() {
    final store = _store;
    if (store == null) return;
    _notificationInbox.bind(store.loggedIn ? store.username : '', store.accessToken);
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_notificationInbox.load());
  }
  @override
  void dispose() {
    _timer?.cancel();
    _store?.removeListener(_bind);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _notificationInbox,
    builder: (_, __) => Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (_notificationInbox.unreadCount > 0)
          Positioned(right: -4, top: -3,
              child: Container(width: 9, height: 9,
                  decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1)))),
      ],
    ),
  );
}

class _ServerNotificationsScreenState extends State<ServerNotificationsScreen> {
  late final NotificationRepository _repository;
  @override
  void initState() {
    super.initState();
    _repository = NotificationRepository(
        ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken));
    Future.microtask(() {
      if (!mounted) return;
      final store = context.read<RidiStore>();
      _notificationInbox.bind(store.loggedIn ? store.username : '', store.accessToken);
      if (!_notificationInbox.loading) unawaited(_notificationInbox.load());
    });
  }

  void _reload() => unawaited(_notificationInbox.load());
  int? _openingNotificationId;

  Future<void> _markReadQuietly(AppNotification notification) async {
    try {
      await _notificationInbox.markRead(notification.id);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          error is ApiException ? '읽음 처리 실패: ${error.message}' : '읽음 처리를 저장하지 못했습니다.')));
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _notificationInbox.markAllRead();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          error is ApiException ? '모두 읽음 저장 실패: ${error.message}' : '모두 읽음을 저장하지 못해 이전 상태로 되돌렸습니다.')));
    }
  }

  Future<void> _open(AppNotification notification) async {
    if (_openingNotificationId != null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    unawaited(_markReadQuietly(notification));
    if (notification.type == 'ROOM_REMOVED') {
      messenger.showSnackBar(const SnackBar(content: Text('퇴장한 방에는 들어갈 수 없습니다.')));
      return;
    }
    final roomId = notification.relatedRoomId;
    if (roomId == null) {
      messenger.showSnackBar(const SnackBar(content: Text('이 알림에 연결된 독서방 정보가 없습니다.')));
      return;
    }
    setState(() => _openingNotificationId = notification.id);
    var stage = '독서방 확인';
    try {
      final repository = ReadingRoomRepository(
          ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken));
      final memoNotification = notification.type == 'ROOM_MEMO_CREATED' ||
          notification.type == 'ROOM_MEMO_COMMENT';
      final bookId = notification.relatedBookId;
      final noteId = notification.relatedNoteId;
      if (memoNotification && bookId != null && noteId != null) {
        final room = await repository.detail(roomId);
        if (!mounted) return;
        if (!room.joined) {
          messenger.showSnackBar(const SnackBar(content: Text('현재 이 독서방에 참여하고 있지 않습니다.')));
          return;
        }
        if (!room.books.any((item) => item.book.id == bookId)) {
          messenger.showSnackBar(const SnackBar(content: Text('방에서 삭제된 도서입니다.')));
          return;
        }
        stage = '책과 독서노트 열기';
        debugPrint('[Notification navigation] opening notebook');
        await navigator.push(MaterialPageRoute(
          builder: (_) => AdvancedBookReaderScreen(
            bookId: bookId,
            readerContext: ReaderContext.readingRoom(roomId),
            initialNoteId: noteId,
            openInitialComments: notification.type == 'ROOM_MEMO_COMMENT',
          ),
        ));
      } else {
        stage = '독서방 열기';
        await navigator.push(MaterialPageRoute(
          builder: (_) => ReadingRoomDetailScreen(repository: repository, roomId: roomId),
        ));
      }
    } catch (error, stack) {
      debugPrint('[Notification navigation] $stage failed: ${error.runtimeType}');
      debugPrintStack(stackTrace: stack, maxFrames: 8);
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(error is ApiException
            ? '$stage 실패: ${error.message}'
            : '$stage 중 오류가 발생했습니다. (${error.runtimeType})')));
      }
    } finally {
      if (mounted) setState(() => _openingNotificationId = null);
    }
  }

  void _error(ApiException error) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('알림'),
      actions: [
        TextButton(
          onPressed: _markAllRead,
          child: const Text('모두 읽음'),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  NotificationSettingsScreen(repository: _repository),
            ),
          ),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: _notificationInbox,
      builder: (context, _) {
        if (_notificationInbox.items.isEmpty && _notificationInbox.loading)
          return const Center(child: CircularProgressIndicator());
        if (_notificationInbox.items.isEmpty && _notificationInbox.error != null)
          return Center(
            child: OutlinedButton(
              onPressed: _reload,
              child: const Text('다시 시도'),
            ),
          );
        final items = _notificationInbox.items;
        if (items.isEmpty)
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications_none_outlined, size: 44),
                SizedBox(height: 12),
                Text('새 알림이 없습니다.'),
              ],
            ),
          );
        return RefreshIndicator(
          onRefresh: _notificationInbox.load,
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: Icon(
                  switch (item.type) {
                    'ROOM_MEMO_CREATED' => Icons.edit_note_outlined,
                    'ROOM_MEMO_COMMENT' => Icons.chat_bubble_outline,
                    'ROOM_BOOK_ADDED' || 'ROOM_BOOK_REMOVED' => Icons.menu_book_outlined,
                    _ => Icons.groups_outlined,
                  },
                ),
                title: Text(
                  item.title,
                  style: item.read
                      ? null
                      : const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(item.body),
                trailing: _openingNotificationId == item.id
                    ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                    : item.read ? null : const CircleAvatar(radius: 4),
                onTap: () => _open(item),
              );
            },
          ),
        );
      },
    ),
  );
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, required this.repository});
  final NotificationRepository repository;
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late Future<NotificationSettings> _settings;
  @override
  void initState() {
    super.initState();
    _settings = widget.repository.settings();
  }

  Future<void> _save(
      NotificationSettings current, {
        bool? friend,
        bool? room,
        bool? activity,
      }) async {
    final next = NotificationSettings(
      friendEnabled: friend ?? current.friendEnabled,
      roomEnabled: room ?? current.roomEnabled,
      activityEnabled: activity ?? current.activityEnabled,
    );
    try {
      final saved = await widget.repository.saveSettings(next);
      if (mounted) setState(() => _settings = Future.value(saved));
    } on ApiException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('알림 설정')),
    body: FutureBuilder<NotificationSettings>(
      future: _settings,
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final settings = snapshot.data!;
        return ListView(
          children: [

            SwitchListTile(
              title: const Text('독서방 알림'),
              subtitle: const Text('입장, 퇴장, 방장 위임, 도서 추가·삭제'),
              value: settings.roomEnabled,
              onChanged: (value) => _save(settings, room: value),
            ),
            SwitchListTile(
              title: const Text('메모·댓글 알림'),
              subtitle: const Text('방 멤버의 새 메모, 내 메모에 달린 댓글'),
              value: settings.activityEnabled,
              onChanged: (value) => _save(settings, activity: value),
            ),
          ],
        );
      },
    ),
  );
}
