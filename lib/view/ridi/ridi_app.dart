import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../model/app_notification.dart';
import '../../repository/notification_repository.dart';
import '../../repository/reading_room_repository.dart';
import 'reading_rooms_screen.dart';
import 'ridi_store.dart';

class ServerNotificationsScreen extends StatefulWidget {
  const ServerNotificationsScreen({super.key});
  @override
  State<ServerNotificationsScreen> createState() =>
      _ServerNotificationsScreenState();
}

class UnreadNotificationBadge extends StatefulWidget {
  const UnreadNotificationBadge({super.key, required this.child});
  final Widget child;

  @override
  State<UnreadNotificationBadge> createState() =>
      _UnreadNotificationBadgeState();
}

class _UnreadNotificationBadgeState extends State<UnreadNotificationBadge> {
  var _unread = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        final repository = NotificationRepository(
          ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
        );
        final notifications = await repository.list();
        if (mounted)
          setState(
                () => _unread = notifications.where((item) => !item.read).length,
          );
      } catch (_) {
        // A badge must not prevent the shell from rendering when offline.
      }
    });
  }

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: _unread > 0,
    smallSize: 8,
    backgroundColor: Colors.red,
    child: widget.child,
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
    _notifications = _repository.list();
  }

  void _reload() => setState(() => _notifications = _repository.list());
  bool _opening = false;

  Future<void> _markRead(AppNotification notification) async {
    if (notification.read) return;
    try {
      await _repository.markRead(notification.id);
      if (mounted) _reload();
    } catch (error) {
      // Reading status must never prevent opening the related room.
      debugPrint('[Notifications] markRead failed: ${error.runtimeType}');
    }
  }

  Future<void> _open(AppNotification notification) async {
    if (_opening) return;
    unawaited(_markRead(notification));
    if (notification.type == 'ROOM_REMOVED') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('퇴장한 방에는 들어갈 수 없습니다.')),
      );
      return;
    }
    final roomId = notification.relatedRoomId;
    if (roomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이 알림에 연결된 독서방 정보가 없습니다.')),
      );
      return;
    }
    _opening = true;
    try {
      final rooms = ReadingRoomRepository(
        ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
      );
      await Navigator.of(context).push<Object?>(
        MaterialPageRoute<Object?>(
          builder: (_) => ReadingRoomDetailScreen(
            repository: rooms,
            roomId: roomId,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is ApiException
              ? error.message
              : '독서방을 열지 못했습니다. 다시 시도해주세요.')),
        );
      }
    } finally {
      _opening = false;
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
                trailing: item.read ? null : const CircleAvatar(radius: 4),
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
