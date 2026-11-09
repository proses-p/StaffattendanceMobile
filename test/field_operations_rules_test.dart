import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance_mobile/services/field_service.dart';
import 'package:staff_attendance_mobile/services/sync_service.dart';

void main() {
  group('Field operation client rules', () {
    test('only supported task types are accepted', () {
      expect(FieldService.supportsTaskType('marketing'), isTrue);
      expect(FieldService.supportsTaskType('innovation_week'), isTrue);
      expect(FieldService.supportsTaskType('innovations'), isFalse);
      expect(FieldService.supportsTaskType('unknown'), isFalse);
    });

    test('transient and authorization responses retain queued events', () {
      for (final status in [401, 403, 429, 500, 503]) {
        expect(
          SyncService.shouldKeepPendingAfterRequestFailure(status),
          isTrue,
        );
      }
      for (final status in [400, 404, 422]) {
        expect(
          SyncService.shouldKeepPendingAfterRequestFailure(status),
          isFalse,
        );
      }
    });
  });
}
