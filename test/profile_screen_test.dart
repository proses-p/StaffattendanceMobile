import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance_mobile/models/profile_model.dart';
import 'package:staff_attendance_mobile/screens/profile_screen.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class _FakeProfileApiService extends ApiService {
  _FakeProfileApiService(this.profile);

  final StaffProfile profile;

  @override
  Future<StaffProfile> fetchProfile() async => profile;
}

void main() {
  testWidgets('shows authenticated profile data and optional-field fallbacks', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          apiService: _FakeProfileApiService(
            const StaffProfile(
              name: 'Amina Hassan',
              email: 'amina@example.test',
              role: 'staff',
              isActive: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Amina Hassan'), findsNWidgets(2));
    expect(find.text('amina@example.test'), findsNWidgets(2));
    expect(find.text('Not provided'), findsNWidgets(3));
    await tester.scrollUntilVisible(find.text('STAFF'), 300);
    expect(find.text('STAFF'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });
}
