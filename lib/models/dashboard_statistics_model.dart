class DashboardStatistics {
  const DashboardStatistics({
    required this.reportingPeriod,
    required this.overtimeMinutes,
    required this.onTimeRatePercent,
    required this.totalWorkedMinutes,
    required this.attendanceRatePercent,
    required this.approvedLeaveDays,
    required this.incompleteDays,
    required this.absentDays,
    required this.hasAttendanceHistory,
    required this.unavailableReasons,
  });

  final String reportingPeriod;
  final int? overtimeMinutes;
  final double? onTimeRatePercent;
  final int totalWorkedMinutes;
  final double? attendanceRatePercent;
  final double? approvedLeaveDays;
  final int? incompleteDays;
  final int? absentDays;
  final bool hasAttendanceHistory;
  final Map<String, String> unavailableReasons;

  factory DashboardStatistics.fromJson(Map<String, dynamic> json) {
    final period = _asMap(json['reporting_period']);
    final reasons = _asMap(json['unavailable_reasons']);
    final totalWorkedMinutes = _integer(json['total_worked_minutes']);
    final hasAttendanceHistory = json['has_attendance_history'];

    if (totalWorkedMinutes == null ||
        totalWorkedMinutes < 0 ||
        hasAttendanceHistory is! bool ||
        period?['label'] is! String) {
      throw const FormatException('Dashboard statistics are incomplete.');
    }

    return DashboardStatistics(
      reportingPeriod: period?['label']?.toString() ?? '',
      overtimeMinutes: _integer(json['overtime_minutes']),
      onTimeRatePercent: _decimal(json['on_time_rate_percent']),
      totalWorkedMinutes: totalWorkedMinutes,
      attendanceRatePercent: _decimal(json['attendance_rate_percent']),
      approvedLeaveDays: _decimal(json['approved_leave_days']),
      incompleteDays: _integer(json['incomplete_days']),
      absentDays: _integer(json['absent_days']),
      hasAttendanceHistory: hasAttendanceHistory,
      unavailableReasons: {
        for (final entry
            in reasons?.entries ?? const <MapEntry<String, dynamic>>[])
          if (entry.value != null && entry.value.toString().isNotEmpty)
            entry.key: entry.value.toString(),
      },
    );
  }

  String formatMinutes(int? minutes) {
    if (minutes == null) return 'Not configured';
    return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static int? _integer(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return value is String ? int.tryParse(value) : null;
  }

  static double? _decimal(dynamic value) {
    if (value is num) return value.toDouble();
    return value is String ? double.tryParse(value) : null;
  }
}
