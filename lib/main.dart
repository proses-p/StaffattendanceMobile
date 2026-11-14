import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/login_screen.dart';
import 'screens/staff_registration_screen.dart';
import 'screens/notification_service.dart';
import 'screens/dashboard_screen.dart';
import 'services/app_theme_manager.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppThemeManager.instance.load();
  await NotificationService().init();

  // await NotificationService().testNotificationIn15Seconds();

  runApp(const StaffFlowApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class StaffFlowApp extends StatefulWidget {
  const StaffFlowApp({super.key});

  @override
  State<StaffFlowApp> createState() => _StaffFlowAppState();
}

class _StaffFlowAppState extends State<StaffFlowApp>
    with WidgetsBindingObserver {
  static const _inactivityTimeout = Duration(seconds: 1200);

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  Timer? _inactivityTimer;
  late final Future<bool> _loginStatus;
  bool _sessionExpired = false;
  bool _sessionEnding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loginStatus = _checkLoginStatus();
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
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkSessionOnResume());
    }
  }

  Future<bool> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.trim().isEmpty) return false;

    final now = DateTime.now();
    final lastActiveMillis = prefs.getInt('last_active_at');
    if (lastActiveMillis != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastActiveMillis)) >=
            _inactivityTimeout) {
      await AuthService.clearLocalSession();
      _sessionExpired = true;
      return false;
    }

    final lastActive = lastActiveMillis == null
        ? now
        : DateTime.fromMillisecondsSinceEpoch(lastActiveMillis);
    if (lastActiveMillis == null) {
      await prefs.setInt('last_active_at', now.millisecondsSinceEpoch);
    }
    _armInactivityTimer(_inactivityTimeout - now.difference(lastActive));
    return true;
  }

  Future<void> _recordInteraction() async {
    if (_sessionEnding) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.trim().isEmpty) {
      _inactivityTimer?.cancel();
      return;
    }

    final now = DateTime.now();
    final lastActiveMillis = prefs.getInt('last_active_at');
    if (lastActiveMillis != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastActiveMillis)) >=
            _inactivityTimeout) {
      await _expireSession();
      return;
    }

    await prefs.setInt('last_active_at', now.millisecondsSinceEpoch);
    _armInactivityTimer(_inactivityTimeout);
  }

  Future<void> _checkSessionOnResume() async {
    if (_sessionEnding) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.trim().isEmpty) {
      _inactivityTimer?.cancel();
      return;
    }

    final now = DateTime.now();
    final lastActiveMillis = prefs.getInt('last_active_at');
    if (lastActiveMillis != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastActiveMillis)) >=
            _inactivityTimeout) {
      await _expireSession();
      return;
    }

    await prefs.setInt('last_active_at', now.millisecondsSinceEpoch);
    _armInactivityTimer(_inactivityTimeout);
  }

  void _armInactivityTimer(Duration duration) {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(
      duration.isNegative ? Duration.zero : duration,
      _expireSession,
    );
  }

  Future<void> _expireSession() async {
    if (_sessionEnding) return;
    _sessionEnding = true;
    _inactivityTimer?.cancel();

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.trim().isEmpty) {
      _sessionEnding = false;
      return;
    }

    await AuthService.clearLocalSession();
    if (!mounted) return;

    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          sessionExpired: true,
          onAuthenticated: _startSessionTimer,
        ),
      ),
      (_) => false,
    );
  }

  void _startSessionTimer() {
    _sessionEnding = false;
    unawaited(_recordInteraction());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeManager.instance.themeMode,
      builder: (context, themeMode, _) => MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'StaffFlow',
        theme: AppThemeManager.lightTheme,
        darkTheme: AppThemeManager.darkTheme,
        themeMode: themeMode,
        builder: (context, child) => Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent) unawaited(_recordInteraction());
            return KeyEventResult.ignored;
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => unawaited(_recordInteraction()),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: FutureBuilder<bool>(
          future: _loginStatus,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.data == true) {
              return const DashboardScreen();
            }

            return LoginScreen(
              sessionExpired: _sessionExpired,
              onAuthenticated: _startSessionTimer,
            );
          },
        ),
      ),
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
