import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staff_attendance_mobile/services/trusted_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('attendance/clock');
  var monotonic = 1000;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    monotonic = 1000;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => monotonic);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'uses the server anchor and monotonic elapsed time when available',
    () async {
      final clock = TrustedClock.instance;
      await clock.anchor(DateTime.utc(2026, 11, 8, 12));
      monotonic += 2000;

      final reading = await clock.now();

      expect(reading.recordedAt, DateTime.utc(2026, 11, 8, 12, 0, 2));
      expect(reading.timeSource, 'trusted');
    },
  );

  test(
    'falls back to the device clock when monotonic time moves backwards',
    () async {
      final clock = TrustedClock.instance;
      await clock.anchor(DateTime.utc(2026, 11, 8, 12));
      monotonic = 500;

      final reading = await clock.now();

      expect(reading.timeSource, 'device');
      expect(reading.recordedAt, reading.deviceTime);
    },
  );
}
