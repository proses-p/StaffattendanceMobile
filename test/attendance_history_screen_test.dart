import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance_mobile/models/attendance_history_model.dart';
import 'package:staff_attendance_mobile/screens/attendance_history_screen.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

void main() {
  testWidgets('shows loading then a clear empty-history state', (tester) async {
    final completer = Completer<AttendanceHistoryPage>();
    final service = _FakeApiService((_) => completer.future);

    await tester.pumpWidget(
      MaterialApp(home: AttendanceHistoryScreen(apiService: service)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(_page(currentPage: 1, lastPage: 1, total: 0));
    await tester.pumpAndSettle();

    expect(find.text('No attendance records yet'), findsOneWidget);
    expect(
      find.text('Your recorded work days will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('shows an actionable error state and retries', (tester) async {
    final service = _FakeApiService(
      (_) async => throw Exception('Network down'),
    );

    await tester.pumpWidget(
      MaterialApp(home: AttendanceHistoryScreen(apiService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unable to load attendance history'), findsOneWidget);
    expect(find.textContaining('Network down'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(service.requestedPages, [1, 1]);
  });

  testWidgets('shows attendance values and loads older server pages', (
    tester,
  ) async {
    final service = _FakeApiService((page) async {
      if (page == 1) {
        return _page(
          currentPage: 1,
          lastPage: 2,
          total: 7,
          records: [
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
        );
      }
      return _page(currentPage: 2, lastPage: 2, total: 7);
    });

    await tester.binding.setSurfaceSize(const Size(320, 780));
    await tester.pumpWidget(
      MaterialApp(home: AttendanceHistoryScreen(apiService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sat, Oct 17, 2026'), findsOneWidget);
    expect(find.text('08:30 AM'), findsOneWidget);
    expect(find.text('Not checked out'), findsOneWidget);
    expect(find.text('In progress'), findsNWidgets(2));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('Location unavailable'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('—'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Older records'));
    await tester.pumpAndSettle();

    expect(service.requestedPages, [1, 2]);
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(find.byTooltip('Newer records'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });
}

class _FakeApiService extends ApiService {
  _FakeApiService(this.loadPage);

  final Future<AttendanceHistoryPage> Function(int page) loadPage;
  final List<int> requestedPages = [];

  @override
  Future<AttendanceHistoryPage> fetchAttendanceHistory({required int page}) {
    requestedPages.add(page);
    return loadPage(page);
  }
}

AttendanceHistoryPage _page({
  required int currentPage,
  required int lastPage,
  required int total,
  List<Map<String, dynamic>> records = const [],
}) {
  return AttendanceHistoryPage.fromJson({
    'records': records,
    'current_page': currentPage,
    'last_page': lastPage,
    'per_page': 6,
    'total': total,
  });
}
