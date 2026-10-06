import '../core/api_client.dart';
import '../model/app_notification.dart';

class NotificationRepository {
  NotificationRepository(this._api);
  final ApiClient _api;
  Future<List<AppNotification>> list() async =>
      (await _api.get<List<AppNotification>>(
        '/api/notifications',
        parse: (json) => (json as List<dynamic>)
            .map(
              (item) => AppNotification.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      )).data ??
      const [];
  Future<void> markRead(int notificationId) =>
      _api.post('/api/notifications/$notificationId/read');
  Future<void> markAllRead() => _api.post('/api/notifications/read-all');
  Future<NotificationSettings> settings() async =>
      (await _api.get<NotificationSettings>(
        '/api/me/notification-settings',
        parse: (json) =>
            NotificationSettings.fromJson(json as Map<String, dynamic>),
      )).data!;
  Future<NotificationSettings> saveSettings(
    NotificationSettings settings,
  ) async => (await _api.put<NotificationSettings>(
    '/api/me/notification-settings',
    body: {
      'friendEnabled': settings.friendEnabled,
      'roomEnabled': settings.roomEnabled,
      'activityEnabled': settings.activityEnabled,
    },
    parse: (json) =>
        NotificationSettings.fromJson(json as Map<String, dynamic>),
  )).data!;
}
