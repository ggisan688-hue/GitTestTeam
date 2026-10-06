import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../model/app_notification.dart';
import '../../repository/notification_repository.dart';
import '../../repository/reading_room_repository.dart';
import 'friends_screen.dart';
import 'reading_rooms_screen.dart';
import 'ridi_store.dart';

class ServerNotificationsScreen extends StatefulWidget {
  const ServerNotificationsScreen({super.key});
  @override
  State<ServerNotificationsScreen> createState() => _ServerNotificationsScreenState();
}

class UnreadNotificationBadge extends StatefulWidget {
  const UnreadNotificationBadge({super.key, required this.child});
  final Widget child;

  @override
  State<UnreadNotificationBadge> createState() => _UnreadNotificationBadgeState();
}

class _UnreadNotificationBadgeState extends State<UnreadNotificationBadge> {
  var _unread = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        final repository = NotificationRepository(ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken));
        final notifications = await repository.list();
        if (mounted) setState(() => _unread = notifications.where((item) => !item.read).length);
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
  @override void initState() { super.initState(); _repository = NotificationRepository(ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken)); _notifications = _repository.list(); }
  void _reload() => setState(() => _notifications = _repository.list());
  Future<void> _open(AppNotification notification) async {
    if (!notification.read) { try { await _repository.markRead(notification.id); _reload(); } on ApiException catch (error) { if (mounted) _error(error); return; } }
    if (notification.relatedRoomId != null && mounted) {
      final rooms = ReadingRoomRepository(ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken));
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReadingRoomDetailScreen(repository: rooms, roomId: notification.relatedRoomId!)));
    } else if (notification.type.startsWith('FRIEND') && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen()));
    }
  }
  void _error(ApiException error) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('알림'), actions: [TextButton(onPressed: () async { try { await _repository.markAllRead(); _reload(); } on ApiException catch (error) { _error(error); } }, child: const Text('모두 읽음')), IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationSettingsScreen(repository: _repository))))]),
    body: FutureBuilder<List<AppNotification>>(future: _notifications, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: OutlinedButton(onPressed: _reload, child: const Text('다시 시도')));
      final items = snapshot.data ?? const [];
      if (items.isEmpty) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.notifications_none_outlined, size: 44), SizedBox(height: 12), Text('새 알림이 없습니다.')]));
      return RefreshIndicator(onRefresh: () async => _reload(), child: ListView.separated(itemCount: items.length, separatorBuilder: (_, _) => const Divider(height: 1), itemBuilder: (context, index) { final item = items[index]; return ListTile(leading: Icon(item.type.startsWith('FRIEND') ? Icons.person_add_alt_1_outlined : Icons.groups_outlined), title: Text(item.title, style: item.read ? null : const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(item.body), trailing: item.read ? null : const CircleAvatar(radius: 4), onTap: () => _open(item)); }));
    }),
  );
}

class NotificationSettingsScreen extends StatefulWidget { const NotificationSettingsScreen({super.key, required this.repository}); final NotificationRepository repository; @override State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState(); }
class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  late Future<NotificationSettings> _settings;
  @override void initState() { super.initState(); _settings = widget.repository.settings(); }
  Future<void> _save(NotificationSettings current, {bool? friend, bool? room, bool? activity}) async { final next = NotificationSettings(friendEnabled: friend ?? current.friendEnabled, roomEnabled: room ?? current.roomEnabled, activityEnabled: activity ?? current.activityEnabled); try { final saved = await widget.repository.saveSettings(next); if (mounted) setState(() => _settings = Future.value(saved)); } on ApiException catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message))); } }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('알림 설정')), body: FutureBuilder<NotificationSettings>(future: _settings, builder: (context, snapshot) { if (!snapshot.hasData) return const Center(child: CircularProgressIndicator()); final settings = snapshot.data!; return ListView(children: [SwitchListTile(title: const Text('친구 요청 알림'), value: settings.friendEnabled, onChanged: (value) => _save(settings, friend: value)), SwitchListTile(title: const Text('교환독서 방 알림'), value: settings.roomEnabled, onChanged: (value) => _save(settings, room: value)), SwitchListTile(title: const Text('활동 알림'), value: settings.activityEnabled, onChanged: (value) => _save(settings, activity: value))]); }));
}
