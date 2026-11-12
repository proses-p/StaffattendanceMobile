import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/staff_registration_screen.dart';
import 'screens/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();

  await NotificationService().scheduleDailyReminder(
    id: 1,
    title: 'Reminder of office check in',
    body: 'Hello, remember to check in now, since you are near the office campus',
    hour: 8,   // Saa 2 Asubuhi (24-hour format)
    minute: 0,
  );

  await NotificationService().scheduleDailyReminder(
    id: 2,
    title: 'Reminder of office check out',
    body: 'Hi!, remember to check out',
    hour: 17,  // Saa 11 Jioni (24-hour format)
    minute: 0,
  );

  // await NotificationService().testNotificationIn15Seconds();

  runApp(const StaffFlowApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class StaffFlowApp extends StatefulWidget {
  const StaffFlowApp({super.key});

  @override
  State<StaffFlowApp> createState() => _StaffFlowAppState();
}

class _StaffFlowAppState extends State<StaffFlowApp> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initializeLinks();
  }

  Future<void> _initializeLinks() async {

    try {
      final Uri? initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleInvitationLink(initialUri);
      }
    } catch (e) {
      debugPrint('Initial link error: $e');
    }
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleInvitationLink,
      onError: (Object error) {
        debugPrint('Invitation link error: $error');
      },
    );
  }

  void _handleInvitationLink(Uri uri) {
    final invitation = parseInvitationLink(uri);
    if (invitation == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (navigatorKey.currentState == null) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => StaffRegistrationScreen(
            token: invitation.token,
            email: invitation.email,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'StaffFlow',
      home: FutureBuilder<bool>(
        future: _checkLoginStatus(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
        }
        // Kama token ipo (true), fungua Dashboard moja kwa moja
        if (snapshot.data == true) {
          return const DashboardScreen();
        }

        // Vinginevyo fungua LoginScreen
          return const LoginScreen();
        },
      ),
    );
  }

  Future<bool> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return token != null && token.trim().isNotEmpty;
  }
}

({String token, String email})? parseInvitationLink(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host != 'app.taarifa.wadudu.co.tz' ||
      uri.pathSegments.length != 3 ||
      uri.pathSegments[0] != 'staff' ||
      uri.pathSegments[1] != 'register') {
    return null;
  }

  return (
    token: uri.pathSegments[2],
    email: uri.queryParameters['email'] ?? '',
  );
}
