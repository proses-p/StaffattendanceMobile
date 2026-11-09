import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance_mobile/screens/field_mode_screen.dart';
import 'package:staff_attendance_mobile/screens/more_screen.dart';

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
    super.didPush(route, previousRoute);
  }
}

void main() {
  testWidgets('More shows Field Mode and opens the existing screen', (
    tester,
  ) async {
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(home: const MoreScreen(), navigatorObservers: [observer]),
    );

    expect(find.text('Field Mode'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);

    final context = tester.element(find.byType(MoreScreen));
    tester
        .widget<ListTile>(find.widgetWithText(ListTile, 'Field Mode'))
        .onTap!();
    final route = observer.lastPushedRoute! as MaterialPageRoute<void>;
    expect(route.builder(context), isA<FieldModeScreen>());
  });
}
