class AppNotification {
  const AppNotification({required this.id, required this.type, required this.title, required this.body, required this.read, required this.createdAt, this.relatedRoomId, this.relatedUserId});
  final int id;
  final String type;
  final String title;
  final String body;
  final bool read;
  final DateTime? createdAt;
  final int? relatedRoomId;
  final int? relatedUserId;
  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: (json['id'] as num).toInt(), type: json['type'] as String, title: json['title'] as String, body: json['body'] as String,
    read: json['read'] == true, createdAt: json['createdAt'] is String ? DateTime.tryParse(json['createdAt'] as String) : null,
    relatedRoomId: (json['relatedRoomId'] as num?)?.toInt(), relatedUserId: (json['relatedUserId'] as num?)?.toInt(),
  );
}

class NotificationSettings {
  const NotificationSettings({required this.friendEnabled, required this.roomEnabled, required this.activityEnabled});
  final bool friendEnabled;
  final bool roomEnabled;
  final bool activityEnabled;
  factory NotificationSettings.fromJson(Map<String, dynamic> json) => NotificationSettings(friendEnabled: json['friendEnabled'] != false, roomEnabled: json['roomEnabled'] != false, activityEnabled: json['activityEnabled'] != false);
}
