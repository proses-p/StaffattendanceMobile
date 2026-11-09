import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/staff_registration_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
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
      home: const LoginScreen(),
    );
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
