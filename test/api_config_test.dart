import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance_mobile/config/api_config.dart';

void main() {
  group('ApiConfig.resolveBaseUrl', () {
    test('uses the hosted HTTPS API by default on every platform', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.fuchsia,
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        expect(
          ApiConfig.resolveBaseUrl(platform),
          'https://app.taarifa.wadudu.co.tz/api/v1',
        );
      }
    });

    test('uses an explicitly configured base URL when provided', () {
      expect(
        ApiConfig.resolveBaseUrl(
          TargetPlatform.android,
          configuredBaseUrl: 'https://attendance.example/api/v1',
        ),
        'https://attendance.example/api/v1',
      );
    });
  });
}
