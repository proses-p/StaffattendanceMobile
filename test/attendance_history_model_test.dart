import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance_mobile/models/attendance_history_model.dart';

void main() {
  test('sorts history newest first and calculates actual elapsed time', () {
    final page = AttendanceHistoryPage.fromJson({
      'records': [
        {
          'attendance_date': '2026-10-16',
          'check_in_at': '2026-10-16T08:15:00+03:00',
          'check_out_at': '2026-10-16T16:40:00+03:00',
          'check_in_time': '08:15 AM',
          'check_out_time': '04:40 PM',
          'sign_in_location': 'Main Office',
          'sign_out_location': 'Main Office',
        },
        {
          'attendance_date': '2026-10-17',
          'check_in_at': '2026-10-17T08:30:00+03:00',
          'check_out_at': null,
          'check_in_time': '08:30 AM',
          'check_out_time': null,
          'sign_in_location': null,
          'sign_out_location': null,
        },
      ],
      'current_page': 1,
      'last_page': 2,
      'per_page': 6,
      'total': 8,
    });

    expect(page.records.first.attendanceDate, DateTime(2026, 10, 17));
    expect(page.records.last.workingHours, '8h 25m');
    expect(page.records.first.workingHours, 'In progress');
    expect(page.records.first.checkOutAt, isNull);
    expect(page.records.first.signInLocation, isNull);
    expect(page.records.first.signOutLocation, isNull);
    expect(page.hasPreviousPage, isFalse);
    expect(page.hasNextPage, isTrue);
    expect(page.perPage, 6);
  });

  test('disables both pagination directions on the only page', () {
    final page = AttendanceHistoryPage.fromJson({
      'records': <Map<String, dynamic>>[],
      'current_page': 1,
      'last_page': 1,
      'per_page': 6,
      'total': 0,
    });

    expect(page.hasPreviousPage, isFalse);
    expect(page.hasNextPage, isFalse);
    expect(page.total, 0);
  });
}
