import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance_mobile/models/leave_request_model.dart';
import 'package:staff_attendance_mobile/screens/leave_management_screen.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class _FakeLeaveApiService extends ApiService {
  _FakeLeaveApiService(this.requests);

  final List<LeaveRequest> requests;
  bool submitCalled = false;

  @override
  Future<List<LeaveRequest>> fetchLeaveRequests() async => requests;

  @override
  Future<LeaveRequest> submitLeaveRequest({
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    submitCalled = true;
    return LeaveRequest(
      id: 2,
      leaveType: leaveType,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      status: 'pending',
      submittedAt: DateTime(2026, 10, 29),
    );
  }
}

void main() {
  testWidgets('shows own request status and administrator response', (
    tester,
  ) async {
    final apiService = _FakeLeaveApiService([
      LeaveRequest(
        id: 1,
        leaveType: 'Leave',
        startDate: DateTime(2026, 11, 2),
        endDate: DateTime(2026, 11, 3),
        reason: 'Family commitment.',
        status: 'rejected',
        submittedAt: DateTime(2026, 10, 20),
        decisionNote: 'Please choose another date.',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: LeaveManagementScreen(apiService: apiService)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Leave overview'), findsOneWidget);
    expect(find.text('Rejected 1'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);
    await tester.tap(find.text('Leave').first);
    await tester.pumpAndSettle();
    expect(find.text('Family commitment.'), findsOneWidget);
    expect(find.text('Please choose another date.'), findsOneWidget);
  });

  testWidgets('request form validates required dates and reason', (
    tester,
  ) async {
    final apiService = _FakeLeaveApiService(const []);

    await tester.pumpWidget(
      MaterialApp(home: LeaveManagementScreen(apiService: apiService)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review and submit'));
    await tester.pumpAndSettle();

    expect(find.text('Select a start date.'), findsOneWidget);
    expect(find.text('Select an end date.'), findsOneWidget);
    expect(find.text('Enter a reason for your leave request.'), findsOneWidget);
    expect(apiService.submitCalled, isFalse);
  });
}
