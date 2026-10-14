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

final _notificationReadRevision = ValueNotifier<int>(0);
final _notificationUnreadCounts = ValueNotifier<Map<String,int>>({});
void _publishUnreadCount(String account, List<AppNotification> items) {
  if (account.isEmpty) return;
  _notificationUnreadCounts.value = {
    ..._notificationUnreadCounts.value,
    account: items.where((item) => !item.read).length,
  };
}

class UnreadNotificationBadge extends StatefulWidget {
  const UnreadNotificationBadge({super.key, required this.child});
  final Widget child;

  @override
  State<UnreadNotificationBadge> createState() =>
      _UnreadNotificationBadgeState();
}

class _UnreadNotificationBadgeState extends State<UnreadNotificationBadge>
    with WidgetsBindingObserver {
  var _unread = 0;
  RidiStore? _store;
  String _account = '';
  Timer? _timer;
  bool _fetching = false;
  bool _refreshPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationReadRevision.addListener(_requestRefresh);
    _notificationUnreadCounts.addListener(_countChanged);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) _requestRefresh();
    });
    Future.microtask(() {
      if (!mounted) return;
      _store = context.read<RidiStore>();
      _store!.addListener(_sessionChanged);
      _sessionChanged();
    });
  }

  void _countChanged() {
    if (!mounted) return;
    final count = _notificationUnreadCounts.value[_account] ?? 0;
    if (_unread != count) setState(() => _unread = count);
  }

  void _sessionChanged() {
    final store = _store;
    final account = store != null && store.loggedIn ? store.username : '';
    if (account != _account) {
      _account = account;
      if (mounted) setState(() => _unread = _notificationUnreadCounts.value[account] ?? 0);
      _requestRefresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _requestRefresh();
  }

  void _requestRefresh() => unawaited(_refresh());

  Future<void> _refresh() async {
    if (!mounted || _account.isEmpty) return;
    if (_fetching) { _refreshPending = true; return; }
    _fetching = true;
    final account = _account;
    final revision = _notificationReadRevision.value;
    final token = _store?.accessToken;
    try {
      final items = await NotificationRepository(ApiClient(tokenProvider: () => token)).list();
      if (mounted && account == _account && revision == _notificationReadRevision.value) {
        _publishUnreadCount(account, items);
      }
    } catch (_) {
      // Keep the last known unread state during a temporary network failure.
    } finally {
      _fetching = false;
      if (_refreshPending && mounted) {
        _refreshPending = false;
        _requestRefresh();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _store?.removeListener(_sessionChanged);
    _notificationReadRevision.removeListener(_requestRefresh);
    _notificationUnreadCounts.removeListener(_countChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      widget.child,
      if (_unread > 0)
        Positioned(right: -4, top: -3,
            child: Container(width: 9, height: 9,
                decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1)))),
    ],
  );
}

class _ServerNotificationsScreenState extends State<ServerNotificationsScreen> {
  late final NotificationRepository _repository;
  late Future<List<AppNotification>> _notifications;
  @override
  void initState() {
    super.initState();
    _repository = NotificationRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    _notifications = _loadNotifications();
  }

  Future<List<AppNotification>> _loadNotifications() async {
    final store = context.read<RidiStore>();
    final account = store.username;
    final items = await _repository.list();
    if (mounted && store.loggedIn && store.username == account) _publishUnreadCount(account, items);
    return items;
  }

  void _reload() {
    if (mounted) setState(() => _notifications = _loadNotifications());
  }
  int? _openingNotificationId;

  Future<void> _markReadQuietly(AppNotification notification) async {
    if (notification.read) return;
    try {
      await _repository.markRead(notification.id);
      _notificationReadRevision.value++;
      if (mounted) _reload();
    } catch (error) {
      debugPrint('[Notification navigation] read failed: ${error.runtimeType}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          error is ApiException ? '읽음 처리 실패: ${error.message}' : '읽음 처리 중 오류가 발생했습니다.')));
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
          onPressed: () async {
            try {
              await _repository.markAllRead();
              _notificationReadRevision.value++;
              _reload();
            } on ApiException catch (error) {
              _error(error);
            }
          },
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
    body: FutureBuilder<List<AppNotification>>(
      future: _notifications,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(
            child: OutlinedButton(
              onPressed: _reload,
              child: const Text('다시 시도'),
            ),
          );
        final items = snapshot.data ?? const [];
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
          onRefresh: () async => _reload(),
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
