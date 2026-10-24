import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance_mobile/models/dashboard_statistics_model.dart';

void main() {
  test('parses completed hours and keeps unconfigured values unavailable', () {
    final statistics = DashboardStatistics.fromJson({
      'reporting_period': {'label': 'Oct 1 - Oct 22, 2026'},
      'total_worked_minutes': 615,
      'has_attendance_history': true,
      'overtime_minutes': null,
      'on_time_rate_percent': null,
      'attendance_rate_percent': null,
      'approved_leave_days': null,
      'incomplete_days': null,
      'absent_days': null,
      'unavailable_reasons': {
        'overtime': 'Daily required hours are not configured.',
      },
    });

    expect(statistics.reportingPeriod, 'Oct 1 - Oct 22, 2026');
    expect(statistics.totalWorkedMinutes, 615);
    expect(
      statistics.formatMinutes(statistics.overtimeMinutes),
      'Not configured',
    );
    expect(
      statistics.unavailableReasons['overtime'],
      contains('not configured'),
    );
    expect(statistics.hasAttendanceHistory, isTrue);
    expect(statistics.absentDays, isNull);
  });

  test('rejects incomplete totals instead of presenting them as zero', () {
    expect(
      () => DashboardStatistics.fromJson({
        'reporting_period': {'label': 'Oct 1 - Oct 22, 2026'},
        'has_attendance_history': false,
      }),
      throwsFormatException,
    );
  });

  test('maps calculated API statistics into mobile card values', () {
    final statistics = DashboardStatistics.fromJson({
      'reporting_period': {'label': 'Oct 1 - Oct 9, 2026'},
      'total_worked_minutes': 2160,
      'overtime_minutes': 60,
      'on_time_rate_percent': 60.0,
      'attendance_rate_percent': 80.0,
      'approved_leave_days': 1,
      'incomplete_days': 1,
      'absent_days': 1,
      'eligible_scheduled_days': 5,
      'has_attendance_history': true,
      'unavailable_reasons': {},
    });

    expect(statistics.formatMinutes(statistics.overtimeMinutes), '1h 00m');
    expect(statistics.totalWorkedMinutes, 2160);
    expect(statistics.onTimeRatePercent, 60);
    expect(statistics.attendanceRatePercent, 80);
    expect(statistics.approvedLeaveDays, 1);
    expect(statistics.incompleteDays, 1);
    expect(statistics.absentDays, 1);
  });
}
