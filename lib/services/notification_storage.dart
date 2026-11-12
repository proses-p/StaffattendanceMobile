import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'],
        title: json['title'],
        body: json['body'],
        timestamp: DateTime.parse(json['timestamp']),
        isRead: json['isRead'] ?? false,
      );
}

class NotificationStorage {
  static const String _key = 'staff_app_notifications';

  // Hifadhi notification mpya
  static Future<void> addNotification(String title, String body) async {
    final prefs = await SharedPreferences.getInstance();
    final List<AppNotification> current = await getNotifications();

    current.insert(
      0, // Weka mpya juu kabisa
      AppNotification(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        body: body,
        timestamp: DateTime.now(),
        isRead: false,
      ),
    );

    final String encoded = jsonEncode(current.map((e) => e.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  // Leta notifications zote
  static Future<List<AppNotification>> getNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_key);
    if (data == null) return [];

    final List<dynamic> decoded = jsonDecode(data);
    return decoded.map((e) => AppNotification.fromJson(e)).toList();
  }

  // Hesabu ambazo hazijasomwa (kwa ajili ya namba kwenye kengele)
  static Future<int> getUnreadCount() async {
    final list = await getNotifications();
    return list.where((n) => !n.isRead).length;
  }

  // Ziweke zote kama zimesomwa mtu akifungua ukurasa
  static Future<void> markAllAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getNotifications();
    for (var n in list) {
      n.isRead = true;
    }
    final String encoded = jsonEncode(list.map((e) => e.toJson()).toList());
    await prefs.setString(_key, encoded);
  }
}
