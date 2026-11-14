import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const _dailyRemindersKey = 'daily_attendance_reminders_enabled';
  static const _scheduledStartKey = 'attendance_reminder_start_time';
  static const _scheduledEndKey = 'attendance_reminder_end_time';
  static const _scheduledDaysKey = 'attendance_reminder_working_days';
  static const _scheduledHolidayKey = 'attendance_reminder_is_holiday_today';

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
    if (!await dailyRemindersEnabled()) {
      await _notificationsPlugin.cancel(id: id);
      return;
    }

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

  }

  Future<bool> dailyRemindersEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_dailyRemindersKey) ?? true;
  }

  Future<void> setDailyRemindersEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_dailyRemindersKey, enabled);

    if (!enabled) {
      for (final id in [1, 2, ...List.generate(14, (index) => 100 + index)]) {
        await _notificationsPlugin.cancel(id: id);
      }
      return;
    }

    final startTime = preferences.getString(_scheduledStartKey);
    final endTime = preferences.getString(_scheduledEndKey);
    final workingDays = preferences.getStringList(_scheduledDaysKey);
    if (startTime != null && endTime != null && workingDays != null) {
      await syncScheduleReminders(
        startTime: startTime,
        endTime: endTime,
        workingDays: workingDays,
        isHolidayToday:
            preferences.getBool(_scheduledHolidayKey) ?? false,
      );
    } else {
      await scheduleDailyReminder(
        id: 1,
        title: 'Reminder of office check in',
        body: 'Hello, remember to check in now, since you are near the office campus',
        hour: 8,
        minute: 0,
      );
      await scheduleDailyReminder(
        id: 2,
        title: 'Reminder of office check out',
        body: 'Hi!, remember to check out',
        hour: 17,
        minute: 0,
      );
    }
  }

  Future<void> syncScheduleReminders({
    required String? startTime,
    required String? endTime,
    required List<String> workingDays,
    bool isHolidayToday = false,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_scheduledStartKey, startTime ?? '');
    await preferences.setString(_scheduledEndKey, endTime ?? '');
    await preferences.setStringList(_scheduledDaysKey, workingDays);
    await preferences.setBool(_scheduledHolidayKey, isHolidayToday);

    for (final id in [1, 2, ...List.generate(14, (index) => 100 + index)]) {
      await _notificationsPlugin.cancel(id: id);
    }

    if (!await dailyRemindersEnabled()) return;

    final start = _parseTime(startTime);
    final end = _parseTime(endTime);
    if (start == null || end == null) return;
    if (workingDays.isEmpty) {
      await scheduleDailyReminder(
        id: 1,
        title: 'Reminder of office check in',
        body: 'Hello, remember to check in now, since you are near the office campus',
        hour: start.$1,
        minute: start.$2,
      );
      await scheduleDailyReminder(
        id: 2,
        title: 'Reminder of office check out',
        body: 'Hi!, remember to check out',
        hour: end.$1,
        minute: end.$2,
      );
      return;
    }

    const weekdayNumbers = {
      'monday': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'friday': DateTime.friday,
      'saturday': DateTime.saturday,
      'sunday': DateTime.sunday,
    };
    final weekdays = workingDays
        .map((day) => weekdayNumbers[day.toLowerCase()])
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();

    for (final weekday in weekdays) {
      await _scheduleWeeklyReminder(
        id: 100 + ((weekday - 1) * 2),
        title: 'Reminder of office check in',
        body: 'Hello, remember to check in now, since you are near the office campus',
        weekday: weekday,
        hour: start.$1,
        minute: start.$2,
        skipToday:
            isHolidayToday && weekday == tz.TZDateTime.now(tz.local).weekday,
      );
      await _scheduleWeeklyReminder(
        id: 101 + ((weekday - 1) * 2),
        title: 'Reminder of office check out',
        body: 'Hi!, remember to check out',
        weekday: weekday,
        hour: end.$1,
        minute: end.$2,
        skipToday:
            isHolidayToday && weekday == tz.TZDateTime.now(tz.local).weekday,
      );
    }
  }

  Future<void> _scheduleWeeklyReminder({
    required int id,
    required String title,
    required String body,
    required int weekday,
    required int hour,
    required int minute,
    bool skipToday = false,
  }) async {
    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _nextInstanceOfWeekdayTime(
        weekday,
        hour,
        minute,
        skipToday: skipToday,
      ),
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
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  (int, int)? _parseTime(String? time) {
    if (time == null) return null;
    final parts = time.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return (hour, minute);
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

  tz.TZDateTime _nextInstanceOfWeekdayTime(
    int weekday,
    int hour,
    int minute, {
    bool skipToday = false,
  }) {
    final now = tz.TZDateTime.now(tz.local);
    var daysUntil = (weekday - now.weekday) % DateTime.daysPerWeek;
    if (skipToday && daysUntil == 0) {
      daysUntil = DateTime.daysPerWeek;
    }
    var scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute)
            .add(Duration(days: daysUntil));
    if (!scheduledDate.isAfter(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }
    return scheduledDate;
  }
}
