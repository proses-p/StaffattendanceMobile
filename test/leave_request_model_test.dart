import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance_mobile/models/leave_request_model.dart';

void main() {
  test('parses persisted status, dates, reason and administrator note', () {
    final request = LeaveRequest.fromJson({
      'id': 42,
      'leave_type': 'Leave',
      'start_date': '2026-11-02',
      'end_date': '2026-11-03',
      'reason': 'Family commitment.',
      'status': 'approved',
      'decision_note': 'Approved.',
      'submitted_at': '2026-10-28T10:00:00Z',
    });

    expect(request.id, 42);
    expect(request.startDate, DateTime(2026, 11, 2));
    expect(request.endDate, DateTime(2026, 11, 3));
    expect(request.reason, 'Family commitment.');
    expect(request.status, 'approved');
    expect(request.decisionNote, 'Approved.');
  });
}
