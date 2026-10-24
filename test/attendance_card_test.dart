import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance_mobile/custom/attendance_card.dart';
import 'package:staff_attendance_mobile/models/user_status_model.dart';

void main() {
  testWidgets('places the rectangular attendance action below the time', (
    tester,
  ) async {
    var actionCount = 0;
    final status = UserStatusModel.fromJson({
      'current_time': '08:00 AM',
      'current_date': 'Thursday, October 22',
      'check_in_time': '--:-- --',
      'check_out_time': '--:-- --',
      'worked_hours': '--',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: AttendanceCard(
                status: status,
                now: DateTime(2026, 10, 22, 8),
                buttonState: 'CHECK_IN',
                onAttendanceAction: () => actionCount++,
                isSubmitting: false,
              ),
            ),
          ),
        ),
      ),
    );

    final timeTop = tester.getTopLeft(find.text('08:00 AM')).dy;
    final buttonLabel = find.text('Check In').first;
    final buttonTop = tester.getTopLeft(buttonLabel).dy;
    expect(buttonTop, greaterThan(timeTop));

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.style?.shape?.resolve({}), isA<RoundedRectangleBorder>());

    await tester.tap(buttonLabel);
    expect(actionCount, 1);
  });
}
