import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:staff_attendance_mobile/services/notification_storage.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 1. Anzisha Timezone ya Tanzania (Africa/Dar_es_Salaam)
    tz.initializeTimeZones();
    final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneInfo.identifier));

    // 2. Mipangilio ya Android (Named parameter 'settings:')
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(settings: initSettings);

    // 3. Omba ruhusa kwenye simu (Android 13+)
    final androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();
    }
  }

  // KIKUMBUSHO CHA KILA SIKU (Sign In / Sign Out)
  Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _nextInstanceOfTime(hour, minute),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'attendance_channel_id',
          'Attendance Reminders',
          channelDescription: 'Vikumbusho vya kuingia na kutoka kazini',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    await NotificationStorage.addNotification(title, body);

  }

  // KAZI YA MAJARIBIO (Inalia baada ya sekunde 15 kuanzia sasa)
  Future<void> testNotificationIn15Seconds() async {
    final scheduledTime =
        tz.TZDateTime.now(tz.local).add(const Duration(seconds: 15));

    await _notificationsPlugin.zonedSchedule(
      id: 999,
      title: 'Majaribio Yamefanikiwa!',
      body: 'Hii ni notification ya majaribio kutoka Staff Attendance App.',
      scheduledDate: scheduledTime,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'test_channel_id',
          'Test Notifications',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
    await NotificationStorage.addNotification('Majaribio yamefanikiwa', 'Hii ni notification ya majaribio kutoka StaffFlow app');

  }

    // ARIFA YA PAPO HAPO (Kwa majibu ya Admin kutoka kwenye API)
  Future<void> showInstantNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'admin_updates_channel',
          'Office Updates',
          channelDescription: 'Leave request updates and announcements',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
      ),
    );
  }


  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}
