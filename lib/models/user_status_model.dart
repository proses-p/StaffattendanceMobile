
import 'dashboard_statistics_model.dart';

const _emptyAttendanceTime = '--:-- --';

class UserStatusModel {
  final String userName;
  final String currentTime;
  final String currentDate;
  final String workedHours;
  final String checkInTime;
  final String checkOutTime;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final bool isCheckedIn;
  final DashboardStatistics? statistics;
  final String? shiftName;
  final String? shiftStartTime;
  final String? shiftEndTime;
  final List<String> workingDays;
  final bool isWorkingDayToday;
  final bool hasWorkSchedule;

  UserStatusModel({
    required this.userName,
    required this.currentTime,
    required this.currentDate,
    required this.workedHours,
    required this.checkInTime,
    required this.checkOutTime,
    required this.checkInAt,
    required this.checkOutAt,
    required this.isCheckedIn,
    required this.statistics,
    required this.shiftName,
    required this.shiftStartTime,
    required this.shiftEndTime,
    required this.workingDays,
    required this.isWorkingDayToday,
    required this.hasWorkSchedule,
  });

  bool get hasCheckedIn =>
      checkInAt != null || checkInTime != _emptyAttendanceTime;

  bool get hasCheckedOut =>
      checkOutAt != null || checkOutTime != _emptyAttendanceTime;

  String workedHoursAt(DateTime now) {
    if (!hasCheckedIn || (isCheckedIn && checkInAt == null)) {
      return '--';
    }

    if (!isCheckedIn && checkOutAt == null) {
      return '--';
    }

    final start = checkInAt!;
    final end = checkOutAt ?? now;
    final elapsed = end.difference(start);
    if (elapsed.isNegative) {
      return '--';
    }

    final minutes = elapsed.inMinutes;
    return '${(minutes ~/ 60).toString().padLeft(2, '0')}h '
        '${(minutes % 60).toString().padLeft(2, '0')}m';
  }

  factory UserStatusModel.fromJson(Map<String, dynamic> json) {
    final checkInAt = _parseTimestamp(json['check_in_at']);
    final checkOutAt = _parseTimestamp(json['check_out_at']);
    final checkInTime = json['check_in_time']?.toString() ?? _emptyAttendanceTime;
    final checkOutTime =
        json['check_out_time']?.toString() ?? _emptyAttendanceTime;
    final hasCheckIn = checkInAt != null || checkInTime != _emptyAttendanceTime;
    final hasCheckOut =
        checkOutAt != null || checkOutTime != _emptyAttendanceTime;

    return UserStatusModel(
      userName: json['user_name']?.toString() ?? 'Staff',
      currentTime: json['current_time']?.toString() ?? _emptyAttendanceTime,
      currentDate: json['current_date']?.toString() ?? '',
      workedHours: json['worked_hours']?.toString() ?? '--',
      checkInTime: checkInTime,
      checkOutTime: checkOutTime,
      checkInAt: checkInAt,
      checkOutAt: checkOutAt,
      isCheckedIn: hasCheckIn && !hasCheckOut,
      statistics: json['statistics'] is Map
          ? DashboardStatistics.fromJson(
              Map<String, dynamic>.from(json['statistics'] as Map),
            )
          : null,
      shiftName: json['shift_name']?.toString(),
      shiftStartTime: json['start_time']?.toString(),
      shiftEndTime: json['end_time']?.toString(),
      workingDays: json['working_days'] is List
          ? (json['working_days'] as List)
              .map((day) => day.toString())
              .toList()
          : const [],
      isWorkingDayToday: json['is_working_day_today'] == true,
      hasWorkSchedule: json['has_work_schedule'] == true,
    );
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is! String || value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }
}