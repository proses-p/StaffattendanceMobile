import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance_mobile/models/user_status_model.dart';

void main() {
  test('shows an empty duration before check in', () {
    final status = UserStatusModel.fromJson({
      'attendance_state': 'not_started',
      'check_in_time': '--:-- --',
      'check_out_time': '--:-- --',
      'worked_hours': '--',
      'is_checked_in': false,
    });

    expect(status.workedHoursAt(DateTime(2026, 10, 17, 10, 50)), '--');
  });

  test('shows elapsed hours using complete check-in timestamp', () {
    final status = UserStatusModel.fromJson({
      'check_in_at': '2026-10-17T08:15:00+03:00',
      'check_out_at': null,
      'check_in_time': '08:15 AM',
      'check_out_time': '--:-- --',
      'is_checked_in': true,
    });

    expect(
      status.workedHoursAt(DateTime.parse('2026-10-17T10:50:00+03:00')),
      '02h 35m',
    );
  });

  test('shows final worked duration from the check-in and check-out dates', () {
    final status = UserStatusModel.fromJson({
      'attendance_date': '2026-10-17',
      'check_in_at': '2026-10-17T08:15:00+03:00',
      'check_out_at': '2026-10-17T16:30:00+03:00',
      'check_in_time': '08:15 AM',
      'check_out_time': '04:30 PM',
      'worked_hours': '08h 15m',
      'is_checked_in': false,
    });

    expect(status.workedHoursAt(DateTime(2026, 10, 18)), '08h 15m');
  });
}
