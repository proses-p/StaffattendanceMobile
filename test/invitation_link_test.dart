import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance_mobile/main.dart';

void main() {
  test('parses the invitation URL generated for mobile registration', () {
    const token =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    const email = 'staff@example.test';
    final uri = Uri.https('taarifa.wadudu.co.tz', '/staff/register/$token', {
      'email': email,
    });

    final invitation = parseInvitationLink(uri);

    expect(invitation?.token, token);
    expect(invitation?.email, email);
  });

  test('ignores URLs outside the verified invitation link', () {
    final uri = Uri.https(
      'app.taarifa.wadudu.co.tz',
      '/staff/register/${'a' * 64}',
    );

    expect(parseInvitationLink(uri), isNull);
  });
}
