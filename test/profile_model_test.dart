import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance_mobile/models/profile_model.dart';

void main() {
  test('parses profile fields and gracefully accepts missing optional values', () {
    final profile = StaffProfile.fromJson({
      'name': 'Amina Hassan',
      'email': 'amina@example.test',
      'organization': null,
      'phone': '',
      'employee_id': null,
      'role': 'staff',
      'is_active': true,
      'created_at': '2026-10-01T09:30:00Z',
    });

    expect(profile.name, 'Amina Hassan');
    expect(profile.email, 'amina@example.test');
    expect(profile.organization, isNull);
    expect(profile.phone, isNull);
    expect(profile.employeeId, isNull);
    expect(profile.role, 'staff');
    expect(profile.isActive, isTrue);
    expect(profile.createdAt, DateTime.parse('2026-10-01T09:30:00Z'));
  });
}
